import SwiftUI

@Observable
@MainActor
final class SidebarViewModel {
    var conversations: [Conversation] = []
    var selectedConversationID: UUID? = nil
    private let store = ConversationStore()

    func loadConversations() {
        store.load()
        conversations = store.conversations
    }

    func createNewConversation() {
        let conversation = store.create()
        conversations = store.conversations
        selectedConversationID = conversation.id
    }

    func deleteConversation(_ conversation: Conversation) {
        store.delete(conversation)
        conversations = store.conversations
        if selectedConversationID == conversation.id {
            selectedConversationID = conversations.first?.id
        }
    }

    func updateConversation(_ conversation: Conversation) {
        store.save(conversation)
        if let idx = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[idx] = conversation
        }
    }
}
