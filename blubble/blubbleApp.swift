import SwiftUI

@main
struct blubbleApp: App {
    @StateObject private var viewModel: ContentViewModel
    @StateObject private var audioSystem: AudioSystem

    init() {
        // 1. Data Layer
        let conversationStore = ConversationStore()
        
        // 2. Service Layer
        let audioCaptureService = AudioCaptureService()
        let audioConverterService = AudioConverterService()
        
        var apiKey = ""
        if let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
           let key = dict["DeepgramAPIKey"] as? String {
            apiKey = key
        }
        let speechRecognitionService = SpeechRecognitionService(apiKey: apiKey, converterService: audioConverterService)
        
        let diarizer = AudioDiarizer()
        let identityManager = VoiceIdentityManager(diarizer: diarizer)
        
        // 3. Coordination Layer
        let system = AudioSystem(
            audioCaptureService: audioCaptureService,
            speechRecognitionService: speechRecognitionService,
            identityManager: identityManager,
            audioConverterService: audioConverterService
        )
        _audioSystem = StateObject(wrappedValue: system)
        
        // 4. View Model Layer
        let vm = ContentViewModel(
            audioCaptureService: audioCaptureService,
            speechRecognitionService: speechRecognitionService,
            identityManager: identityManager,
            conversationStore: conversationStore
        )
        _viewModel = StateObject(wrappedValue: vm)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .windowStyle(.plain)
        .defaultSize(width: 500, height: 600)
    }
}
