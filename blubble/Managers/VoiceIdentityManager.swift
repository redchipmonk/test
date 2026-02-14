import Foundation
import Combine
import AVFoundation
import FluidAudio
import OSLog

@MainActor
final class VoiceIdentityManager: ObservableObject {
    private let logger = Logger(subsystem: "team1.blubble", category: "VoiceIdentityManager")
    
    @Published var speakerProbabilities: [Float] = [0, 0, 0, 0]
    @Published var currentSpeaker: String? = nil
    
    private let diarizer = AudioDiarizer()
    private let audioConverter = AudioConverter()
    
    init() {}
    
    func initialize() async {
        do {
            try await diarizer.loadModel()
        } catch {
            logger.error("Failed to initialize diarizer: \(error.localizedDescription)")
        }
    }
    
    func processStreamBuffer(_ buffer: AVAudioPCMBuffer) async {
        do {
            logger.debug("Input buffer: \(buffer.format.sampleRate) Hz, \(buffer.format.channelCount) channel(s)")
            
            let convertedSamples = try audioConverter.resampleBuffer(buffer)
            
            logger.debug("Converted to 16 kHz: \(convertedSamples.count) samples")
            
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
                return
            }
            
            convertedBuffer.frameLength = AVAudioFrameCount(convertedSamples.count)
            if let floatData = convertedBuffer.floatChannelData?[0] {
                convertedSamples.withUnsafeBufferPointer { ptr in
                    floatData.update(from: ptr.baseAddress!, count: convertedSamples.count)
                }
            }
            
            if let result = try await diarizer.process(buffer: convertedBuffer) {
                updateState(from: result)
            }
        } catch {
            logger.error("Audio conversion or processing error: \(error.localizedDescription)")
        }
    }
    
    private func updateState(from result: SortformerChunkResult) {
        let numSpeakers = 4
        let frameCount = result.frameCount
        
        guard frameCount > 0 else { return }
        
        let lastFrameIndex = frameCount - 1
        let startIdx = lastFrameIndex * numSpeakers
        let endIdx = startIdx + numSpeakers
        
        if endIdx <= result.speakerPredictions.count {
            let lastFrameProbs = Array(result.speakerPredictions[startIdx..<endIdx])
            self.speakerProbabilities = lastFrameProbs
            
            logger.debug("Processing Sortformer Result:")
            logger.debug("   Speaker Probabilities: [\(lastFrameProbs.map { String(format: "%.3f", $0) }.joined(separator: ", "))]")
            
            if let maxProb = lastFrameProbs.max(), let maxIndex = lastFrameProbs.firstIndex(of: maxProb), maxProb > 0.5 {
                self.currentSpeaker = "Speaker \(maxIndex + 1)"
                logger.debug("   Current Speaker: \(self.currentSpeaker ?? "None") (probability: \(String(format: "%.3f", maxProb)))")
            } else {
                self.currentSpeaker = nil
                logger.debug("   Current Speaker: None (max probability \(String(format: "%.3f", lastFrameProbs.max() ?? 0)) below 0.5 threshold)")
            }
        }
    }
}
