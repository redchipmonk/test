import Foundation
import AVFoundation

protocol AudioCaptureProtocol {
    func startCapture() throws -> AsyncStream<AVAudioPCMBuffer>
    func stopCapture()
}
