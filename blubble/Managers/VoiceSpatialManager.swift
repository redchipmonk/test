//
//  VoiceSpatialManager.swift
//  blubble
//
//  Created by Alvin Ngoc Le on 2/3/26.
//

import Foundation
import AVFoundation
import Accelerate
import Combine
import simd

/// Determines speech source (User vs Partner) using RMS energy and low-frequency dominance
@MainActor
@Observable
final class VoiceSpatialManager {
    
    // MARK: - Published State
    var currentRMS: Float = 0.0
    var lowFreqDominance: Float = 0.0
    var isUserSpeaking: Bool = false
    var isPartnerSpeaking: Bool = false
    var isRunning: Bool = false
    
    // Partner speech text (placeholder for now)
    var partnerTranscript: String = ""
    
    // MARK: - Thresholds
    /// RMS threshold for user voice (higher due to microphone proximity)
    var internalUserThreshold: Float = 0.15
    /// Low-frequency dominance threshold (proximity effect = boosted bass)
    var lowFreqDominanceThreshold: Float = 0.6
    /// Angle threshold for partner direction (degrees)
    var angleThreshold: Float = 30.0
    
    // MARK: - Spatial Tracking
    /// Direction to partner anchor in world space
    var partnerAnchorDirection: SIMD3<Float>?
    /// World position of partner (from PersonSegmentation centroid)
    var partnerWorldPosition: SIMD3<Float>?
    
    // MARK: - Private Properties
    private let audioEngine = AVAudioEngine()
    private let inputBus: AVAudioNodeBus = 0
    private let analysisQueue = DispatchQueue(label: "com.blubble.voiceSpatial", qos: .userInteractive)
    
    // FFT setup for frequency analysis - nonisolated for deinit cleanup
    private nonisolated(unsafe) var fftSetup: vDSP_DFT_Setup?
    private let fftLength: Int = 1024
    
    init() {
        fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftLength), .FORWARD)
        requestPermissions()
    }
    
    nonisolated func cleanupFFT() {
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
        }
    }
    
    // MARK: - Public Methods
    
    func startListening() {
        guard !audioEngine.isRunning else { return }
        
        do {
            try configureAudioSession()
            setupAudioEngine()
            try audioEngine.start()
            isRunning = true
            print("✅ VoiceSpatialManager: Audio engine started")
        } catch {
            print("❌ VoiceSpatialManager: Failed to start - \(error)")
            stopListening()
        }
    }
    
    func stopListening() {
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: inputBus)
            audioEngine.stop()
        }
        isRunning = false
        isUserSpeaking = false
        isPartnerSpeaking = false
    }
    
    func setPartnerAnchorPosition(_ position: SIMD3<Float>) {
        partnerWorldPosition = position
    }
    
    // MARK: - Audio Engine Setup
    
    private func setupAudioEngine() {
        let inputNode = audioEngine.inputNode
        let nativeFormat = inputNode.inputFormat(forBus: inputBus)
        
        guard nativeFormat.channelCount > 0 else {
            print("❌ VoiceSpatialManager: Input format has 0 channels")
            return
        }
        
        inputNode.removeTap(onBus: inputBus)
        inputNode.installTap(onBus: inputBus, bufferSize: UInt32(fftLength), format: nativeFormat) { [weak self] buffer, _ in
            self?.analyzeAudioBuffer(buffer)
        }
    }
    
    // MARK: - Audio Analysis
    
    private func analyzeAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        
        // Calculate RMS (energy level)
        var rms: Float = 0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameCount))
        
        // Calculate low-frequency dominance
        let lowFreq = calculateLowFreqDominance(from: channelData, frameCount: frameCount, sampleRate: Float(buffer.format.sampleRate))
        
        // Determine speaker based on RMS + low-freq dominance
        let isUser = determineIfUserSpeech(rms: rms, lowFreqDominance: lowFreq)
        let isPartner = !isUser && rms > 0.02 // Partner if external and audible
        
        Task { @MainActor in
            self.currentRMS = rms
            self.lowFreqDominance = lowFreq
            self.isUserSpeaking = isUser
            self.isPartnerSpeaking = isPartner
        }
    }
    
    /// Calculate low-frequency dominance using FFT
    /// Proximity effect causes boosted bass (< 500Hz) for user speech
    private func calculateLowFreqDominance(from samples: UnsafePointer<Float>, frameCount: Int, sampleRate: Float) -> Float {
        guard let fftSetup = fftSetup, frameCount >= fftLength else { return 0.0 }
        
        // Prepare input for FFT
        var realInput = [Float](repeating: 0, count: fftLength)
        let imagInput = [Float](repeating: 0, count: fftLength)
        var realOutput = [Float](repeating: 0, count: fftLength)
        var imagOutput = [Float](repeating: 0, count: fftLength)
        
        // Copy samples to real input
        for i in 0..<min(frameCount, fftLength) {
            realInput[i] = samples[i]
        }
        
        // Perform FFT
        vDSP_DFT_Execute(fftSetup, realInput, imagInput, &realOutput, &imagOutput)
        
        // Calculate magnitude spectrum
        var magnitudes = [Float](repeating: 0, count: fftLength / 2)
        for i in 0..<fftLength / 2 {
            magnitudes[i] = sqrt(realOutput[i] * realOutput[i] + imagOutput[i] * imagOutput[i])
        }
        
        // Calculate energy in low frequencies (< 500Hz) vs total
        let binWidth = sampleRate / Float(fftLength)
        let lowFreqBins = Int(500.0 / binWidth)
        
        var lowFreqEnergy: Float = 0
        var totalEnergy: Float = 0
        
        for i in 0..<magnitudes.count {
            let energy = magnitudes[i] * magnitudes[i]
            totalEnergy += energy
            if i < lowFreqBins {
                lowFreqEnergy += energy
            }
        }
        
        guard totalEnergy > 0 else { return 0.0 }
        return lowFreqEnergy / totalEnergy
    }
    
    /// Determine if speech is from user based on RMS and low-frequency dominance
    /// User speech: High RMS (close mic) + High low-freq dominance (proximity effect)
    private func determineIfUserSpeech(rms: Float, lowFreqDominance: Float) -> Bool {
        // User voice: louder (high RMS) AND proximity effect (boosted bass)
        return rms > internalUserThreshold && lowFreqDominance > lowFreqDominanceThreshold
    }
    
    /// Calculate angle between headset forward and sound source direction
    func calculateAngleToPartner(headsetForward: SIMD3<Float>, soundDirection: SIMD3<Float>) -> Float {
        let dotProduct = simd_dot(simd_normalize(headsetForward), simd_normalize(soundDirection))
        let clampedDot = max(-1.0, min(1.0, dotProduct))
        let angleRadians = acos(clampedDot)
        return angleRadians * (180.0 / .pi)
    }
    
    /// Check if sound is coming from partner's direction
    func isWithinPartnerAngle(headsetForward: SIMD3<Float>, soundDirection: SIMD3<Float>) -> Bool {
        let angle = calculateAngleToPartner(headsetForward: headsetForward, soundDirection: soundDirection)
        return angle <= angleThreshold
    }
    
    // MARK: - Audio Session
    
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        // Use .default mode (not .measurement or .voiceChat) to avoid noise cancellation
        // and capture raw audio from all directions including partner's voice
        try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }
    
    private func requestPermissions() {
        AVAudioApplication.requestRecordPermission { _ in }
    }
}
