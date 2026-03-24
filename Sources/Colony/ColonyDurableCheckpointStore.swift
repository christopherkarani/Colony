import Foundation
import HiveCore

/// A durable checkpoint store that persists to the filesystem.
///
/// This store saves checkpoints as JSON files organized by thread ID,
/// enabling recovery of agent state across application restarts.
public actor ColonyDurableCheckpointStore<Schema: HiveSchema>: HiveCheckpointQueryableStore {
    private let baseURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Creates a new durable checkpoint store at the specified URL.
    ///
    /// - Parameters:
    ///   - baseURL: Base directory for checkpoint storage.
    ///   - fileManager: File manager to use. Defaults to `.default`.
    /// - Throws: If the directory cannot be created.
    public init(baseURL: URL, fileManager: FileManager = .default) throws {
        self.baseURL = baseURL
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()

        try ColonyPersistenceIO.ensureDirectoryExists(baseURL, fileManager: fileManager)
    }

    /// Saves a checkpoint to durable storage.
    ///
    /// - Parameter checkpoint: The checkpoint to save.
    public func save(_ checkpoint: HiveCheckpoint<Schema>) async throws {
        let threadDirectory = threadDirectoryURL(threadID: checkpoint.threadID)
        try ColonyPersistenceIO.ensureDirectoryExists(threadDirectory, fileManager: fileManager)

        let fileName = checkpointFileName(for: checkpoint)
        let fileURL = threadDirectory.appendingPathComponent(fileName, isDirectory: false)
        try ColonyPersistenceIO.writeJSON(checkpoint, to: fileURL, encoder: encoder, fileManager: fileManager)
    }

    /// Loads the latest checkpoint for a thread.
    ///
    /// - Parameter threadID: The thread ID to load checkpoints for.
    /// - Returns: The latest checkpoint, or nil if none exist.
    public func loadLatest(threadID: HiveThreadID) async throws -> HiveCheckpoint<Schema>? {
        let checkpoints = try loadCheckpoints(threadID: threadID)
        return checkpoints.max(by: { lhs, rhs in
            if lhs.checkpoint.stepIndex != rhs.checkpoint.stepIndex {
                return lhs.checkpoint.stepIndex < rhs.checkpoint.stepIndex
            }
            return lhs.url.lastPathComponent < rhs.url.lastPathComponent
        })?.checkpoint
    }

    /// Lists checkpoints for a thread with optional limit.
    ///
    /// - Parameters:
    ///   - threadID: The thread ID.
    ///   - limit: Maximum number of checkpoints to return.
    /// - Returns: List of checkpoint summaries, newest first.
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

    /// Loads a specific checkpoint by ID.
    ///
    /// - Parameters:
    ///   - threadID: The thread ID.
    ///   - id: The checkpoint ID.
    /// - Returns: The checkpoint if found.
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
