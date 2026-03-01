import Foundation

@Observable
@MainActor
final class ConversationStore {
    private(set) var conversations: [Conversation] = []
    private let directory: URL
    private let fileManager: FileManager
    private let reportError: @MainActor @Sendable (String) -> Void

    init(
        directory: URL? = nil,
        fileManager: FileManager = .default,
        reportError: @escaping @MainActor @Sendable (String) -> Void = { message in
            fputs("[ConversationStore] \(message)\n", stderr)
        }
    ) {
        self.fileManager = fileManager
        self.reportError = reportError

        let baseDirectory: URL
        if let directory {
            baseDirectory = directory
        } else {
            baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        }

        self.directory = baseDirectory
            .appendingPathComponent("DeepResearch", isDirectory: true)
            .appendingPathComponent("conversations", isDirectory: true)

        do {
            try fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
        } catch {
            reportError("Failed to create conversations directory: \(error)")
        }
    }

    func load() {
        let files: [URL]
        do {
            files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        } catch {
            reportError("Failed to list conversations directory: \(error)")
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var loaded: [Conversation] = []
        for file in files where file.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: file)
                let conversation = try decoder.decode(Conversation.self, from: data)
                loaded.append(conversation)
            } catch {
                reportError("Failed to load conversation at \(file.lastPathComponent): \(error)")
                continue
            }
        }

        conversations = loaded.sorted { $0.createdAt > $1.createdAt }
    }

    func save(_ conversation: Conversation) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601

        let fileURL = directory.appendingPathComponent("\(conversation.id.uuidString).json")

        do {
            let data = try encoder.encode(conversation)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            reportError("Failed to save conversation \(conversation.id.uuidString): \(error)")
            return
        }

        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        } else {
            conversations.append(conversation)
            conversations.sort { $0.createdAt > $1.createdAt }
        }
    }

    func delete(_ conversation: Conversation) {
        let fileURL = directory.appendingPathComponent("\(conversation.id.uuidString).json")
        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            reportError("Failed to delete conversation \(conversation.id.uuidString): \(error)")
        }
        conversations.removeAll { $0.id == conversation.id }
    }

    func create() -> Conversation {
        let conversation = Conversation()
        save(conversation)
        return conversation
    }
}
