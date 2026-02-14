import Foundation
import FluidAudio
import AVFoundation
import CoreML
import OSLog

actor AudioDiarizer: AudioDiarizing {
    private let logger = Logger(subsystem: "team1.blubble", category: "AudioDiarizer")
    private var diarizer: SortformerDiarizer?
    private var isModelLoaded: Bool = false
    private let audioConverter = AudioConverter()
    
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
    
    func process(nativeBuffer buffer: AVAudioPCMBuffer) async throws -> SortformerChunkResult? {
        guard let diarizer = diarizer, isModelLoaded else {
            logger.error("process() failed: diarizer is \(String(describing: self.diarizer)), isModelLoaded: \(self.isModelLoaded)")
            throw DiarizerError.modelNotLoaded
        }
        
        // 1. Resample to 16kHz
        let convertedSamples = try audioConverter.resampleBuffer(buffer)
        
        // 2. Prepare 16kHz buffer for diarizer
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!
        
        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: AVAudioFrameCount(convertedSamples.count)
        ) else {
            logger.warning("Failed to create 16kHz buffer")
            return nil
        }
        
        convertedBuffer.frameLength = AVAudioFrameCount(convertedSamples.count)
        if let floatData = convertedBuffer.floatChannelData?[0] {
            convertedSamples.withUnsafeBufferPointer { ptr in
                floatData.update(from: ptr.baseAddress!, count: convertedSamples.count)
            }
        }
        
        // 3. Process with Sortformer
        let result = try diarizer.processSamples(Array(convertedSamples))
        
        if let result = result {
            logger.debug("[Sortformer] Chunk Result: Frame Count: \(result.frameCount)")
        }
        
        return result
    }
}
