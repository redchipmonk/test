//
//  VoiceIdentityManager.swift
//  blubble
//
//  Created by Alvin Ngoc Le on 2/9/26.
//

import Foundation
import Combine
import AVFoundation
import FluidAudio

@MainActor
final class VoiceIdentityManager: ObservableObject {
    
    // Simplified state for Sortformer
    // Sortformer outputs 4 fixed slots. 
    @Published var speakerProbabilities: [Float] = [0, 0, 0, 0]
    @Published var currentSpeaker: String? = nil
    
    private let diarizer = AudioDiarizer()
    private let audioConverter = AudioConverter()
    
    // We no longer manage the audio engine in here for calibration.
    // We only process buffers from AudioInputManager.
    
    init() {}
    
    func initialize() async {
        do {
            try await diarizer.loadModel()
        } catch {
            print("Failed to initialize diarizer: \(error)")
        }
    }
    
    // Process buffer from external source (AudioInputManager)
    func processStreamBuffer(_ buffer: AVAudioPCMBuffer) async {
        do {
            print("📥 [VoiceIdentityManager] Input buffer: \(buffer.format.sampleRate) Hz, \(buffer.format.channelCount) channel(s)")
            
            // Convert to 16 kHz mono Float32 as required by Sortformer
            let convertedSamples = try audioConverter.resampleBuffer(buffer)
            
            print("✅ [VoiceIdentityManager] Converted to 16 kHz: \(convertedSamples.count) samples")
            
            // Create a 16kHz buffer from the converted samples
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
                print("⚠️ [VoiceIdentityManager] Failed to create 16kHz buffer")
                return
            }
            
            convertedBuffer.frameLength = AVAudioFrameCount(convertedSamples.count)
            if let floatData = convertedBuffer.floatChannelData?[0] {
                convertedSamples.withUnsafeBufferPointer { ptr in
                    floatData.update(from: ptr.baseAddress!, count: convertedSamples.count)
                }
            }
            
            // Get chunk result from Sortformer with properly formatted audio
            if let result = try await diarizer.process(buffer: convertedBuffer) {
                // Update UI state
                updateState(from: result)
            }
        } catch {
            print("⚠️ [VoiceIdentityManager] Audio conversion or processing error: \(error)")
        }
    }
    
    private func updateState(from result: SortformerChunkResult) {
        // Result.speakerPredictions contains flattened [frameCount * 4] probabilities.
        // We want to visualize the *latest* frame to show "who is speaking now".
        
        let numSpeakers = 4
        let frameCount = result.frameCount
        
        guard frameCount > 0 else { return }
        
        // Get the probabilities for the last frame in this chunk
        let lastFrameIndex = frameCount - 1
        let startIdx = lastFrameIndex * numSpeakers
        let endIdx = startIdx + numSpeakers
        
        if endIdx <= result.speakerPredictions.count {
            let lastFrameProbs = Array(result.speakerPredictions[startIdx..<endIdx])
            self.speakerProbabilities = lastFrameProbs
            
            print("🎯 [VoiceIdentityManager] Processing Sortformer Result:")
            print("   Speaker Probabilities: [\(lastFrameProbs.map { String(format: "%.3f", $0) }.joined(separator: ", "))]")
            
            // Determine dominant speaker
            // Threshold of 0.5 is standard for sigmoid output
            if let maxProb = lastFrameProbs.max(), let maxIndex = lastFrameProbs.firstIndex(of: maxProb), maxProb > 0.5 {
                self.currentSpeaker = "Speaker \(maxIndex + 1)"
                print("   Current Speaker: \(self.currentSpeaker ?? "None") (probability: \(String(format: "%.3f", maxProb)))")
            } else {
                self.currentSpeaker = nil
                print("   Current Speaker: None (max probability \(String(format: "%.3f", lastFrameProbs.max() ?? 0)) below 0.5 threshold)")
            }
        }
    }
}
