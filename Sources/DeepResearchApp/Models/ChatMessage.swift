import Foundation

struct ChatMessage: Identifiable, Codable, Sendable {
    let id: String
    let role: ChatMessageRole
    var content: String
    let timestamp: Date
    var isStreaming: Bool
    var toolCalls: [ToolCallInfo]

    enum ChatMessageRole: String, Codable, Sendable {
        case user
        case assistant
        case system
        case toolResult
    }

    struct ToolCallInfo: Identifiable, Codable, Sendable {
        let id: String
        let name: String
        var status: ToolCallStatus

        enum ToolCallStatus: String, Codable, Sendable {
            case pending
            case running
            case completed
            case failed
        }
    }

    static func user(_ content: String) -> ChatMessage {
        ChatMessage(
            id: UUID().uuidString,
            role: .user,
            content: content,
            timestamp: .now,
            isStreaming: false,
            toolCalls: []
        )
    }

    static func assistantPlaceholder() -> ChatMessage {
        ChatMessage(
            id: UUID().uuidString,
            role: .assistant,
            content: "",
            timestamp: .now,
            isStreaming: true,
            toolCalls: []
        )
    }
}
