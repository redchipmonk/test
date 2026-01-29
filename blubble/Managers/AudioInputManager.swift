//
//  AudioInputManager.swift
//  blubble
//
//  Created by Alvin Ngoc Le on 1/28/26.
//

import Foundation
import AVFoundation
import Accelerate
import Combine

/// Manages the live audio stream from the Apple Vision Pro microphones.
/// Handles volume detection for speaker separation and pitch analysis for tone detection.
class AudioInputManager: ObservableObject {
    // MARK: - Published Properties
    @Published var currentRMS: Float = 0.0
    @Published var currentZCR: Float = 0.0
    /// Indicates if the engine is currently running
    @Published var isRunning: Bool = false
    
    private let audioEngine = AVAudioEngine()
    private let mixerNode = AVAudioMixerNode()
    
    /// Initializes the audio session and starts the hardware tap
    func startMonitoring() {
        guard !audioEngine.isRunning else { return }
        
        // 1. Configure Session
        configureAudioSession()
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // FIX: Check if the format is valid (Sample rate must be > 0)
        guard recordingFormat.sampleRate > 0 else {
            print("Audio format is invalid. If on Simulator, ensure 'I/O' settings use System Microphone.")
            return
        }
        
        // 2. Clear any existing tap to avoid crashes on restart
        inputNode.removeTap(onBus: 0)
        
        // 3. Install the tap using the verified format
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] (buffer, time) in
            self?.analyzeBuffer(buffer)
        }
        
        // 4. Start Engine
        do {
            // Prepare the engine before starting
            audioEngine.prepare()
            try audioEngine.start()
            DispatchQueue.main.async {
                self.isRunning = true
            }
        } catch {
            print("Audio Engine failed: \(error.localizedDescription)")
        }
    }
    
    func stopMonitoring() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        DispatchQueue.main.async {
            self.isRunning = false
        }
    }

    
    private func analyzeBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = UInt(buffer.frameLength)
        
        // A. Calculate RMS (Volume)
        // This supports the metric: System attributes speech to correct speaker >80% [cite: 31]
        var rms: Float = 0.0
        vDSP_rmsqv(channelData, 1, &rms, frameLength)
        
        // B. Calculate Zero-Crossing Rate (Pitch/Tone indicator) [cite: 40]
        var crossings: Float = 0.0
        for i in 0..<Int(frameLength - 1) {
            // Check for sign changes in the waveform
            if (channelData[i] > 0 && channelData[i+1] <= 0) ||
               (channelData[i] < 0 && channelData[i+1] >= 0) {
                crossings += 1
            }
        }
        
        let zcr = crossings / Float(frameLength)
        
        // Update the UI/HUD on the main thread
        DispatchQueue.main.async {
            self.currentRMS = rms
            self.currentZCR = zcr
        }
    }
    
    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            print("Failed to set up audio session category: \(error)")
        }
    }
}
