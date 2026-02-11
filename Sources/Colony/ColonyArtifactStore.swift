import Foundation
import HiveCore

public struct ColonyArtifactRetentionPolicy: Sendable {
    public var maxArtifacts: Int?
    public var maxAge: TimeInterval?

    public init(maxArtifacts: Int? = nil, maxAge: TimeInterval? = nil) {
        self.maxArtifacts = maxArtifacts
        self.maxAge = maxAge
    }
}

public struct ColonyArtifactRecord: Codable, Sendable, Equatable {
    public let id: String
    public let threadID: String
    public let runID: UUID?
    public let kind: String
    public let createdAt: Date
    public let redacted: Bool
    public let metadata: [String: String]

    public init(
        id: String,
        threadID: String,
        runID: UUID?,
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
        threadID: HiveThreadID,
        runID: HiveRunID?,
        kind: String,
        content: String,
        metadata: [String: String] = [:],
        redact: Bool = true,
        createdAt: Date = Date()
    ) async throws -> ColonyArtifactRecord {
        let artifactID = UUID().uuidString.lowercased()
        let cleanedMetadata = redact ? redactionPolicy.redact(values: metadata) : metadata
        let cleanedContent = redact ? redactionPolicy.redactInlineSecrets(in: content) : content

        let record = ColonyArtifactRecord(
            id: artifactID,
            threadID: threadID.rawValue,
            runID: runID?.rawValue,
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
        threadID: HiveThreadID? = nil,
        runID: HiveRunID? = nil,
        kind: String? = nil,
        limit: Int? = nil
    ) async throws -> [ColonyArtifactRecord] {
        if let limit, limit <= 0 {
            return []
        }

        let artifacts = try loadStoredArtifacts()
            .map(\.record)
            .filter { record in
                if let threadID, record.threadID != threadID.rawValue { return false }
                if let runID, record.runID != runID.rawValue { return false }
                if let kind, record.kind != kind { return false }
                return true
            }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.id > rhs.id
            }

        if let limit {
            return Array(artifacts.prefix(limit))
        }

        return artifacts
    }

    public func readContent(id: String) async throws -> String? {
        let url = artifactURLForID(id)
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
                return lhs.record.id < rhs.record.id
            }

        var removeIDs: Set<String> = []

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
