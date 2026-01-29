//
//  TranscriptionService.swift
//  blubble
//
//  Created by Alvin Ngoc Le on 1/28/26.
//

import Foundation
import Speech
import AVFoundation
import SwiftUI
import Combine

class TranscriptionService: ObservableObject {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    @Published var transcript: String = ""
    @Published var isFinal: Bool = false

    func startTranscribing(buffer: AVAudioPCMBuffer) {
        if recognitionRequest == nil {
            prepareRecognition()
        }
        recognitionRequest?.append(buffer)
    }

    private func prepareRecognition() {
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true // Critical for <500ms latency

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                DispatchQueue.main.async {
                    self.transcript = result.bestTranscription.formattedString
                    self.isFinal = result.isFinal
                }
            }
        }
    }
    
    func reset() {
        recognitionTask?.finish()
        recognitionTask = nil
        recognitionRequest = nil
        transcript = ""
    }
}
