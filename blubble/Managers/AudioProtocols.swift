import Foundation
import AVFoundation
import FluidAudio
import Combine

// MARK: - Audio Diarizer Protocol
protocol AudioDiarizing: Actor {
    func loadModel() async throws
    func process(nativeBuffer: AVAudioPCMBuffer) async throws -> SortformerChunkResult?
}

// MARK: - Voice Identity Manager Protocol
@MainActor
protocol VoiceIdentityManaging: AnyObject {
    var speakerProbabilities: [Float] { get }
    var currentSpeaker: String? { get }
    var isInitializing: Bool { get }
    
    func initialize() async
    func processStreamBuffer(_ buffer: AVAudioPCMBuffer) async
}

// MARK: - Audio Input Manager Protocol
@MainActor
protocol AudioInputManaging: ObservableObject {
    var isRunning: Bool { get }
    var transcript: String { get }
    var chatHistory: [ChatMessage] { get }
    var currentSpeaker: Int? { get }
    
    func startMonitoring()
    func stopMonitoring()
}
