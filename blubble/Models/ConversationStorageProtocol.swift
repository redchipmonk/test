import Foundation

@MainActor
protocol ConversationStorageProtocol {
    var savedConversations: [Conversation] { get }
    func save(_ messages: [ChatMessage])
    func delete(_ conversation: Conversation)
    func deleteAll()
}
