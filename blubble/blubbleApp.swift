//
//  blubbleApp.swift
//  blubble
//
//  Created by Alvin Ngoc Le on 1/28/26.
//

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
