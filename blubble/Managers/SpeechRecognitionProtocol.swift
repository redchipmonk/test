import Foundation
import AVFoundation

protocol SpeechRecognitionProtocol {
    func startRecognition() async -> AsyncStream<SpeechRecognitionResult>
    func sendAudio(_ buffer: AVAudioPCMBuffer)
    func stopRecognition()
}

enum SpeechRecognitionResult {
    case partial(String)
    case final(String)
    case error(Error)
}
