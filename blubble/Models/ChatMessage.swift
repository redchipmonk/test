import Foundation

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let speaker: Int
    let timestamp: Date
}
