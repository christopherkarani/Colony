import Foundation
import HiveCore

public actor ColonyDurableCheckpointStore<Schema: HiveSchema>: HiveCheckpointQueryableStore {
    private let baseURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseURL: URL, fileManager: FileManager = .default) throws {
        self.baseURL = baseURL
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()

        try ColonyPersistenceIO.ensureDirectoryExists(baseURL, fileManager: fileManager)
    }

    public func save(_ checkpoint: HiveCheckpoint<Schema>) async throws {
        let threadDirectory = threadDirectoryURL(threadID: checkpoint.threadID)
        try ColonyPersistenceIO.ensureDirectoryExists(threadDirectory, fileManager: fileManager)

        let fileName = checkpointFileName(for: checkpoint)
        let fileURL = threadDirectory.appendingPathComponent(fileName, isDirectory: false)
        try ColonyPersistenceIO.writeJSON(checkpoint, to: fileURL, encoder: encoder, fileManager: fileManager)
    }

    public func loadLatest(threadID: HiveThreadID) async throws -> HiveCheckpoint<Schema>? {
        let checkpoints = try loadCheckpoints(threadID: threadID)
        return checkpoints.max(by: { lhs, rhs in
            if lhs.checkpoint.stepIndex != rhs.checkpoint.stepIndex {
                return lhs.checkpoint.stepIndex < rhs.checkpoint.stepIndex
            }
            return lhs.url.lastPathComponent < rhs.url.lastPathComponent
        })?.checkpoint
    }

    public func listCheckpoints(threadID: HiveThreadID, limit: Int?) async throws -> [HiveCheckpointSummary] {
        if let limit, limit <= 0 {
            return []
        }

        let checkpoints = try loadCheckpoints(threadID: threadID)
            .sorted(by: { lhs, rhs in
                if lhs.checkpoint.stepIndex != rhs.checkpoint.stepIndex {
                    return lhs.checkpoint.stepIndex > rhs.checkpoint.stepIndex
                }
                return lhs.url.lastPathComponent > rhs.url.lastPathComponent
            })

        let summaries = checkpoints.map { entry in
            HiveCheckpointSummary(
                id: entry.checkpoint.id,
                threadID: entry.checkpoint.threadID,
                runID: entry.checkpoint.runID,
                stepIndex: entry.checkpoint.stepIndex,
                schemaVersion: entry.checkpoint.schemaVersion,
                graphVersion: entry.checkpoint.graphVersion,
                createdAt: ColonyPersistenceIO.fileCreationDate(at: entry.url, fileManager: fileManager),
                backendID: entry.url.lastPathComponent
            )
        }

        if let limit {
            return Array(summaries.prefix(limit))
        }
        return summaries
    }

    public func loadCheckpoint(threadID: HiveThreadID, id: HiveCheckpointID) async throws -> HiveCheckpoint<Schema>? {
        let checkpoints = try loadCheckpoints(threadID: threadID)
            .filter { $0.checkpoint.id == id }
            .sorted(by: { lhs, rhs in
                if lhs.checkpoint.stepIndex != rhs.checkpoint.stepIndex {
                    return lhs.checkpoint.stepIndex > rhs.checkpoint.stepIndex
                }
                return lhs.url.lastPathComponent > rhs.url.lastPathComponent
            })

        return checkpoints.first?.checkpoint
    }

    private func loadCheckpoints(threadID: HiveThreadID) throws -> [(checkpoint: HiveCheckpoint<Schema>, url: URL)] {
        let threadDirectory = threadDirectoryURL(threadID: threadID)
        let files = try ColonyPersistenceIO.listFiles(in: threadDirectory, fileManager: fileManager)
            .filter { $0.pathExtension == "json" }

        var checkpoints: [(checkpoint: HiveCheckpoint<Schema>, url: URL)] = []
        checkpoints.reserveCapacity(files.count)

        for file in files {
            let checkpoint = try ColonyPersistenceIO.readJSON(HiveCheckpoint<Schema>.self, from: file, decoder: decoder)
            checkpoints.append((checkpoint: checkpoint, url: file))
        }

        return checkpoints
    }

    private func threadDirectoryURL(threadID: HiveThreadID) -> URL {
        let name = ColonyPersistenceIO.stableThreadDirectoryName(threadID: threadID)
        return baseURL.appendingPathComponent(name, isDirectory: true)
    }

    private func checkpointFileName(for checkpoint: HiveCheckpoint<Schema>) -> String {
        let step = String(format: "%012d", checkpoint.stepIndex)
        let checkpointID = ColonyPersistenceIO.safeFileComponent(checkpoint.id.rawValue)
        let runID = checkpoint.runID.rawValue.uuidString.lowercased()
        return "checkpoint-\(step)-\(runID)-\(checkpointID).json"
    }
}
