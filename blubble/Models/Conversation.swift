import Foundation

/// Represents a saved conversation session
struct Conversation: Identifiable, Codable {
    let id: UUID
    let title: String
    let date: Date
    let messages: [SavedMessage]
    
    init(id: UUID = UUID(), title: String? = nil, date: Date = Date(), messages: [SavedMessage]) {
        self.id = id
        self.date = date
        self.messages = messages
        
        // Auto-generate title from first message or date
        if let customTitle = title {
            self.title = customTitle
        } else if let firstMessage = messages.first {
            let preview = String(firstMessage.text.prefix(30))
            self.title = preview + (firstMessage.text.count > 30 ? "..." : "")
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            self.title = "Conversation \(formatter.string(from: date))"
        }
    }
}

/// Codable version of chat message for storage
struct SavedMessage: Identifiable, Codable {
    let id: UUID
    let text: String
    let speaker: Int
    let timestamp: Date
    
    init(from chatMessage: ChatMessage) {
        self.id = chatMessage.id
        self.text = chatMessage.text
        self.speaker = chatMessage.speaker
        self.timestamp = chatMessage.timestamp
    }
}

/// Manages saved conversations with persistence
@MainActor
@Observable
class ConversationStore: ConversationStorageProtocol {
    var savedConversations: [Conversation] = []
    
    private var saveURL: URL {
        URL.documentsDirectory.appendingPathComponent("conversations.json")
    }
    
    init() {
        migrateFromUserDefaults()
        loadConversations()
    }
    
    private func migrateFromUserDefaults() {
        let saveKey = "savedConversations"
        if let data = UserDefaults.standard.data(forKey: saveKey) {
            do {
                try data.write(to: saveURL, options: [.atomic, .completeFileProtection])
                UserDefaults.standard.removeObject(forKey: saveKey)
                print("Successfully migrated conversations from UserDefaults to file storage")
            } catch {
                print("Failed to migrate conversations: \(error.localizedDescription)")
            }
        }
    }
    
    func save(_ messages: [ChatMessage]) {
        guard !messages.isEmpty else { return }
        
        let savedMessages = messages.map { SavedMessage(from: $0) }
        let conversation = Conversation(messages: savedMessages)
        savedConversations.insert(conversation, at: 0)
        persistConversations()
    }
    
    func delete(_ conversation: Conversation) {
        savedConversations.removeAll { $0.id == conversation.id }
        persistConversations()
    }
    
    func deleteAll() {
        savedConversations.removeAll()
        persistConversations()
    }
    
    private func persistConversations() {
        do {
            let data = try JSONEncoder().encode(savedConversations)
            try data.write(to: saveURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("Failed to save conversations: \(error.localizedDescription)")
        }
    }
    
    private func loadConversations() {
        guard FileManager.default.fileExists(atPath: saveURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: saveURL)
            let conversations = try JSONDecoder().decode([Conversation].self, from: data)
            savedConversations = conversations
        } catch {
            print("Failed to load conversations: \(error.localizedDescription)")
        }
    }
}
