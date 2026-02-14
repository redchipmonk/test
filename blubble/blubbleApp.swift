import SwiftUI

@main
struct blubbleApp: App {

    @State private var conversationStore = ConversationStore()
    @StateObject private var audioSystem = AudioSystem()

    var body: some Scene {
        WindowGroup {
            ContentView(
                audioManager: audioSystem.audioManager,
                identityManager: audioSystem.identityManager
            )
            .environment(conversationStore)
        }
        .windowStyle(.plain)
        .defaultSize(width: 500, height: 600)
    }
}
