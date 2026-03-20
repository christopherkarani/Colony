import Foundation

struct Conversation: Identifiable, Codable, Sendable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    let createdAt: Date

    init(id: UUID = UUID(), title: String = "New Research", messages: [ChatMessage] = [], createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
    }
}
