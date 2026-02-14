import Foundation
import AVFoundation
import OSLog

final class AudioConverterService: AudioConverterProtocol {
    private let logger = Logger(subsystem: "team1.blubble", category: "AudioConverterService")
    private var converter: AVAudioConverter?
    
    func convert(buffer: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) throws -> AVAudioPCMBuffer {
        if converter == nil || converter?.inputFormat != buffer.format || converter?.outputFormat != targetFormat {
            converter = AVAudioConverter(from: buffer.format, to: targetFormat)
            if converter == nil {
                logger.error("Failed to create audio converter from \(buffer.format) to \(targetFormat)")
                throw AudioConverterError.creationFailed
            }
        }
        
        guard let converter = converter else { throw AudioConverterError.creationFailed }
        
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let targetFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetFrameCapacity) else {
            throw AudioConverterError.bufferAllocationFailed
        }
        
        var error: NSError? = nil
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        if let error = error {
            logger.error("Audio conversion error: \(error.localizedDescription)")
            throw error
        }
        
        return outputBuffer
    }
    
    enum AudioConverterError: Error {
        case creationFailed
        case bufferAllocationFailed
    }
}
