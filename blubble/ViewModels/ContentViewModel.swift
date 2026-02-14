import Foundation
import SwiftUI
import Combine
import AVFoundation
import OSLog

@MainActor
class ContentViewModel: ObservableObject {
    private let logger = Logger(subsystem: "team1.blubble", category: "ContentViewModel")
    
    // Services
    private let audioCaptureService: AudioCaptureProtocol
    private let speechRecognitionService: SpeechRecognitionProtocol
    private let identityManager: any VoiceIdentityManaging
    let conversationStore: any ConversationStorageProtocol
    
    func getStore() -> any ConversationStorageProtocol {
        return conversationStore
    }
    
    // UI State
    @Published var isRunning: Bool = false
    @Published var transcript: String = ""
    @Published var chatHistory: [ChatMessage] = []
    @Published var selectedTab: ContentView.Tab = .transcribe
    @Published var showingSaveConfirmation = false
    
    // Identity State
    @Published var isInitializing: Bool = false
    @Published var currentSpeaker: String? = nil
    @Published var speakerProbabilities: [Float] = []
    
    private var captureTask: Task<Void, Never>?
    private var recognitionTask: Task<Void, Never>?
    
    init(
        audioCaptureService: AudioCaptureProtocol,
        speechRecognitionService: SpeechRecognitionProtocol,
        identityManager: any VoiceIdentityManaging,
        conversationStore: any ConversationStorageProtocol
    ) {
        self.audioCaptureService = audioCaptureService
        self.speechRecognitionService = speechRecognitionService
        self.identityManager = identityManager
        self.conversationStore = conversationStore
        
        // Sync with identity manager initial state
        self.isInitializing = identityManager.isInitializing
        
        // Setup observers if needed (using SwiftUI's @Observable or Combine)
        // Since we are refactoring to DI, we might want to observe the identity manager.
    }
    
    func initialize() async {
        await identityManager.initialize()
        isInitializing = identityManager.isInitializing
    }
    
    func startMonitoring() {
        guard !isRunning else { return }
        
        recognitionTask = Task {
            let stream = await speechRecognitionService.startRecognition()
            for await result in stream {
                handleRecognitionResult(result)
            }
        }
        
        captureTask = Task {
            do {
                let stream = try audioCaptureService.startCapture()
                isRunning = true
                for await buffer in stream {
                    // Send to Deepgram
                    speechRecognitionService.sendAudio(buffer)
                    // Send to Identity Manager
                    await identityManager.processStreamBuffer(buffer)
                    
                    // Update identity states
                    self.currentSpeaker = identityManager.currentSpeaker
                    self.speakerProbabilities = identityManager.speakerProbabilities
                }
            } catch {
                logger.error("Failed to start capture: \(error.localizedDescription)")
                stopMonitoring()
            }
        }
    }
    
    func stopMonitoring() {
        audioCaptureService.stopCapture()
        speechRecognitionService.stopRecognition()
        captureTask?.cancel()
        recognitionTask?.cancel()
        isRunning = false
        transcript = ""
    }
    
    private func handleRecognitionResult(_ result: SpeechRecognitionResult) {
        switch result {
        case .partial(let text):
            self.transcript = text
        case .final(let text):
            let speakerID = getSpeakerID()
            let message = ChatMessage(text: text, speaker: speakerID, timestamp: Date())
            self.chatHistory.append(message)
            self.transcript = ""
        case .error(let error):
            logger.error("Recognition error: \(error.localizedDescription)")
            stopMonitoring()
        }
    }
    
    private func getSpeakerID() -> Int {
        if let speakerString = identityManager.currentSpeaker,
           let id = Int(speakerString.components(separatedBy: " ").last ?? "") {
            return id - 1
        }
        return 0
    }
    
    func saveConversation() {
        conversationStore.save(chatHistory)
        showingSaveConfirmation = true
    }
    
    func clearConversation() {
        chatHistory.removeAll()
        transcript = ""
    }
}

// Extension to help ContentView with Tab enum
extension ContentView {
    enum Tab {
        case transcribe
        case history
    }
}
