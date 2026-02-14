import Foundation
import Combine
import AVFoundation
import FluidAudio
import OSLog

@MainActor
final class VoiceIdentityManager: VoiceIdentityManaging {
    private let logger = Logger(subsystem: "team1.blubble", category: "VoiceIdentityManager")
    
    @Published var speakerProbabilities: [Float] = [0, 0, 0, 0]
    @Published var currentSpeaker: String? = nil
    @Published var isInitializing: Bool = false
    
    private let diarizer: any AudioDiarizing
    
    init(diarizer: any AudioDiarizing) {
        self.diarizer = diarizer
    }
    
    func initialize() async {
        logger.info("initialize() called on VoiceIdentityManager")
        isInitializing = true
        do {
            try await diarizer.loadModel()
            logger.info("diarizer.loadModel() successfully returned")
        } catch {
            logger.error("Failed to initialize diarizer: \(error.localizedDescription)")
        }
        isInitializing = false
    }
    
    func processStreamBuffer(_ buffer: AVAudioPCMBuffer) async {
        do {
            if let result = try await diarizer.process(nativeBuffer: buffer) {
                updateState(from: result)
            }
        } catch {
            logger.error("Diarization processing error: \(error.localizedDescription)")
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
