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

    weak var transcriptionService: TranscriptionService?

    private let audioEngine = AVAudioEngine()
    private let inputBus: AVAudioNodeBus = 0

    private let speechFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 44_100,
        channels: 1,
        interleaved: false
    )!

    private var audioConverter: AVAudioConverter?

    init(transcriptionService: TranscriptionService? = nil) {
        self.transcriptionService = transcriptionService
        requestPermissions()
    }

    func startMonitoring() {
        guard !audioEngine.isRunning else { return }

        transcriptionService?.start()

        do {
            try configureAudioSession()
        } catch {
            print("Audio session error:", error)
            return
        }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: inputBus)

        audioConverter = AVAudioConverter(from: inputFormat, to: speechFormat)

        inputNode.removeTap(onBus: inputBus)
        inputNode.installTap(
            onBus: inputBus,
            bufferSize: 1024,
            format: inputFormat
        ) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
            isRunning = true
        } catch {
            print("Failed to start audio engine:", error)
        }
    }

    func stopMonitoring() {
        guard audioEngine.isRunning else { return }

        audioEngine.inputNode.removeTap(onBus: inputBus)
        audioEngine.stop()
        isRunning = false

        transcriptionService?.stop()
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        analyzeLevels(buffer)
        convertAndSendToSpeech(buffer)
    }

    private func analyzeLevels(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = vDSP_Length(buffer.frameLength)

        var rms: Float = 0
        vDSP_rmsqv(channelData, 1, &rms, frameCount)

        var crossings: Float = 0
        for i in 0..<Int(frameCount - 1) {
            if (channelData[i] > 0 && channelData[i + 1] <= 0) ||
               (channelData[i] < 0 && channelData[i + 1] >= 0) {
                crossings += 1
            }
        }

        currentRMS = rms
        currentZCR = crossings / Float(frameCount)
    }

    private func convertAndSendToSpeech(_ buffer: AVAudioPCMBuffer) {
        guard
            let converter = audioConverter,
            let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: speechFormat,
                frameCapacity: buffer.frameCapacity
            )
        else { return }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if error == nil {
            transcriptionService?.appendAudioBuffer(outputBuffer)
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.mixWithOthers]
        )
        try session.setActive(true)
    }

    private func requestPermissions() {
        AVAudioSession.sharedInstance().requestRecordPermission { _ in }
        SFSpeechRecognizer.requestAuthorization { _ in }
    }
}
