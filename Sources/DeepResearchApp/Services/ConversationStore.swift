import Foundation

@Observable
@MainActor
final class ConversationStore {
    private(set) var conversations: [Conversation] = []
    private let directory: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.directory = appSupport
            .appendingPathComponent("DeepResearch", isDirectory: true)
            .appendingPathComponent("conversations", isDirectory: true)

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func load() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var loaded: [Conversation] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let conversation = try? decoder.decode(Conversation.self, from: data) else {
                continue
            }
            loaded.append(conversation)
        }

        conversations = loaded.sorted { $0.createdAt > $1.createdAt }
    }

    func save(_ conversation: Conversation) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601

        let fileURL = directory.appendingPathComponent("\(conversation.id.uuidString).json")

        guard let data = try? encoder.encode(conversation) else { return }
        try? data.write(to: fileURL, options: .atomic)

        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        } else {
            conversations.append(conversation)
            conversations.sort { $0.createdAt > $1.createdAt }
        }
    }

    func delete(_ conversation: Conversation) {
        let fileURL = directory.appendingPathComponent("\(conversation.id.uuidString).json")
        try? FileManager.default.removeItem(at: fileURL)
        conversations.removeAll { $0.id == conversation.id }
    }

    func create() -> Conversation {
        let conversation = Conversation()
        save(conversation)
        return conversation
    }
}
