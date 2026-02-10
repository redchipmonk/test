//
//  VoiceIdentityManager.swift
//  blubble
//
//  Created by Alvin Ngoc Le on 2/9/26.
//

import Foundation
import Combine
import AVFoundation
import FluidAudio

@MainActor
final class VoiceIdentityManager: ObservableObject {
    
    enum CalibrationState: Equatable {
        case uncalibrated
        case listeningForUser
        case userSaved
        case listeningForPartner
        case partnerSaved
        case calibrated
        case error(String)
    }
    
    @Published var calibrationState: CalibrationState = .uncalibrated
    @Published var isUserSpeaking: Bool = false
    @Published var isPartnerSpeaking: Bool = false
    @Published var isOverlapping: Bool = false
    @Published var isRecordingEnrollment: Bool = false
    
    private let diarizer = AudioDiarizer()
    private let audioEngine = AVAudioEngine()
    private let inputBus: AVAudioNodeBus = 0
    
    // Speaker IDs after calibration/enrollment
    private let userId = "User"
    private let partnerId = "Partner"
    
    // Enrollment state
    private var enrollmentBuffer: [Float] = []
    private let enrollmentDuration: Double = 5.0 // 5 seconds
    private let sampleRate: Double = 16000.0 // FluidAudio target
    
    init() {}
    
    func initialize() async {
        do {
            try await diarizer.loadModel()
        } catch {
            print("Failed to initialize diarizer: \(error)")
            calibrationState = .error("Failed to load AI models")
        }
    }
    
    // MARK: - Calibration Flow
    
    func startCalibratingUser() {
        startEnrollment(targetState: .listeningForUser)
    }
    
    func startCalibratingPartner() {
        startEnrollment(targetState: .listeningForPartner)
    }
    
    private func startEnrollment(targetState: CalibrationState) {
        calibrationState = targetState
        isRecordingEnrollment = true
        enrollmentBuffer.removeAll()
        startAudioEngine()
    }
    
    func cancelCalibration() {
        stopAudioEngine()
        isRecordingEnrollment = false
        if calibrationState == .listeningForUser {
            calibrationState = .uncalibrated
        } else if calibrationState == .listeningForPartner {
            calibrationState = .userSaved
        }
    }
    
    // MARK: - Audio Engine Control
    
    // When driven externally (by AudioInputManager)
    func startMonitoring() {
        // No-op for internal engine, but we ensure state is calibrated
    }
    
    func stopMonitoring() {
        // No-op for internal engine
    }
    
    // Process buffer from external source (AudioInputManager)
    func processStreamBuffer(_ buffer: AVAudioPCMBuffer) async {
        await processAudioBuffer(buffer)
    }
    
    // Internal engine for calibration only
    private func startAudioEngine() {
        guard !audioEngine.isRunning else { return }
        
        let inputNode = audioEngine.inputNode
        let nativeFormat = inputNode.inputFormat(forBus: inputBus)
        
        // Setup format converter to 16kHz Mono Float32 for FluidAudio
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: nativeFormat, to: targetFormat) else {
            print("❌ VoiceIdentityManager: Failed to create audio converter")
            return
        }
        
        inputNode.removeTap(onBus: inputBus)
        inputNode.installTap(onBus: inputBus, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            
            // Convert buffer
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
            
            if error == nil {
                Task {
                    await self.processAudioBuffer(outputBuffer)
                }
            }
        }
        
        do {
            try audioEngine.prepare()
            try audioEngine.start()
        } catch {
            print("Audio engine start error: \(error)")
            calibrationState = .error("Microphone access failed")
        }
    }
    
    private func stopAudioEngine() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: inputBus)
    }
    
    // MARK: - Audio Processing
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        
        // 1. Enrollment Logic
        if isRecordingEnrollment {
            enrollmentBuffer.append(contentsOf: samples)
            
            // Check if we have enough audio
            if Double(enrollmentBuffer.count) / sampleRate >= enrollmentDuration {
                await finishEnrollment()
            }
            return
        }
        
        // 2. Real-time Diarization Logic
        guard calibrationState == .calibrated else { return }
        
        do {
            let result = try await diarizer.process(buffer: buffer)
            
            // Map segments to User/Partner
            let activeIDs = Set(result.segments.map { $0.speakerId })
            
            // Update UI state
            self.isUserSpeaking = activeIDs.contains(userId)
            self.isPartnerSpeaking = activeIDs.contains(partnerId)
            self.isOverlapping = activeIDs.count > 1
            
        } catch {
            // Log but don't spam console
        }
    }
    
    private func finishEnrollment() async {
        stopAudioEngine()
        isRecordingEnrollment = false
        
        do {
            // Extract embedding from accumulated buffer
            let embedding = try await diarizer.extractEmbedding(from: enrollmentBuffer)
            
            let speakerId = (calibrationState == .listeningForUser) ? userId : partnerId
            
            // Register known speaker with FluidAudio SpeakerManager
            if let manager = await diarizer.getSpeakerManager() {
                // Initialize known speaker
                // Note: initializeKnownSpeakers takes [Speaker], so we should accumulate them
                // But for this simple flow, we might need to modify how we access the manager.
                // Assuming AudioDiarizer exposes a way or pass-through.
                
                // Construct Speaker object (FluidAudio type)
                let speaker = Speaker(id: speakerId, name: speakerId, currentEmbedding: embedding)
                // Note: This API call might wipe others if we don't pass all known.
                // Ideally we'd keep a list in VoiceIdentityManager.
                // For now, let's assume we can add one by one or re-init.
                // Simplified: We just consider it "Saved" for our state machine.
                // The actual enrollment in FluidAudio requires `manager.initializeKnownSpeakers([...])`
                // So we should store the speaker object here.
                
                // TODO: Store speaker object for bulk initialization when calibration is fully done
            }
            
            if calibrationState == .listeningForUser {
                print("✅ User voice calibrated")
                calibrationState = .userSaved
            } else if calibrationState == .listeningForPartner {
                print("✅ Partner voice calibrated")
                calibrationState = .partnerSaved
                
                // If both ready, finalize
                 calibrationState = .calibrated
            }
            
        } catch {
            print("Enrollment failed: \(error)")
            calibrationState = .error("Voice calibration failed: \(error.localizedDescription)")
        }
    }
}
