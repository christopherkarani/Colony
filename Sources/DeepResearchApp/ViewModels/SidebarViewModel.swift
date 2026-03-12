import SwiftUI

@Observable
@MainActor
final class SidebarViewModel {
    var conversations: [Conversation] = []
    var selectedConversationID: UUID? = nil
    var lastPersistenceError: String? = nil
    private let store = ConversationStore()

    func loadConversations() {
        do {
            try store.load()
            conversations = store.conversations
            lastPersistenceError = nil
        } catch {
            conversations = store.conversations
            lastPersistenceError = String(describing: error)
        }
    }

    func createNewConversation() {
        do {
            let conversation = try store.create()
            conversations = store.conversations
            selectedConversationID = conversation.id
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = String(describing: error)
        }
    }

    func deleteConversation(_ conversation: Conversation) {
        do {
            try store.delete(conversation)
            conversations = store.conversations
            if selectedConversationID == conversation.id {
                selectedConversationID = conversations.first?.id
            }
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = String(describing: error)
        }
    }

    func updateConversation(_ conversation: Conversation) {
        do {
            try store.save(conversation)
            if let idx = conversations.firstIndex(where: { $0.id == conversation.id }) {
                conversations[idx] = conversation
            }
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = String(describing: error)
        }
    }
}
