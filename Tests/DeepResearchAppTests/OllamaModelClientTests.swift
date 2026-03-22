import Foundation
import Testing
@testable import DeepResearchApp

@MainActor
private final class FakeConversationStore: ConversationPersisting {
    var conversations: [Conversation]

    init(conversations: [Conversation]) {
        self.conversations = conversations
    }

    func load() {}

    func save(_ conversation: Conversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        } else {
            conversations.append(conversation)
        }
    }

    func delete(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
    }

    func create() -> Conversation {
        let conversation = Conversation()
        save(conversation)
        return conversation
    }

    func conversation(id: UUID) -> Conversation? {
        conversations.first { $0.id == id }
    }
}

@Test("Ollama JSON conversion preserves nested arrays and objects")
func ollamaJSONConversionPreservesNestedValues() {
    let value: [String: Any] = [
        "query": "swift",
        "urls": ["https://a.example", "https://b.example"],
        "options": [
            "depth": 3,
            "include_raw": true,
            "weights": [1.0, 0.5],
        ],
    ]

    let converted = OllamaModelClient.convertToOllamaJSONValue(value)

    guard case let .object(root) = converted else {
        #expect(Bool(false))
        return
    }

    guard case let .array(urls)? = root["urls"] else {
        #expect(Bool(false))
        return
    }
    #expect(urls.count == 2)

    guard case let .object(options)? = root["options"] else {
        #expect(Bool(false))
        return
    }
    guard case let .array(weights)? = options["weights"] else {
        #expect(Bool(false))
        return
    }

    #expect(weights.count == 2)
    if case let .bool(includeRaw)? = options["include_raw"] {
        #expect(includeRaw == true)
    } else {
        #expect(Bool(false))
    }
}

@MainActor
@Test("ChatViewModel configure loads selected conversation from store")
func chatViewModelConfigureLoadsConversationByID() {
    let targetID = UUID(uuidString: "E9F32765-FA95-4D63-A317-2F20A378D47B")!
    let persistedMessages = [ChatMessage.user("Persisted message")]
    let store = FakeConversationStore(
        conversations: [
            Conversation(id: targetID, title: "Persisted", messages: persistedMessages),
            Conversation(id: UUID(), title: "Other", messages: []),
        ]
    )
    let viewModel = ChatViewModel(conversationStore: store)
    let settingsVM = SettingsViewModel()

    viewModel.configure(with: settingsVM, conversationID: targetID)

    #expect(viewModel.messages.count == 1)
    #expect(viewModel.messages.first?.content == "Persisted message")
}
