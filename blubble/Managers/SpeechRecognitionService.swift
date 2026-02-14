import Foundation
import AVFoundation
import OSLog

final class SpeechRecognitionService: NSObject, SpeechRecognitionProtocol {
    private let logger = Logger(subsystem: "team1.blubble", category: "SpeechRecognitionService")
    private let apiKey: String
    private let converterService: any AudioConverterProtocol
    private var webSocketTask: URLSessionWebSocketTask?
    private var continuation: AsyncStream<SpeechRecognitionResult>.Continuation?
    
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 48000,
        channels: 1,
        interleaved: true
    )!
    
    private var isRunning = false
    
    init(apiKey: String, converterService: any AudioConverterProtocol) {
        self.apiKey = apiKey
        self.converterService = converterService
        super.init()
    }
    
    func startRecognition() async -> AsyncStream<SpeechRecognitionResult> {
        isRunning = true
        return AsyncStream { continuation in
            self.continuation = continuation
            setupWebSocket()
            
            continuation.onTermination = { @Sendable _ in
                Task { [weak self] in
                    await self?.stopRecognition()
                }
            }
        }
    }
    
    func sendAudio(_ buffer: AVAudioPCMBuffer) {
        guard isRunning else { return }
        
        do {
            let convertedBuffer = try converterService.convert(buffer: buffer, to: targetFormat)
            if convertedBuffer.frameLength > 0 {
                sendConvertedData(convertedBuffer)
            }
        } catch {
            logger.error("Failed to convert audio: \(error.localizedDescription)")
        }
    }
    
    private func sendConvertedData(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.int16ChannelData else { return }
        
        let channelPtr = channelData[0]
        let dataSize = Int(buffer.frameLength) * 2
        let data = Data(bytes: channelPtr, count: dataSize)
        
        let message = URLSessionWebSocketTask.Message.data(data)
        webSocketTask?.send(message) { error in
            if let error = error {
                self.logger.error("WebSocket send error: \(error.localizedDescription)")
            }
        }
    }
    
    func stopRecognition() {
        isRunning = false
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        continuation?.finish()
        continuation = nil
    }
    
    private func setupWebSocket() {
        var components = URLComponents(string: "wss://api.deepgram.com/v1/listen")
        components?.queryItems = [
            URLQueryItem(name: "model", value: "nova-2"),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "diarize", value: "false"),
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "48000")
        ]
        
        guard let url = components?.url else { return }
        
        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        
        ping()
        receiveMessage()
    }
    
    private func ping() {
        guard isRunning else { return }
        webSocketTask?.sendPing { [weak self] error in
            if let error = error {
                self?.logger.error("WebSocket Ping Error: \(error.localizedDescription)")
            } else {
                DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                    self?.ping()
                }
            }
        }
    }
    
    private func receiveMessage() {
        guard isRunning else { return }
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .failure(let error):
                self.logger.error("WebSocket receive error: \(error.localizedDescription)")
                self.continuation?.yield(.error(error))
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(_):
                    break
                @unknown default:
                    break
                }
                self.receiveMessage()
            }
        }
    }
    
    private func handleMessage(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8) else { return }
        
        do {
            let response = try JSONDecoder().decode(DeepgramResponse.self, from: data)
            let isFinal = response.is_final ?? false
            
            if let alternative = response.channel?.alternatives.first {
                let transcript = alternative.transcript
                if isFinal {
                    if !transcript.isEmpty {
                        continuation?.yield(.final(transcript))
                    }
                } else {
                    continuation?.yield(.partial(transcript))
                }
            }
        } catch {
            logger.error("JSON decoding error: \(error.localizedDescription)")
        }
    }
}

extension SpeechRecognitionService: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        logger.info("WebSocket Connected to Deepgram")
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "No reason"
        logger.error("WebSocket Closed: Code \(closeCode.rawValue), Reason: \(reasonString)")
    }
}
