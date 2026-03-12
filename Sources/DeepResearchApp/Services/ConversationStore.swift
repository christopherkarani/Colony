import Foundation

enum ConversationStoreError: Error, Sendable {
    case storageUnavailable(String)
    case loadFailed(String)
    case saveFailed(String)
    case deleteFailed(String)
}

@Observable
@MainActor
final class ConversationStore {
    private(set) var conversations: [Conversation] = []
    private let directory: URL
    private let fileManager: FileManager
    private let startupError: ConversationStoreError?

    init() {
        self.fileManager = .default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.directory = appSupport
            .appendingPathComponent("DeepResearch", isDirectory: true)
            .appendingPathComponent("conversations", isDirectory: true)

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            self.startupError = nil
        } catch {
            self.startupError = .storageUnavailable(String(describing: error))
        }
    }

    func load() throws {
        try throwIfStorageUnavailable()
        let files: [URL]
        do {
            files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        } catch {
            throw ConversationStoreError.loadFailed(String(describing: error))
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var loaded: [Conversation] = []
        var firstCorruptFileError: ConversationStoreError?
        for file in files where file.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: file)
                let conversation = try decoder.decode(Conversation.self, from: data)
                loaded.append(conversation)
            } catch {
                try quarantineCorruptFile(file)
                if firstCorruptFileError == nil {
                    firstCorruptFileError = .loadFailed("Corrupt conversation moved to quarantine: \(file.lastPathComponent)")
                }
                continue
            }
        }

        conversations = loaded.sorted { $0.createdAt > $1.createdAt }
        if let firstCorruptFileError {
            throw firstCorruptFileError
        }
    }

    func save(_ conversation: Conversation) throws {
        try throwIfStorageUnavailable()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601

        let fileURL = directory.appendingPathComponent("\(conversation.id.uuidString).json")

        do {
            let data = try encoder.encode(conversation)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw ConversationStoreError.saveFailed(String(describing: error))
        }

        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        } else {
            conversations.append(conversation)
            conversations.sort { $0.createdAt > $1.createdAt }
        }
    }

    func delete(_ conversation: Conversation) throws {
        try throwIfStorageUnavailable()
        let fileURL = directory.appendingPathComponent("\(conversation.id.uuidString).json")
        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
        } catch {
            throw ConversationStoreError.deleteFailed(String(describing: error))
        }
        conversations.removeAll { $0.id == conversation.id }
    }

    func create() throws -> Conversation {
        let conversation = Conversation()
        try save(conversation)
        return conversation
    }

    private func throwIfStorageUnavailable() throws {
        if let startupError {
            throw startupError
        }
    }

    private func quarantineCorruptFile(_ file: URL) throws {
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let quarantineURL = directory.appendingPathComponent("\(file.lastPathComponent).corrupt-\(timestamp)")
        do {
            if fileManager.fileExists(atPath: quarantineURL.path) {
                try fileManager.removeItem(at: quarantineURL)
            }
            try fileManager.moveItem(at: file, to: quarantineURL)
        } catch {
            throw ConversationStoreError.loadFailed("Unable to quarantine corrupt file \(file.lastPathComponent): \(error)")
        }
    }
}
