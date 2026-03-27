import Foundation

public struct ColonyCheckpointSummary: Sendable, Equatable {
    public let id: ColonyCheckpointID
    public let threadID: ColonyThreadID
    public let runID: ColonyRunID
    public let stepIndex: Int
    public let createdAt: Date?
    public let backendID: String

    public init(
        id: ColonyCheckpointID,
        threadID: ColonyThreadID,
        runID: ColonyRunID,
        stepIndex: Int,
        createdAt: Date?,
        backendID: String
    ) {
        self.id = id
        self.threadID = threadID
        self.runID = runID
        self.stepIndex = stepIndex
        self.createdAt = createdAt
        self.backendID = backendID
    }
}

package actor ColonyDurableCheckpointStore: ColonyCheckpointStore {
    private let baseURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    package init(baseURL: URL, fileManager: FileManager = .default) throws {
        self.baseURL = baseURL
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        try ColonyPersistenceIO.ensureDirectoryExists(baseURL, fileManager: fileManager)
    }

    package func save(_ checkpoint: ColonyCheckpointSnapshot) async throws {
        let threadDirectory = threadDirectoryURL(threadID: checkpoint.threadID)
        try ColonyPersistenceIO.ensureDirectoryExists(threadDirectory, fileManager: fileManager)

        let fileName = checkpointFileName(for: checkpoint)
        let fileURL = threadDirectory.appendingPathComponent(fileName, isDirectory: false)
        try ColonyPersistenceIO.writeJSON(checkpoint, to: fileURL, encoder: encoder, fileManager: fileManager)
    }

    package func loadLatest(threadID: ColonyThreadID) async throws -> ColonyCheckpointSnapshot? {
        let checkpoints = try loadCheckpoints(threadID: threadID)
        return checkpoints.max {
            if $0.checkpoint.stepIndex == $1.checkpoint.stepIndex {
                return $0.url.lastPathComponent < $1.url.lastPathComponent
            }
            return $0.checkpoint.stepIndex < $1.checkpoint.stepIndex
        }?.checkpoint
    }

    package func loadCheckpoint(threadID: ColonyThreadID, id: ColonyCheckpointID) async throws -> ColonyCheckpointSnapshot? {
        try loadCheckpoints(threadID: threadID)
            .last { $0.checkpoint.id == id }?
            .checkpoint
    }

    package func loadByInterruptID(threadID: ColonyThreadID, interruptID: ColonyInterruptID) async throws -> ColonyCheckpointSnapshot? {
        try loadCheckpoints(threadID: threadID)
            .last { $0.checkpoint.interruptID == interruptID }?
            .checkpoint
    }

    public func listCheckpoints(threadID: ColonyThreadID, limit: Int?) async throws -> [ColonyCheckpointSummary] {
        if let limit, limit <= 0 {
            return []
        }

        let checkpoints = try loadCheckpoints(threadID: threadID)
            .sorted {
                if $0.checkpoint.stepIndex == $1.checkpoint.stepIndex {
                    return $0.url.lastPathComponent > $1.url.lastPathComponent
                }
                return $0.checkpoint.stepIndex > $1.checkpoint.stepIndex
            }

        let summaries = checkpoints.map { entry in
            ColonyCheckpointSummary(
                id: entry.checkpoint.id,
                threadID: entry.checkpoint.threadID,
                runID: entry.checkpoint.runID,
                stepIndex: entry.checkpoint.stepIndex,
                createdAt: ColonyPersistenceIO.fileCreationDate(at: entry.url, fileManager: fileManager),
                backendID: entry.url.lastPathComponent
            )
        }

        if let limit {
            return Array(summaries.prefix(limit))
        }
        return summaries
    }

    private func loadCheckpoints(threadID: ColonyThreadID) throws -> [(checkpoint: ColonyCheckpointSnapshot, url: URL)] {
        let threadDirectory = threadDirectoryURL(threadID: threadID)
        let files = try ColonyPersistenceIO.listFiles(in: threadDirectory, fileManager: fileManager)
            .filter { $0.pathExtension == "json" }

        return try files.map { file in
            let checkpoint = try ColonyPersistenceIO.readJSON(
                ColonyCheckpointSnapshot.self,
                from: file,
                decoder: decoder
            )
            return (checkpoint, file)
        }
    }

    private func threadDirectoryURL(threadID: ColonyThreadID) -> URL {
        let name = ColonyPersistenceIO.stableThreadDirectoryName(threadID: threadID)
        return baseURL.appendingPathComponent(name, isDirectory: true)
    }

    private func checkpointFileName(for checkpoint: ColonyCheckpointSnapshot) -> String {
        let step = String(format: "%012d", checkpoint.stepIndex)
        let checkpointID = ColonyPersistenceIO.safeFileComponent(checkpoint.id.rawValue)
        let runID = ColonyPersistenceIO.safeFileComponent(checkpoint.runID.rawValue.lowercased())
        return "checkpoint-\(step)-\(runID)-\(checkpointID).json"
    }
}
