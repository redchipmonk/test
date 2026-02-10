//
//  AudioDiarizer.swift
//  blubble
//
//  Created by Alvin Ngoc Le on 2/9/26.
//

import Foundation
import FluidAudio
import AVFoundation
import CoreML

actor AudioDiarizer {
    private var diarizer: SortformerDiarizer?
    private var isModelLoaded: Bool = false
    
    enum DiarizerError: Error {
        case modelNotLoaded
        case modelLoadingFailed
        case processingFailed
    }
    
    func loadModel() async throws {
        // Prevent double loading
        guard !isModelLoaded else { return }
        
        do {
            print("⏳ AudioDiarizer: Initializing Sortformer config...")
            // Create default config
            let config = SortformerConfig.default
            
            print("⏳ AudioDiarizer: Creating diarizer instance...")
            // Create diarizer with config first (matches documentation pattern)
            let newDiarizer = SortformerDiarizer(config: config)
            
            print("⏳ AudioDiarizer: Downloading/Loading Sortformer models...")
            // Load models from HuggingFace (or cache)
            // Use CPU-only on Simulator to avoid Metal/MPSGraph errors
            #if targetEnvironment(simulator)
            let computeUnits: MLComputeUnits = .cpuOnly
            #else
            let computeUnits: MLComputeUnits = .all
            #endif
            
            let models = try await SortformerModels.loadFromHuggingFace(config: config, computeUnits: computeUnits)
            
            print("⏳ AudioDiarizer: Initializing pipeline...")
            newDiarizer.initialize(models: models)
            
            self.diarizer = newDiarizer
            self.isModelLoaded = true
            print("✅ AudioDiarizer: Ready (Sortformer)")
        } catch {
            print("❌ AudioDiarizer: Failed to load models - \(error)")
            throw DiarizerError.modelLoadingFailed
        }
    }
    
    /// Process a checking of audio and return the result for that chunk (if available)
    func process(buffer: AVAudioPCMBuffer) async throws -> SortformerChunkResult? {
        guard let diarizer = diarizer, isModelLoaded else {
            throw DiarizerError.modelNotLoaded
        }
        
        // Convert AVAudioPCMBuffer to [Float] for FluidAudio
        guard let channelData = buffer.floatChannelData?[0] else {
            throw DiarizerError.processingFailed
        }
        
        let frameCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        
        // Process samples using Sortformer's streaming API
        let result = try diarizer.processSamples(samples)
        
        // Debug logging for Sortformer output
        if let result = result {
            print("🔍 [Sortformer] Chunk Result:")
            print("   Frame Count: \(result.frameCount)")
            print("   Speaker Predictions Count: \(result.speakerPredictions.count)")
            
            // Show first few predictions as a sample
            let sampleSize = min(8, result.speakerPredictions.count)
            if sampleSize > 0 {
                let sample = result.speakerPredictions.prefix(sampleSize)
                print("   First \(sampleSize) predictions: \(sample.map { String(format: "%.3f", $0) })")
            }
            
            // Show predictions for the last frame (most recent)
            let numSpeakers = 4
            if result.frameCount > 0 {
                let lastFrameIndex = result.frameCount - 1
                let startIdx = lastFrameIndex * numSpeakers
                let endIdx = startIdx + numSpeakers
                
                if endIdx <= result.speakerPredictions.count {
                    let lastFrameProbs = result.speakerPredictions[startIdx..<endIdx]
                    print("   Latest frame [Sp1, Sp2, Sp3, Sp4]: [\(lastFrameProbs.map { String(format: "%.3f", $0) }.joined(separator: ", "))]")
                    
                    // Identify active speakers (prob > 0.5)
                    let activeSpeakers = lastFrameProbs.enumerated().filter { $0.element > 0.5 }.map { "Speaker \($0.offset + 1) (\(String(format: "%.3f", $0.element)))" }
                    if !activeSpeakers.isEmpty {
                        print("   Active speakers: \(activeSpeakers.joined(separator: ", "))")
                    } else {
                        print("   Active speakers: None (all below 0.5ß threshold)")
                    }
                }
            }
        } else {
            print("🔍 [Sortformer] No result returned for this chunk")
        }
        
        return result
    }
    
    // Note: Sortformer does NOT support SpeakerManager or Embedding Extraction compatible with the previous flow.
    // We remove getSpeakerManager() and extractEmbedding().
}
