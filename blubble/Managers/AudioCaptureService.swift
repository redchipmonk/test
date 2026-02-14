import Foundation
import AVFoundation
import OSLog

final class AudioCaptureService: AudioCaptureProtocol {
    private let logger = Logger(subsystem: "team1.blubble", category: "AudioCaptureService")
    private let audioEngine = AVAudioEngine()
    private let inputBus: AVAudioNodeBus = 0
    
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    
    func startCapture() throws -> AsyncStream<AVAudioPCMBuffer> {
        guard !audioEngine.isRunning else {
            throw AudioCaptureError.alreadyRunning
        }
        
        try configureAudioSession()
        
        let stream = AsyncStream<AVAudioPCMBuffer> { continuation in
            self.continuation = continuation
            
            let inputNode = audioEngine.inputNode
            let nativeFormat = inputNode.inputFormat(forBus: inputBus)
            
            guard nativeFormat.channelCount > 0 else {
                logger.error("AudioCaptureService: Input node format has 0 channels.")
                continuation.finish()
                return
            }
            
            inputNode.removeTap(onBus: inputBus)
            inputNode.installTap(onBus: inputBus, bufferSize: 4096, format: nativeFormat) { buffer, _ in
                continuation.yield(buffer)
            }
            
            do {
                try audioEngine.start()
            } catch {
                self.logger.error("Failed to start audio engine: \(error.localizedDescription)")
                continuation.finish()
            }
            
            continuation.onTermination = { @Sendable _ in
                Task { [weak self] in
                    await self?.stopCapture()
                }
            }
        }
        
        return stream
    }
    
    @MainActor
    func stopCapture() {
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: inputBus)
            audioEngine.stop()
        }
        continuation?.finish()
        continuation = nil
    }
    
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.mixWithOthers, .allowBluetoothHFP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }
    
    enum AudioCaptureError: Error {
        case alreadyRunning
        case initializationFailed
    }
}
