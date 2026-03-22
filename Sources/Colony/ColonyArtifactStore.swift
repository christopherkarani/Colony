import Foundation
import ColonyCore

/// Type-safe artifact kind with autocomplete for standard kinds.
///
/// Artifacts are persisted content produced during agent execution, such as
/// conversation history summaries, large tool outputs, or checkpoint data.
public struct ColonyArtifactKind: Hashable, Codable, Sendable,
                                   ExpressibleByStringLiteral,
                                   CustomStringConvertible {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(value) }
    public var description: String { rawValue }
}

extension ColonyArtifactKind {
    /// Offloaded conversation history for a thread
    public static let conversationHistory: ColonyArtifactKind = "conversation_history"
    /// Large tool output that exceeded context budget
    public static let largeToolResult: ColonyArtifactKind = "large_tool_result"
    /// Runtime checkpoint for interrupt/resume
    public static let checkpoint: ColonyArtifactKind = "checkpoint"
    /// Summarized content
    public static let summary: ColonyArtifactKind = "summary"
}

/// Policy for artifact retention limits.
public struct ColonyArtifactRetentionPolicy: Sendable {
    /// Maximum number of artifacts to retain (oldest are deleted first)
    public var maxArtifacts: Int?
    /// Maximum age of artifacts in seconds (older are deleted)
    public var maxAge: TimeInterval?

    public init(maxArtifacts: Int? = nil, maxAge: TimeInterval? = nil) {
        self.maxArtifacts = maxArtifacts
        self.maxAge = maxAge
    }
}

/// A single artifact record representing persisted content from agent execution.
///
/// Artifacts are stored separately from the main conversation state to keep
/// context windows small. Each record includes metadata about what created
/// it and when.
public struct ColonyArtifactRecord: Codable, Sendable, Equatable {
    public let id: ColonyArtifactID
    public let threadID: ColonyThreadID
    public let runID: UUID?
    public let kind: ColonyArtifactKind
    public let createdAt: Date
    public let redacted: Bool
    public let metadata: [String: String]

    public init(
        id: ColonyArtifactID = ColonyArtifactID(UUID().uuidString),
        threadID: ColonyThreadID,
        runID: UUID?,
        kind: ColonyArtifactKind,
        createdAt: Date = Date(),
        redacted: Bool = true,
        metadata: [String: String] = [:]
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

    @discardableResult
    public func put(
        threadID: ColonyThreadID,
        runID: UUID?,
        kind: ColonyArtifactKind,
        content: String,
        metadata: [String: String] = [:],
        redact: Bool = true,
        createdAt: Date = Date()
    ) async throws -> ColonyArtifactRecord {
        let artifactID = UUID().uuidString.lowercased()
        let cleanedMetadata = redact ? redactionPolicy.redact(values: metadata) : metadata
        let cleanedContent = redact ? redactionPolicy.redactInlineSecrets(in: content) : content

        let record = ColonyArtifactRecord(
            id: ColonyArtifactID(artifactID),
            threadID: threadID,
            runID: runID,
            kind: kind,
            createdAt: createdAt,
            redacted: redact,
            metadata: cleanedMetadata
        )

        let stored = StoredArtifact(record: record, content: cleanedContent)
        let artifactURL = artifactURLForID(artifactID)
        try ColonyPersistenceIO.writeJSON(stored, to: artifactURL, encoder: encoder, fileManager: fileManager)

        _ = try await enforceRetention(now: createdAt)
        return record
    }

    public func list(
        threadID: ColonyThreadID? = nil,
        runID: UUID? = nil,
        kind: ColonyArtifactKind? = nil,
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

    public func readContent(id: ColonyArtifactID) async throws -> String? {
        let url = artifactURLForID(id.rawValue)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let artifact = try ColonyPersistenceIO.readJSON(StoredArtifact.self, from: url, decoder: decoder)
        return artifact.content
    }

    @discardableResult
    public func enforceRetention(now: Date = Date()) async throws -> [String] {
        let artifacts = try loadStoredArtifacts()
            .sorted { lhs, rhs in
                if lhs.record.createdAt != rhs.record.createdAt {
                    return lhs.record.createdAt < rhs.record.createdAt
                }
                return lhs.record.id.rawValue < rhs.record.id.rawValue
            }

        var removeIDs: Set<ColonyArtifactID> = []

        if let maxAge = retentionPolicy.maxAge {
            let threshold = now.addingTimeInterval(-maxAge)
            for artifact in artifacts where artifact.record.createdAt < threshold {
                removeIDs.insert(artifact.record.id)
            }
        }

        if let maxArtifacts = retentionPolicy.maxArtifacts, maxArtifacts >= 0 {
            let kept = artifacts.filter { removeIDs.contains($0.record.id) == false }
            if kept.count > maxArtifacts {
                let overflow = kept.count - maxArtifacts
                for artifact in kept.prefix(overflow) {
                    removeIDs.insert(artifact.record.id)
                }
            }
        }

        let removed = Array(removeIDs).sorted { $0.rawValue < $1.rawValue }
        for id in removed {
            try? fileManager.removeItem(at: artifactURLForID(id.rawValue))
        }

        return removed.map(\.rawValue)
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
