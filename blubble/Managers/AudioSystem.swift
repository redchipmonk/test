import Foundation
import Combine
import SwiftUI
import OSLog

@MainActor
@Observable
final class AudioSystem {
    let audioCaptureService: any AudioCaptureProtocol
    let speechRecognitionService: any SpeechRecognitionProtocol
    let identityManager: any VoiceIdentityManaging
    let audioConverterService: any AudioConverterProtocol
    
    init(
        audioCaptureService: any AudioCaptureProtocol,
        speechRecognitionService: any SpeechRecognitionProtocol,
        identityManager: any VoiceIdentityManaging,
        audioConverterService: any AudioConverterProtocol
    ) {
        self.audioCaptureService = audioCaptureService
        self.speechRecognitionService = speechRecognitionService
        self.identityManager = identityManager
        self.audioConverterService = audioConverterService
        
        Logger(subsystem: "team1.blubble", category: "AudioSystem").info("AudioSystem.init() completed")
    }
}
