import Foundation
import HiveCore

/// Policy for artifact retention management.
///
/// Controls how many artifacts to keep and how old they can be.
public struct ColonyArtifactRetentionPolicy: Sendable {
    /// Maximum number of artifacts to retain. nil means unlimited.
    public var maxArtifacts: Int?

    /// Maximum age of artifacts in seconds. nil means unlimited.
    public var maxAge: TimeInterval?

    /// Creates a new retention policy.
    ///
    /// - Parameters:
    ///   - maxArtifacts: Maximum artifact count. Defaults to nil (unlimited).
    ///   - maxAge: Maximum artifact age. Defaults to nil (unlimited).
    public init(maxArtifacts: Int? = nil, maxAge: TimeInterval? = nil) {
        self.maxArtifacts = maxArtifacts
        self.maxAge = maxAge
    }
}

/// Record describing a stored artifact.
///
/// Contains metadata about an artifact without the content itself.
public struct ColonyArtifactRecord: Codable, Sendable, Equatable {
    /// Unique identifier for this artifact.
    public let id: ColonyArtifactID

    /// The thread this artifact belongs to.
    public let threadID: ColonyThreadID

    /// The run that created this artifact, if any.
    public let runID: ColonyRunID?

    /// Kind of artifact (e.g., "file", "code", "result").
    public let kind: String

    /// When the artifact was created.
    public let createdAt: Date

    /// Whether the artifact content was redacted.
    public let redacted: Bool

    /// Additional metadata about the artifact.
    public let metadata: [String: String]

    /// Creates a new artifact record.
    ///
    /// - Parameters:
    ///   - id: Artifact ID.
    ///   - threadID: Thread ID.
    ///   - runID: Optional run ID.
    ///   - kind: Artifact kind.
    ///   - createdAt: Creation timestamp.
    ///   - redacted: Whether content was redacted.
    ///   - metadata: Additional metadata.
    public init(
        id: ColonyArtifactID,
        threadID: ColonyThreadID,
        runID: ColonyRunID?,
        kind: String,
        createdAt: Date,
        redacted: Bool,
        metadata: [String: String]
    ) {
        self.id = id
        self.threadID = threadID
        self.runID = runID
        self.kind = kind
        self.createdAt = createdAt
        self.redacted = redacted
        self.metadata = metadata
    }
}

/// A durable store for agent artifacts.
///
/// Artifacts are named content produced by the agent (code files, generated docs, etc.)
/// that outlast the run that created them.
public actor ColonyArtifactStore {
    private struct StoredArtifact: Codable, Sendable {
        let record: ColonyArtifactRecord
        let content: String
    }

    private let artifactsDirectoryURL: URL
    private let fileManager: FileManager
    private let retentionPolicy: ColonyArtifactRetentionPolicy
    private let redactionPolicy: ColonyRedactionPolicy
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Creates a new artifact store.
    ///
    /// - Parameters:
    ///   - baseURL: Base directory for artifact storage.
    ///   - retentionPolicy: Policy for artifact retention.
    ///   - redactionPolicy: Policy for redacting sensitive data.
    ///   - fileManager: File manager to use.
    /// - Throws: If the artifacts directory cannot be created.
    public init(
        baseURL: URL,
        retentionPolicy: ColonyArtifactRetentionPolicy = ColonyArtifactRetentionPolicy(),
        redactionPolicy: ColonyRedactionPolicy = ColonyRedactionPolicy(),
        fileManager: FileManager = .default
    ) throws {
        self.artifactsDirectoryURL = baseURL.appendingPathComponent("artifacts", isDirectory: true)
        self.retentionPolicy = retentionPolicy
        self.redactionPolicy = redactionPolicy
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        try ColonyPersistenceIO.ensureDirectoryExists(artifactsDirectoryURL, fileManager: fileManager)
    }

    /// Stores a new artifact.
    ///
    /// - Parameters:
    ///   - threadID: Thread ID for the artifact.
    ///   - runID: Optional run ID.
    ///   - kind: Kind of artifact.
    ///   - content: The artifact content.
    ///   - metadata: Additional metadata.
    ///   - redact: Whether to redact sensitive data.
    ///   - createdAt: Creation timestamp.
    /// - Returns: The artifact record.
    @discardableResult
    public func put(
        threadID: ColonyThreadID,
        runID: ColonyRunID?,
        kind: String,
        content: String,
        metadata: [String: String] = [:],
        redact: Bool = true,
        createdAt: Date = Date()
    ) async throws -> ColonyArtifactRecord {
        let artifactID = ColonyArtifactID(UUID().uuidString.lowercased())
        let cleanedMetadata = redact ? redactionPolicy.redact(values: metadata) : metadata
        let cleanedContent = redact ? redactionPolicy.redactInlineSecrets(in: content) : content

        let record = ColonyArtifactRecord(
            id: artifactID,
            threadID: threadID,
            runID: runID,
            kind: kind,
            createdAt: createdAt,
            redacted: redact,
            metadata: cleanedMetadata
        )

        let stored = StoredArtifact(record: record, content: cleanedContent)
        let artifactURL = artifactURLForID(artifactID.rawValue)
        try ColonyPersistenceIO.writeJSON(stored, to: artifactURL, encoder: encoder, fileManager: fileManager)

        _ = try await enforceRetention(now: createdAt)
        return record
    }

    /// Lists artifact records matching the given criteria.
    ///
    /// - Parameters:
    ///   - threadID: Filter by thread ID.
    ///   - runID: Filter by run ID.
    ///   - kind: Filter by artifact kind.
    ///   - limit: Maximum number to return.
    /// - Returns: Matching artifact records, newest first.
    public func list(
        threadID: ColonyThreadID? = nil,
        runID: ColonyRunID? = nil,
        kind: String? = nil,
        limit: Int? = nil
    ) async throws -> [ColonyArtifactRecord] {
        if let limit, limit <= 0 {
            return []
        }

        let artifacts = try loadStoredArtifacts()
            .map(\.record)
            .filter { record in
                if let threadID, record.threadID != threadID { return false }
                if let runID, record.runID != runID { return false }
                if let kind, record.kind != kind { return false }
                return true
            }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.id.rawValue > rhs.id.rawValue
            }

        if let limit {
            return Array(artifacts.prefix(limit))
        }

        return artifacts
    }

    /// Reads the content of an artifact by ID.
    ///
    /// - Parameter id: The artifact ID.
    /// - Returns: The artifact content, or nil if not found.
    public func readContent(id: String) async throws -> String? {
        let url = artifactURLForID(id)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let artifact = try ColonyPersistenceIO.readJSON(StoredArtifact.self, from: url, decoder: decoder)
        return artifact.content
    }

    /// Enforces retention policy by removing expired artifacts.
    ///
    /// - Parameter now: Reference time for age calculation.
    /// - Returns: IDs of removed artifacts.
    @discardableResult
    public func enforceRetention(now: Date = Date()) async throws -> [String] {
        let artifacts = try loadStoredArtifacts()
            .sorted { lhs, rhs in
                if lhs.record.createdAt != rhs.record.createdAt {
                    return lhs.record.createdAt < rhs.record.createdAt
                }
                return lhs.record.id.rawValue < rhs.record.id.rawValue
            }

        var removeIDs: Set<String> = []

        if let maxAge = retentionPolicy.maxAge {
            let threshold = now.addingTimeInterval(-maxAge)
            for artifact in artifacts where artifact.record.createdAt < threshold {
                removeIDs.insert(artifact.record.id.rawValue)
            }
        }

        if let maxArtifacts = retentionPolicy.maxArtifacts, maxArtifacts >= 0 {
            let kept = artifacts.filter { removeIDs.contains($0.record.id.rawValue) == false }
            if kept.count > maxArtifacts {
                let overflow = kept.count - maxArtifacts
                for artifact in kept.prefix(overflow) {
                    removeIDs.insert(artifact.record.id.rawValue)
                }
            }
        }

        let removed = Array(removeIDs).sorted()
        for id in removed {
            try? fileManager.removeItem(at: artifactURLForID(id))
        }

        return removed
    }

    private func loadStoredArtifacts() throws -> [StoredArtifact] {
        let files = try ColonyPersistenceIO.listFiles(in: artifactsDirectoryURL, fileManager: fileManager)
            .filter { $0.pathExtension == "json" }

        var artifacts: [StoredArtifact] = []
        artifacts.reserveCapacity(files.count)

        for file in files {
            artifacts.append(try ColonyPersistenceIO.readJSON(StoredArtifact.self, from: file, decoder: decoder))
        }

        return artifacts
    }

    private func artifactURLForID(_ id: String) -> URL {
        let safeID = ColonyPersistenceIO.safeFileComponent(id)
        return artifactsDirectoryURL.appendingPathComponent("artifact-\(safeID).json", isDirectory: false)
    }
}
