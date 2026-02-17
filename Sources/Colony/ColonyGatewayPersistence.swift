import Foundation
import HiveCore

public struct ColonyRuntimeSessionID: Hashable, Codable, Sendable, Equatable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum ColonyRuntimeMessageRole: String, Codable, Sendable, Equatable {
    case user
    case assistant
    case system
    case tool
}

public struct ColonyRuntimeMessage: Codable, Sendable, Equatable {
    public var id: String
    public var role: ColonyRuntimeMessageRole
    public var content: String
    public var createdAt: Date
    public var metadata: [String: String]

    public init(
        id: String = "message:" + UUID().uuidString.lowercased(),
        role: ColonyRuntimeMessageRole,
        content: String,
        createdAt: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.metadata = metadata
    }
}

public struct ColonyRuntimeSessionRecord: Codable, Sendable, Equatable {
    public var sessionID: ColonyRuntimeSessionID
    public var threadID: String
    public var createdAt: Date
    public var updatedAt: Date
    public var metadata: [String: String]

    public init(
        sessionID: ColonyRuntimeSessionID,
        threadID: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.sessionID = sessionID
        self.threadID = threadID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
    }
}

public protocol ColonyRuntimeStateMigrator: Sendable {
    func migrate(
        payload: Data,
        fromSchemaVersion: Int,
        toSchemaVersion: Int
    ) throws -> Data
}

public struct ColonyPassthroughRuntimeStateMigrator: ColonyRuntimeStateMigrator {
    public init() {}

    public func migrate(payload: Data, fromSchemaVersion: Int, toSchemaVersion: Int) throws -> Data {
        _ = fromSchemaVersion
        _ = toSchemaVersion
        return payload
    }
}

public enum ColonyRuntimeSessionStoreError: Error, Sendable, Equatable {
    case duplicateSession(ColonyRuntimeSessionID)
    case sessionNotFound(ColonyRuntimeSessionID)
}

public protocol ColonyRuntimeSessionStore: Sendable {
    func createSession(_ session: ColonyRuntimeSessionRecord) async throws
    func getSession(id: ColonyRuntimeSessionID) async throws -> ColonyRuntimeSessionRecord?
    func updateSession(_ session: ColonyRuntimeSessionRecord) async throws
    func appendMessage(_ message: ColonyRuntimeMessage, sessionID: ColonyRuntimeSessionID) async throws
    func messageHistory(sessionID: ColonyRuntimeSessionID, limit: Int?) async throws -> [ColonyRuntimeMessage]
    func runID(forIdempotencyKey key: String, sessionID: ColonyRuntimeSessionID) async throws -> UUID?
    func recordRunID(_ runID: UUID, forIdempotencyKey key: String, sessionID: ColonyRuntimeSessionID) async throws
}

public actor ColonyInMemoryRuntimeSessionStore: ColonyRuntimeSessionStore {
    private var sessions: [ColonyRuntimeSessionID: ColonyRuntimeSessionRecord] = [:]
    private var messagesBySessionID: [ColonyRuntimeSessionID: [ColonyRuntimeMessage]] = [:]
    private var idempotentRunIDsBySessionID: [ColonyRuntimeSessionID: [String: UUID]] = [:]

    public init() {}

    public func createSession(_ session: ColonyRuntimeSessionRecord) throws {
        guard sessions[session.sessionID] == nil else {
            throw ColonyRuntimeSessionStoreError.duplicateSession(session.sessionID)
        }
        sessions[session.sessionID] = session
        messagesBySessionID[session.sessionID] = []
        idempotentRunIDsBySessionID[session.sessionID] = [:]
    }

    public func getSession(id: ColonyRuntimeSessionID) -> ColonyRuntimeSessionRecord? {
        sessions[id]
    }

    public func updateSession(_ session: ColonyRuntimeSessionRecord) throws {
        guard sessions[session.sessionID] != nil else {
            throw ColonyRuntimeSessionStoreError.sessionNotFound(session.sessionID)
        }
        sessions[session.sessionID] = session
    }

    public func appendMessage(_ message: ColonyRuntimeMessage, sessionID: ColonyRuntimeSessionID) throws {
        guard sessions[sessionID] != nil else {
            throw ColonyRuntimeSessionStoreError.sessionNotFound(sessionID)
        }
        var history = messagesBySessionID[sessionID, default: []]
        history.append(message)
        messagesBySessionID[sessionID] = history
    }

    public func messageHistory(sessionID: ColonyRuntimeSessionID, limit: Int?) throws -> [ColonyRuntimeMessage] {
        guard sessions[sessionID] != nil else {
            throw ColonyRuntimeSessionStoreError.sessionNotFound(sessionID)
        }
        let history = messagesBySessionID[sessionID, default: []]
        if let limit, limit > 0 {
            return Array(history.suffix(limit))
        }
        return history
    }

    public func runID(forIdempotencyKey key: String, sessionID: ColonyRuntimeSessionID) throws -> UUID? {
        guard sessions[sessionID] != nil else {
            throw ColonyRuntimeSessionStoreError.sessionNotFound(sessionID)
        }
        return idempotentRunIDsBySessionID[sessionID]?[key]
    }

    public func recordRunID(_ runID: UUID, forIdempotencyKey key: String, sessionID: ColonyRuntimeSessionID) throws {
        guard sessions[sessionID] != nil else {
            throw ColonyRuntimeSessionStoreError.sessionNotFound(sessionID)
        }
        var map = idempotentRunIDsBySessionID[sessionID, default: [:]]
        map[key] = map[key] ?? runID
        idempotentRunIDsBySessionID[sessionID] = map
    }
}

public actor ColonyJSONRuntimeSessionStore: ColonyRuntimeSessionStore {
    private struct PersistedSessionEnvelope: Codable {
        var schemaVersion: Int
        var session: ColonyRuntimeSessionRecord
        var messages: [ColonyRuntimeMessage]
        var idempotentRunIDs: [String: String]
    }

    private let baseURL: URL
    private let fileManager: FileManager
    private let schemaVersion: Int
    private let migrator: any ColonyRuntimeStateMigrator
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        baseURL: URL,
        schemaVersion: Int = 1,
        migrator: any ColonyRuntimeStateMigrator = ColonyPassthroughRuntimeStateMigrator(),
        fileManager: FileManager = .default
    ) throws {
        self.baseURL = baseURL
        self.fileManager = fileManager
        self.schemaVersion = max(1, schemaVersion)
        self.migrator = migrator

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        try ColonyPersistenceIO.ensureDirectoryExists(baseURL, fileManager: fileManager)
    }

    public func createSession(_ session: ColonyRuntimeSessionRecord) throws {
        let fileURL = sessionFileURL(for: session.sessionID)
        guard fileManager.fileExists(atPath: fileURL.path) == false else {
            throw ColonyRuntimeSessionStoreError.duplicateSession(session.sessionID)
        }

        let envelope = PersistedSessionEnvelope(
            schemaVersion: schemaVersion,
            session: session,
            messages: [],
            idempotentRunIDs: [:]
        )
        try ColonyPersistenceIO.writeJSON(envelope, to: fileURL, encoder: encoder, fileManager: fileManager)
    }

    public func getSession(id: ColonyRuntimeSessionID) throws -> ColonyRuntimeSessionRecord? {
        try loadEnvelope(sessionID: id)?.session
    }

    public func updateSession(_ session: ColonyRuntimeSessionRecord) throws {
        guard var envelope = try loadEnvelope(sessionID: session.sessionID) else {
            throw ColonyRuntimeSessionStoreError.sessionNotFound(session.sessionID)
        }
        envelope.session = session
        envelope.session.updatedAt = Date()
        try saveEnvelope(envelope, sessionID: session.sessionID)
    }

    public func appendMessage(_ message: ColonyRuntimeMessage, sessionID: ColonyRuntimeSessionID) throws {
        guard var envelope = try loadEnvelope(sessionID: sessionID) else {
            throw ColonyRuntimeSessionStoreError.sessionNotFound(sessionID)
        }
        envelope.messages.append(message)
        envelope.session.updatedAt = Date()
        try saveEnvelope(envelope, sessionID: sessionID)
    }

    public func messageHistory(sessionID: ColonyRuntimeSessionID, limit: Int?) throws -> [ColonyRuntimeMessage] {
        guard let envelope = try loadEnvelope(sessionID: sessionID) else {
            throw ColonyRuntimeSessionStoreError.sessionNotFound(sessionID)
        }

        if let limit, limit > 0 {
            return Array(envelope.messages.suffix(limit))
        }
        return envelope.messages
    }

    public func runID(forIdempotencyKey key: String, sessionID: ColonyRuntimeSessionID) throws -> UUID? {
        guard let envelope = try loadEnvelope(sessionID: sessionID) else {
            throw ColonyRuntimeSessionStoreError.sessionNotFound(sessionID)
        }
        guard let raw = envelope.idempotentRunIDs[key] else { return nil }
        return UUID(uuidString: raw)
    }

    public func recordRunID(_ runID: UUID, forIdempotencyKey key: String, sessionID: ColonyRuntimeSessionID) throws {
        guard var envelope = try loadEnvelope(sessionID: sessionID) else {
            throw ColonyRuntimeSessionStoreError.sessionNotFound(sessionID)
        }
        if envelope.idempotentRunIDs[key] == nil {
            envelope.idempotentRunIDs[key] = runID.uuidString.lowercased()
        }
        envelope.session.updatedAt = Date()
        try saveEnvelope(envelope, sessionID: sessionID)
    }

    private func loadEnvelope(sessionID: ColonyRuntimeSessionID) throws -> PersistedSessionEnvelope? {
        let fileURL = sessionFileURL(for: sessionID)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        if let direct = try? decoder.decode(PersistedSessionEnvelope.self, from: data),
           direct.schemaVersion == schemaVersion
        {
            return direct
        }

        // Apply migration contract if persisted schema differs from current schema.
        let oldContainer = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = oldContainer as? [String: Any],
              let fromSchema = dictionary["schemaVersion"] as? Int
        else {
            throw ColonyProviderError.malformedResponse("session-store")
        }

        let migrated = try migrator.migrate(
            payload: data,
            fromSchemaVersion: fromSchema,
            toSchemaVersion: schemaVersion
        )
        var envelope = try decoder.decode(PersistedSessionEnvelope.self, from: migrated)
        envelope.schemaVersion = schemaVersion
        try saveEnvelope(envelope, sessionID: sessionID)
        return envelope
    }

    private func saveEnvelope(_ envelope: PersistedSessionEnvelope, sessionID: ColonyRuntimeSessionID) throws {
        let fileURL = sessionFileURL(for: sessionID)
        try ColonyPersistenceIO.writeJSON(envelope, to: fileURL, encoder: encoder, fileManager: fileManager)
    }

    private func sessionFileURL(for sessionID: ColonyRuntimeSessionID) -> URL {
        let safe = ColonyPersistenceIO.safeFileComponent(sessionID.rawValue)
        return baseURL.appendingPathComponent("session-\(safe).json", isDirectory: false)
    }
}

public protocol ColonyRuntimeCheckpointStore: Sendable {
    func save(_ checkpoint: HiveCheckpoint<ColonySchema>) async throws
    func loadLatest(threadID: HiveThreadID) async throws -> HiveCheckpoint<ColonySchema>?
}

public actor ColonyInMemoryRuntimeCheckpointStore: ColonyRuntimeCheckpointStore {
    private var checkpoints: [HiveCheckpoint<ColonySchema>] = []

    public init() {}

    public func save(_ checkpoint: HiveCheckpoint<ColonySchema>) async {
        checkpoints.append(checkpoint)
    }

    public func loadLatest(threadID: HiveThreadID) async -> HiveCheckpoint<ColonySchema>? {
        checkpoints
            .filter { $0.threadID == threadID }
            .max { lhs, rhs in
                if lhs.stepIndex == rhs.stepIndex {
                    return lhs.id.rawValue < rhs.id.rawValue
                }
                return lhs.stepIndex < rhs.stepIndex
            }
    }
}

public actor ColonyDurableRuntimeCheckpointStoreAdapter: ColonyRuntimeCheckpointStore {
    private let durableStore: ColonyDurableCheckpointStore<ColonySchema>

    public init(baseURL: URL) throws {
        self.durableStore = try ColonyDurableCheckpointStore<ColonySchema>(baseURL: baseURL)
    }

    public func save(_ checkpoint: HiveCheckpoint<ColonySchema>) async throws {
        try await durableStore.save(checkpoint)
    }

    public func loadLatest(threadID: HiveThreadID) async throws -> HiveCheckpoint<ColonySchema>? {
        try await durableStore.loadLatest(threadID: threadID)
    }
}
