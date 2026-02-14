import Foundation
import Combine
import SwiftUI
import OSLog

@MainActor
final class AudioSystem: ObservableObject {
    let audioManager: AudioInputManager
    let identityManager: VoiceIdentityManager
    private let diarizer: AudioDiarizer
    
    init() {
        Logger(subsystem: "team1.blubble", category: "AudioSystem").info("AudioSystem.init() starting")
        // Load API key from Secrets.plist
        var apiKey = ""
        if let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
           let key = dict["DeepgramAPIKey"] as? String {
            apiKey = key
        } else {
            Logger(subsystem: "team1.blubble", category: "AudioSystem")
                .error("Failed to load DeepgramAPIKey from Secrets.plist")
        }
        
        self.diarizer = AudioDiarizer()
        self.identityManager = VoiceIdentityManager(diarizer: self.diarizer)
        self.audioManager = AudioInputManager(apiKey: apiKey, identityManager: self.identityManager)
    }
}
