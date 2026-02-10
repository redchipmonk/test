//
//  AudioInputManager.swift
//  blubble
//
//  Created by Alvin Ngoc Le on 1/28/26.
//

import Foundation
import AVFoundation
import Accelerate
import Speech
import Combine

@MainActor
final class AudioInputManager: ObservableObject {
    @Published var currentRMS: Float = 0.0
    @Published var currentZCR: Float = 0.0
    @Published var isRunning: Bool = false
    
    @Published var transcript: String = ""
    // currentSpeaker is now derived from VoiceIdentityManager
    var currentSpeaker: Int? {
        if identityManager.isUserSpeaking { return 0 }
        if identityManager.isPartnerSpeaking { return 1 }
        return nil
    }
    
    @Published var chatHistory: [ChatMessage] = []
    
    // Inject VoiceIdentityManager
    let identityManager: VoiceIdentityManager

    private let apiKey: String
    private let audioEngine = AVAudioEngine() // Main engine likely moved to IdentityManager in future refactor, but kept here for now
    // Ideally we share one engine. For this step, we'll let AudioInputManager control the engine and feed IdentityManager.
    // However, IdentityManager also needs to control engine for calibration when this manager isn't running.
    // To avoid conflict, let's SHARE the engine or have IdentityManager own it.
    // Plan: IdentityManager owns the engine. This manager requests stream from it?
    // OR: AudioInputManager owns engine, and passes buffers to IdentityManager.
    // Let's go with: AudioInputManager owns engine (since it handles transcription stream), 
    // and IdentityManager is "active" only when we feed it.
    // BUT IdentityManager needs to record for calibration when AudioInputManager's "Start Transcribing" isn't active.
    
    // DECISION: VoiceIdentityManager should probably own the AVAudioEngine to be the single source of truth as per KI.
    // Refactoring AudioInputManager to USE VoiceIdentityManager's engine or coordinate.
    // For minimal breakage: AudioInputManager keeps engine, but we ensure they don't fight.
    // Better: VoiceIdentityManager exposes `startMonitoring()` which starts engine.
    
    private let inputBus: AVAudioNodeBus = 0
    private var webSocketTask: URLSessionWebSocketTask?
    
    private let analysisQueue = DispatchQueue(label: "com.blubble.audioAnalysis", qos: .userInteractive)
    
    init(apiKey: String, identityManager: VoiceIdentityManager) {
        self.apiKey = apiKey
        self.identityManager = identityManager
        requestPermissions()
    }
    
    func startMonitoring() {
        guard !audioEngine.isRunning else { return }
        
        // Ensure IdentityManager is ready (calibrated)
        guard identityManager.calibrationState == .calibrated else {
            print("⚠️ Cannot start monitoring: Not calibrated")
            return
        }
        
        setupWebSocket()
        
        do {
            try configureAudioSession()
            setupAudioEngine()
            try audioEngine.start()
            isRunning = true
            
            // Notify IdentityManager we are starting (so it can reset state if needed)
            identityManager.startMonitoring()
            
        } catch {
            print("Failed to start audio engine:", error)
            stopMonitoring()
        }
    }

    func stopMonitoring() {
        // Stop Audio
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: inputBus)
            audioEngine.stop()
        }
        
        isRunning = false
        
        // Notify IdentityManager
        identityManager.stopMonitoring()
        
        // Close WebSocket
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
    }
    
    private func setupWebSocket() {
        // Deepgram WebSocket URL
        var components = URLComponents(string: "wss://api.deepgram.com/v1/listen")
        components?.queryItems = [
            URLQueryItem(name: "model", value: "nova-2"),
            URLQueryItem(name: "smart_format", value: "true"),
            // Diarize FALSE - we do it locally now!
            URLQueryItem(name: "diarize", value: "false"),
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "48000")
        ]
        
        guard let url = components?.url else { return }
        
        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        
        receiveMessage()
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .failure(let error):
                print("WebSocket receive error:", error)
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
                
                Task { @MainActor in
                    // Speaker ID comes from local IdentityManager now
                    let speakerID = self.identityManager.isUserSpeaking ? 0 : (self.identityManager.isPartnerSpeaking ? 1 : 0) // Default to user if unsure
                    
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
            print("JSON decoding error:", error)
        }
    }

    // MARK: - Audio Handling
    private func setupAudioEngine() {
        let inputNode = audioEngine.inputNode
        let nativeFormat = inputNode.inputFormat(forBus: inputBus)
        
        guard nativeFormat.channelCount > 0 else {
            print("❌ AudioInputManager: Input node format has 0 channels. Aborting setup.")
            return
        }
        
        // Target: 48kHz Int16 (Deepgram standard high quality)
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 48000,
            channels: 1,
            interleaved: true
        )!
        
        guard let formatConverter = AVAudioConverter(from: nativeFormat, to: targetFormat) else {
            print("❌ AudioInputManager: Failed to create audio converter.")
            return
        }
        
        // We also need to feed VoiceIdentityManager which requires standard buffers.
        // We can pass the native buffer directly.
        
        inputNode.removeTap(onBus: inputBus)
        inputNode.installTap(onBus: inputBus, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            
            // 1. Analyze for UI viz
            self.analyzeLevels(buffer)
            
            // 2. Stream to VoiceIdentityManager for Diarization
            // Note: This is async actor call inside
            Task {
                // We create a copy or pass buffer (AVAudioPCMBuffer is ref type, but immutable data usually ok here if we don't modify)
                // However, deepgram converter might modify? No, it reads.
                // We pass the buffer to IdentityManager's processing loop (which expects 16kHz conversion inside)
                // Actually IdentityManager (as written in previous step) has its own audio engine for calibration.
                // But for real-time monitoring, we are sharing THIS capture session.
                // So IdentityManager needs a `processExternalBuffer` method if we don't want two engines fighting.
                // Let's assume we use `processAudioBuffer` from IdentityManager which we made private...
                // We should expose it.
                // But wait, IdentityManager was written to start its OWN engine in startMonitoring.
                // CONFLICT DETECTED.
                // Fix: We should consolidate.
                // For this step implementation, let's assume we pass the buffer to a new public method `processStreamBuffer` on IdentityManager.
                await self.identityManager.processStreamBuffer(buffer)
            }
            
            // 3. Stream to Deepgram
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
            print("Audio conversion error: \(error)")
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
                print("WebSocket send error:", error)
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
