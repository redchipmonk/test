//
//  SavedConversationsView.swift
//  blubble
//
//  Created by Alvin Ngoc Le on 2/3/26.
//

import SwiftUI

/// View displaying saved conversation history
struct SavedConversationsView: View {
    @Environment(ConversationStore.self) private var store
    @State private var selectedConversation: Conversation?
    
    var body: some View {
        NavigationStack {
            Group {
                if store.savedConversations.isEmpty {
                    ContentUnavailableView(
                        "No Saved Conversations",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Transcribe a conversation and tap Save to keep it here.")
                    )
                } else {
                    List {
                        ForEach(store.savedConversations) { conversation in
                            Button {
                                selectedConversation = conversation
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(conversation.title)
                                        .font(.headline)
                                        .lineLimit(1)
                                    
                                    HStack {
                                        Text(conversation.date, style: .date)
                                        Text("•")
                                        Text("\(conversation.messages.count) messages")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                store.delete(store.savedConversations[index])
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                if !store.savedConversations.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear All", role: .destructive) {
                            store.deleteAll()
                        }
                    }
                }
            }
            .sheet(item: $selectedConversation) { conversation in
                ConversationDetailView(conversation: conversation)
            }
        }
    }
}

/// Detail view for viewing a saved conversation
struct ConversationDetailView: View {
    let conversation: Conversation
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(conversation.messages) { message in
                        SavedChatBubble(message: message)
                    }
                }
                .padding()
            }
            .navigationTitle(conversation.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Chat bubble for saved messages
struct SavedChatBubble: View {
    let message: SavedMessage
    
    var isUser: Bool {
        message.speaker == 0
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer() }
            
            if !isUser {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 28, height: 28)
                    .overlay(Text("\(message.speaker)").font(.caption2).foregroundColor(.white))
            }
            
            Text(message.text)
                .padding(12)
                .background(isUser ? Color.blue : Color(.systemGray5))
                .foregroundColor(isUser ? .white : .primary)
                .cornerRadius(16)
            
            if isUser {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 28, height: 28)
                    .overlay(Text("0").font(.caption2).foregroundColor(.white))
            }
            
            if !isUser { Spacer() }
        }
    }
}

#Preview {
    SavedConversationsView()
        .environment(ConversationStore())
}
