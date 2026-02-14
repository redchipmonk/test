import SwiftUI

@main
struct blubbleApp: App {

    @State private var conversationStore = ConversationStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(conversationStore)
        }
        .windowStyle(.plain)
        .defaultSize(width: 500, height: 600)
    }
}
