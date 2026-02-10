//
//  AudioDiarizer.swift
//  blubble
//
//  Created by Alvin Ngoc Le on 2/9/26.
//

import Foundation
import FluidAudio
import AVFoundation

actor AudioDiarizer {
    private var diarizer: DiarizerManager?
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
            print("⏳ AudioDiarizer: Downloading models...")
            let models = try await DiarizerModels.downloadIfNeeded()
            
            print("⏳ AudioDiarizer: Initializing manager...")
            let newDiarizer = DiarizerManager()
            newDiarizer.initialize(models: models)
            
            self.diarizer = newDiarizer
            self.isModelLoaded = true
            print("✅ AudioDiarizer: Ready")
        } catch {
            print("❌ AudioDiarizer: Failed to load models - \(error)")
            throw DiarizerError.modelLoadingFailed
        }
    }
    
    func process(buffer: AVAudioPCMBuffer) async throws -> DiarizationResult {
        guard let diarizer = diarizer, isModelLoaded else {
            throw DiarizerError.modelNotLoaded
        }
        
        // Convert AVAudioPCMBuffer to [Float] for FluidAudio
        guard let channelData = buffer.floatChannelData?[0] else {
            throw DiarizerError.processingFailed
        }
        
        let frameCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        
        // Process samples
        // Note: We use performCompleteDiarization for chunks. 
        // For strict streaming we might want a different approach, but performCompleteDiarization with small chunks (3-5s) 
        // is recommended in the docs for real-time capture.
        return try diarizer.performCompleteDiarization(samples)
    }
    
    func getSpeakerManager() -> SpeakerManager? {
        return diarizer?.speakerManager
    }
    
    /// Extract embedding from raw samples [Float]
    func extractEmbedding(from samples: [Float]) async throws -> [Float] {
        guard let diarizer = diarizer, let extractor = diarizer.embeddingExtractor else {
            throw DiarizerError.modelNotLoaded
        }
        
        // Create a mask of 1.0s for the entire duration (assuming proper enrollment clip)
        // The extractor expects [[Float]] where outer is speakers, inner is frames.
        // We simulate 1 speaker active for the whole clip.
        
        // Note: We need to know the frame count expected by the extractor or just pass a mask matching the audio length?
        // Looking at EmbeddingExtractor code provided by user/docs:
        // "numMasksInChunk = (firstMask.count * audio.count + 80_000) / 160_000" implies some ratio?
        // Actually the user snippet shows:
        // "let numFrames = slidingFeature.data[0].count" in DiarizerManager.
        // And "masks.append(speakerMask)" where speakerMask has length numFrames.
        
        // Wait, the EmbeddingExtractor.getEmbeddings takes `audio` and `masks`.
        // The mask length seems to be related to model output frames.
        // Pyannote segmentation usually outputs frames every ~16ms.
        // If we don't know the exact frame count, we might fail.
        
        // ALTERNATIVE:
        // Run `performCompleteDiarization` on the enrollment clip.
        // Find the speaker segment with the longest duration (should be our user).
        // Return that embedding.
        // This is robust because it uses the real segmentation model to find the speech.
        
        let result = try diarizer.performCompleteDiarization(samples)
        
        // Find the most prominent speaker
        let speakerDurations = result.segments.reduce(into: [String: Float]()) { dict, segment in
            dict[segment.speakerId, default: 0] += (segment.endTimeSeconds - segment.startTimeSeconds)
        }
        
        guard let bestSpeakerId = speakerDurations.max(by: { $0.value < $1.value })?.key,
              let bestSegment = result.segments.first(where: { $0.speakerId == bestSpeakerId }) else {
            throw DiarizerError.processingFailed
        }
        
        return bestSegment.embedding
    }
    
    /// Extract embedding from a buffer for calibration
    func extractEmbedding(from buffer: AVAudioPCMBuffer) async throws -> [Float] {
        guard let channelData = buffer.floatChannelData?[0] else {
            throw DiarizerError.processingFailed
        }
        
        let frameCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        return try await extractEmbedding(from: samples)
    }
}
