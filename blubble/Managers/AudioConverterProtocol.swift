import Foundation
import AVFoundation

protocol AudioConverterProtocol {
    func convert(buffer: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) throws -> AVAudioPCMBuffer
}
