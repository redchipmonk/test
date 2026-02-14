import Foundation
import FluidAudio
import AVFoundation
import CoreML
import OSLog

actor AudioDiarizer: AudioDiarizing {
    private let logger = Logger(subsystem: "team1.blubble", category: "AudioDiarizer")
    private var diarizer: SortformerDiarizer?
    private var isModelLoaded: Bool = false
    
    enum DiarizerError: Error {
        case modelNotLoaded
        case modelLoadingFailed
        case processingFailed
    }
    
    func loadModel() async throws {
        logger.info("loadModel() called. current isModelLoaded: \(self.isModelLoaded)")
        guard !isModelLoaded else { 
            logger.info("Model already loaded, skipping.")
            return 
        }
        
        do {
            logger.info("Initializing Sortformer config...")
            let config = SortformerConfig.default
            
            logger.info("Creating diarizer instance...")
            let newDiarizer = SortformerDiarizer(config: config)
            
            logger.info("Downloading/Loading Sortformer models...")
            #if targetEnvironment(simulator)
            let computeUnits: MLComputeUnits = .cpuOnly
            #else
            let computeUnits: MLComputeUnits = .all
            #endif
            
            let models = try await SortformerModels.loadFromHuggingFace(config: config, computeUnits: computeUnits)
            
            newDiarizer.initialize(models: models)
            
            self.diarizer = newDiarizer
            self.isModelLoaded = true
            logger.info("Ready (Sortformer)")
        } catch {
            logger.error("Failed to load models: \(error.localizedDescription)")
            throw DiarizerError.modelLoadingFailed
        }
    }
    
    func process(buffer: AVAudioPCMBuffer) async throws -> SortformerChunkResult? {
        guard let diarizer = diarizer, isModelLoaded else {
            logger.error("process() failed: diarizer is \(String(describing: self.diarizer)), isModelLoaded: \(self.isModelLoaded)")
            throw DiarizerError.modelNotLoaded
        }
        
        guard let channelData = buffer.floatChannelData?[0] else {
            throw DiarizerError.processingFailed
        }
        
        let frameCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        
        let result = try diarizer.processSamples(samples)
        
        if let result = result {
            logger.debug("[Sortformer] Chunk Result:")
            logger.debug("   Frame Count: \(result.frameCount)")
            logger.debug("   Speaker Predictions Count: \(result.speakerPredictions.count)")
            
            let sampleSize = min(8, result.speakerPredictions.count)
            if sampleSize > 0 {
                let sample = result.speakerPredictions.prefix(sampleSize)
                logger.debug("   First \(sampleSize) predictions: \(sample.map { String(format: "%.3f", $0) })")
            }
            
            let numSpeakers = 4
            if result.frameCount > 0 {
                let lastFrameIndex = result.frameCount - 1
                let startIdx = lastFrameIndex * numSpeakers
                let endIdx = startIdx + numSpeakers
                
                if endIdx <= result.speakerPredictions.count {
                    let lastFrameProbs = result.speakerPredictions[startIdx..<endIdx]
                    logger.debug("   Latest frame [Sp1, Sp2, Sp3, Sp4]: [\(lastFrameProbs.map { String(format: "%.3f", $0) }.joined(separator: ", "))]")
                    
                    let activeSpeakers = lastFrameProbs.enumerated().filter { $0.element > 0.5 }.map { "Speaker \($0.offset + 1) (\(String(format: "%.3f", $0.element)))" }
                    if !activeSpeakers.isEmpty {
                        logger.debug("   Active speakers: \(activeSpeakers.joined(separator: ", "))")
                    } else {
                        logger.debug("   Active speakers: None (all below 0.5 threshold)")
                    }
                }
            }
        } else {
            logger.debug("[Sortformer] No result returned for this chunk")
        }
        
        return result
    }
}
