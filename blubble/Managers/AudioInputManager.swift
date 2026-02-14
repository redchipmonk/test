import Foundation
import AVFoundation
import Accelerate
import Speech
import Combine
import OSLog

@MainActor
final class AudioInputManager: NSObject, AudioInputManaging, ObservableObject {
    private let logger = Logger(subsystem: "team1.blubble", category: "AudioInputManager")
    
    @Published var currentRMS: Float = 0.0
    @Published var currentZCR: Float = 0.0
    @Published var isRunning: Bool = false
    
    @Published var transcript: String = ""
    var currentSpeaker: Int? {
        if let speakerString = identityManager.currentSpeaker {
            if let id = Int(speakerString.components(separatedBy: " ").last ?? "") {
                return id - 1
            }
        }
        return nil
    }
    
    @Published var chatHistory: [ChatMessage] = []
    
    let identityManager: any VoiceIdentityManaging

    private let apiKey: String
    private let audioEngine = AVAudioEngine()
    
    private let inputBus: AVAudioNodeBus = 0
    private var webSocketTask: URLSessionWebSocketTask?
    
    private let analysisQueue = DispatchQueue(label: "com.blubble.audioAnalysis", qos: .userInteractive)
    
    init(apiKey: String, identityManager: any VoiceIdentityManaging) {
        self.apiKey = apiKey
        self.identityManager = identityManager
        super.init()
        requestPermissions()
    }
    
    func startMonitoring() {
        guard !audioEngine.isRunning else { return }
        
        setupWebSocket()
        
        do {
            try configureAudioSession()
            setupAudioEngine()
            try audioEngine.start()
            isRunning = true
        } catch {
            logger.error("Failed to start audio engine: \(error.localizedDescription)")
            stopMonitoring()
        }
    }

    func stopMonitoring() {
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: inputBus)
            audioEngine.stop()
        }
        
        isRunning = false
        
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
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
        webSocketTask?.sendPing { error in
            if let error = error {
                self.logger.error("WebSocket Ping Error: \(error.localizedDescription)")
            } else if self.isRunning {
                DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
                    self?.ping()
                }
            }
        }
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .failure(let error):
                self.logger.error("WebSocket receive error: \(error.localizedDescription)")
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(_):
                    break
                @unknown default:
                    break
                }
                
                if self.isRunning {
                    self.receiveMessage()
                }
            }
        }
    }
    
    private func handleMessage(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8) else { return }
        
        do {
            let response = try JSONDecoder().decode(DeepgramResponse.self, from: data)
            let isFinal = response.is_final ?? false
            
            if let alternative = response.channel?.alternatives.first {
                let newTranscript = alternative.transcript
                logger.debug("Deepgram received: '\(newTranscript)' (is_final: \(isFinal))")
                
                Task { @MainActor in
                    let speakerID = self.currentSpeaker ?? 0
                    
                    if isFinal {
                        if !newTranscript.isEmpty {
                            let message = ChatMessage(
                                text: newTranscript,
                                speaker: speakerID,
                                timestamp: Date()
                            )
                            self.chatHistory.append(message)
                            self.transcript = ""
                        }
                    } else {
                        self.transcript = newTranscript
                    }
                }
            }
        } catch {
            logger.error("JSON decoding error: \(error.localizedDescription)")
        }
    }
    
    private func setupAudioEngine() {
        let inputNode = audioEngine.inputNode
        let nativeFormat = inputNode.inputFormat(forBus: inputBus)
        
        guard nativeFormat.channelCount > 0 else {
            logger.error("AudioInputManager: Input node format has 0 channels. Aborting setup.")
            return
        }
        
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 48000,
            channels: 1,
            interleaved: true
        )!
        
        guard let formatConverter = AVAudioConverter(from: nativeFormat, to: targetFormat) else {
            logger.error("AudioInputManager: Failed to create audio converter.")
            return
        }
        
        inputNode.removeTap(onBus: inputBus)
        inputNode.installTap(onBus: inputBus, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            
            self.analyzeLevels(buffer)
            
            Task {
                await self.identityManager.processStreamBuffer(buffer)
            }
            
            self.convertAndStream(buffer: buffer, converter: formatConverter, targetFormat: targetFormat)
        }
    }
    
    private func convertAndStream(buffer: AVAudioPCMBuffer, converter: AVAudioConverter?, targetFormat: AVAudioFormat) {
        guard let converter = converter else { return }
        
        let inputFrameCount = buffer.frameLength
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let targetFrameCapacity = AVAudioFrameCount(Double(inputFrameCount) * ratio)
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetFrameCapacity) else { return }
        
        var error: NSError? = nil
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        if let error = error {
            logger.error("Audio conversion error: \(error.localizedDescription)")
            return
        }
        
        if outputBuffer.frameLength > 0 {
            sendAudioData(outputBuffer)
        }
    }
    
    private func sendAudioData(_ buffer: AVAudioPCMBuffer) {
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

    private func analyzeLevels(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = vDSP_Length(buffer.frameLength)

        var rms: Float = 0
        vDSP_rmsqv(channelData, 1, &rms, frameCount)

        var crossings: Float = 0
        if frameCount > 1 {
            for i in 0..<Int(frameCount - 1) {
                 if (channelData[i] > 0 && channelData[i + 1] <= 0) ||
                    (channelData[i] < 0 && channelData[i + 1] >= 0) {
                     crossings += 1
                 }
            }
        }

        let zcr = crossings / Float(frameCount)
        
        Task { @MainActor in
            self.currentRMS = rms
            self.currentZCR = zcr
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.mixWithOthers, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func requestPermissions() {
        AVAudioSession.sharedInstance().requestRecordPermission { _ in }
    }
}

extension AudioInputManager: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        logger.info("WebSocket Connected to Deepgram")
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "No reason"
        logger.error("WebSocket Closed: Code \(closeCode.rawValue), Reason: \(reasonString)")
    }
}
