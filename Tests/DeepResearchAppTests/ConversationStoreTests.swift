import Foundation
import Testing
@testable import DeepResearchApp

@MainActor
@Suite("ConversationStore")
struct ConversationStoreTests {

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConversationStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Create and Load

    @Test("create() persists a conversation and load() recovers it")
    func createAndLoad() throws {
        let dir = try makeTempDirectory()
        defer { cleanup(dir) }

        let store = ConversationStore(directory: dir)
        let created = store.create()

        #expect(store.conversations.count == 1)
        #expect(store.conversations.first?.id == created.id)

        // Fresh store loading from same directory should recover the conversation.
        let store2 = ConversationStore(directory: dir)
        store2.load()

        #expect(store2.conversations.count == 1)
        #expect(store2.conversations.first?.id == created.id)
        #expect(store2.conversations.first?.title == created.title)
    }

    // MARK: - Save Round-Trip

    @Test("save() round-trips message content through JSON")
    func saveRoundTrip() throws {
        let dir = try makeTempDirectory()
        defer { cleanup(dir) }

        let store = ConversationStore(directory: dir)
        var conversation = store.create()
        conversation.messages.append(.user("Hello world"))
        conversation.title = "Test Research"
        store.save(conversation)

        let store2 = ConversationStore(directory: dir)
        store2.load()

        let loaded = try #require(store2.conversations.first)
        #expect(loaded.title == "Test Research")
        #expect(loaded.messages.count == 1)
        #expect(loaded.messages.first?.content == "Hello world")
        #expect(loaded.messages.first?.role == .user)
    }

    // MARK: - Sort Order

    @Test("conversations are sorted newest-first after load")
    func sortOrder() throws {
        let dir = try makeTempDirectory()
        defer { cleanup(dir) }

        let store = ConversationStore(directory: dir)

        let older = Conversation(
            title: "Older",
            createdAt: Date(timeIntervalSince1970: 1_000_000)
        )
        let newer = Conversation(
            title: "Newer",
            createdAt: Date(timeIntervalSince1970: 2_000_000)
        )

        // Save in chronological order.
        store.save(older)
        store.save(newer)

        let store2 = ConversationStore(directory: dir)
        store2.load()

        #expect(store2.conversations.count == 2)
        #expect(store2.conversations[0].title == "Newer")
        #expect(store2.conversations[1].title == "Older")
    }

    // MARK: - Update In-Place

    @Test("save() updates an existing conversation in-place")
    func updateInPlace() throws {
        let dir = try makeTempDirectory()
        defer { cleanup(dir) }

        let store = ConversationStore(directory: dir)
        var conversation = store.create()
        #expect(store.conversations.count == 1)

        conversation.title = "Updated Title"
        store.save(conversation)

        // Should update, not duplicate.
        #expect(store.conversations.count == 1)
        #expect(store.conversations.first?.title == "Updated Title")
    }

    // MARK: - Delete

    @Test("delete() removes the conversation from memory and disk")
    func deleteConversation() throws {
        let dir = try makeTempDirectory()
        defer { cleanup(dir) }

        let store = ConversationStore(directory: dir)
        let conversation = store.create()
        #expect(store.conversations.count == 1)

        store.delete(conversation)
        #expect(store.conversations.isEmpty)

        // Verify disk cleanup: fresh load should find nothing.
        let store2 = ConversationStore(directory: dir)
        store2.load()
        #expect(store2.conversations.isEmpty)
    }

    // MARK: - Empty Directory

    @Test("load() on an empty directory produces no conversations")
    func loadEmptyDirectory() throws {
        let dir = try makeTempDirectory()
        defer { cleanup(dir) }

        let store = ConversationStore(directory: dir)
        store.load()
        #expect(store.conversations.isEmpty)
    }

    // MARK: - Corrupt File Resilience

    @Test("load() skips corrupt JSON files without crashing")
    func corruptFileResilience() throws {
        let dir = try makeTempDirectory()
        defer { cleanup(dir) }

        // Write a valid conversation.
        let store = ConversationStore(directory: dir)
        _ = store.create()

        // Write a corrupt JSON file alongside it.
        let corruptFile = dir.appendingPathComponent("corrupt.json")
        try Data("not valid json".utf8).write(to: corruptFile)

        let store2 = ConversationStore(directory: dir)
        store2.load()

        // Should load the valid conversation and skip the corrupt one.
        #expect(store2.conversations.count == 1)
    }
}
