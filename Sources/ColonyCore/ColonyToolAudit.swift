import CryptoKit
import Foundation

/// The outcome of a tool approval decision.
///
/// Tracks how each tool call was processed through the approval workflow.
public enum ColonyToolAuditDecisionKind: String, Codable, Sendable, Equatable {
    /// Tool required human approval before execution.
    case approvalRequired = "approval_required"
    /// Tool was automatically approved based on policy.
    case autoApproved = "auto_approved"
    /// User explicitly approved this tool call.
    case userApproved = "user_approved"
    /// User explicitly denied this tool call.
    case userDenied = "user_denied"
}

/// A single tool approval decision event in the audit log.
///
/// Captures all context around a tool call decision for compliance and debugging.
public struct ColonyToolAuditEvent: Codable, Sendable, Equatable {
    /// Monotonic timestamp in nanoseconds since an arbitrary epoch.
    public var timestampNanoseconds: UInt64
    /// Identifier for the thread that processed this tool call.
    public var threadID: String
    /// Identifier for the task/agent that initiated this tool call.
    public var taskID: String
    /// Unique identifier for this specific tool call invocation.
    public var toolCallID: String
    /// Name of the tool that was evaluated.
    public var toolName: String
    /// Assessed risk level of the tool at evaluation time.
    public var riskLevel: ColonyToolRiskLevel
    /// The outcome of the approval decision.
    public var decision: ColonyToolAuditDecisionKind
    /// Optional reason why approval was required (if applicable).
    public var reason: ColonyToolApprovalRequirementReason?

    public init(
        timestampNanoseconds: UInt64,
        threadID: String,
        taskID: String,
        toolCallID: String,
        toolName: String,
        riskLevel: ColonyToolRiskLevel,
        decision: ColonyToolAuditDecisionKind,
        reason: ColonyToolApprovalRequirementReason? = nil
    ) {
        self.timestampNanoseconds = timestampNanoseconds
        self.threadID = threadID
        self.taskID = taskID
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.riskLevel = riskLevel
        self.decision = decision
        self.reason = reason
    }
}

/// The payload of a signed audit log entry.
///
/// Contains the sequenced event data with a hash linking to the previous entry,
/// forming a cryptographically verifiable chain of records.
public struct ColonyToolAuditRecordPayload: Codable, Sendable, Equatable {
    /// Monotonically increasing sequence number starting at 1.
    public var sequence: Int
    /// SHA-256 hex digest of the previous entry in the chain (nil for the first entry).
    public var previousEntryHash: String?
    /// The audit event being recorded.
    public var event: ColonyToolAuditEvent

    public init(sequence: Int, previousEntryHash: String?, event: ColonyToolAuditEvent) {
        self.sequence = sequence
        self.previousEntryHash = previousEntryHash
        self.event = event
    }
}

/// A complete signed audit log entry with cryptographic proof.
///
/// Combines the sequenced payload with the entry hash and cryptographic signature,
/// enabling verification of both chain integrity and signer authenticity.
public struct ColonySignedToolAuditRecord: Codable, Sendable, Equatable {
    /// The sequenced audit event payload.
    public var payload: ColonyToolAuditRecordPayload
    /// SHA-256 hex digest of the chained payload data.
    public var entryHash: String
    /// Base64-encoded cryptographic signature of the entry hash.
    public var signatureBase64: String
    /// Algorithm used for signing (e.g., "hmac-sha256").
    public var signatureAlgorithm: String
    /// Identifier of the signing key used.
    public var signerKeyID: String

    public init(
        payload: ColonyToolAuditRecordPayload,
        entryHash: String,
        signatureBase64: String,
        signatureAlgorithm: String,
        signerKeyID: String
    ) {
        self.payload = payload
        self.entryHash = entryHash
        self.signatureBase64 = signatureBase64
        self.signatureAlgorithm = signatureAlgorithm
        self.signerKeyID = signerKeyID
    }
}

/// Errors that can occur when appending records to the audit log.
///
/// These errors indicate chain integrity violations that prevent appending new entries.
public enum ToolAuditError: Error, Sendable, Equatable {
    /// The appended record's sequence number does not match the expected next sequence.
    case invalidSequence(expected: Int, actual: Int)
    /// The appended record's previous entry hash does not match the actual last entry hash.
    case previousHashMismatch(expected: String?, actual: String?)
}

// MARK: - Backward Compatibility

public typealias ColonyToolAuditError = ToolAuditError

/// Protocol for cryptographic signing of audit log entries.
///
/// Implementations provide signing and verification capabilities for the audit chain.
public protocol ColonyToolAuditSigner: Sendable {
    /// Unique identifier for the signing key.
    var keyID: String { get }
    /// Name of the signing algorithm (e.g., "hmac-sha256").
    var algorithm: String { get }
    /// Signs a message and returns the cryptographic signature.
    func sign(message: Data) throws -> Data
    /// Verifies a signature against a message.
    func verify(signature: Data, message: Data) -> Bool
}

/// An HMAC-SHA256 based signer for audit log entries.
///
/// Uses CryptoKit's HMAC with SHA-256 for symmetric-key signing of audit records.
public struct ColonyHMACSHA256ToolAuditSigner: ColonyToolAuditSigner {
    public let keyID: String
    public let algorithm: String = "hmac-sha256"
    private let keyData: Data

    /// Creates a new HMAC-SHA256 signer with the given key data.
    ///
    /// - Parameters:
    ///   - keyData: The shared secret key for HMAC signing.
    ///   - keyID: Identifier for this key (included in signed records).
    public init(keyData: Data, keyID: String = "default") {
        self.keyData = keyData
        self.keyID = keyID
    }

    public func sign(message: Data) throws -> Data {
        let key = SymmetricKey(data: keyData)
        let code = HMAC<SHA256>.authenticationCode(for: message, using: key)
        return Data(code)
    }

    public func verify(signature: Data, message: Data) -> Bool {
        let key = SymmetricKey(data: keyData)
        let expected = HMAC<SHA256>.authenticationCode(for: message, using: key)
        return Data(expected) == signature
    }
}

/// Append-only storage for signed audit log records.
///
/// Implementations enforce immutability by validating chain integrity before appending.
/// Records cannot be modified or deleted after creation.
public protocol ColonyImmutableToolAuditLogStore: Sendable {
    /// Appends a new signed record to the log.
    ///
    /// - Parameter record: The signed record to append. Must have correct sequence and previous hash.
    func append(_ record: ColonySignedToolAuditRecord) async throws
    /// Returns all records in the log in chronological order.
    func records() async throws -> [ColonySignedToolAuditRecord]
}

/// An in-memory implementation of the immutable audit log store.
///
/// Intended for short-lived processes or testing. Data is lost on process termination.
public actor ColonyInMemoryToolAuditLogStore: ColonyImmutableToolAuditLogStore {
    private var storage: [ColonySignedToolAuditRecord] = []

    public init() {}

    public func append(_ record: ColonySignedToolAuditRecord) async throws {
        let expectedSequence = (storage.last?.payload.sequence ?? 0) + 1
        guard record.payload.sequence == expectedSequence else {
            throw ToolAuditError.invalidSequence(expected: expectedSequence, actual: record.payload.sequence)
        }

        let expectedPreviousHash = storage.last?.entryHash
        guard record.payload.previousEntryHash == expectedPreviousHash else {
            throw ToolAuditError.previousHashMismatch(
                expected: expectedPreviousHash,
                actual: record.payload.previousEntryHash
            )
        }

        storage.append(record)
    }

    public func records() async throws -> [ColonySignedToolAuditRecord] {
        storage
    }
}

/// A file system backed implementation of the immutable audit log store.
///
/// Records are stored as individual JSON files named `entry-NNNNNNNNNNNN.json` in the
/// specified path prefix, enabling persistence across process restarts.
public actor ColonyFileSystemToolAuditLogStore: ColonyImmutableToolAuditLogStore {
    private let filesystem: any ColonyFileSystemBackend
    private let pathPrefix: ColonyVirtualPath

    /// Creates a file system backed audit log store.
    ///
    /// - Parameters:
    ///   - filesystem: The file system backend to use for storage.
    ///   - pathPrefix: Virtual path prefix for audit entry files (defaults to `.toolAuditRoot`).
    public init(
        filesystem: any ColonyFileSystemBackend,
        pathPrefix: ColonyVirtualPath = .toolAuditRoot
    ) {
        self.filesystem = filesystem
        self.pathPrefix = pathPrefix
    }

    public func append(_ record: ColonySignedToolAuditRecord) async throws {
        let existing = try await records()
        let expectedSequence = (existing.last?.payload.sequence ?? 0) + 1
        guard record.payload.sequence == expectedSequence else {
            throw ToolAuditError.invalidSequence(expected: expectedSequence, actual: record.payload.sequence)
        }

        let expectedPreviousHash = existing.last?.entryHash
        guard record.payload.previousEntryHash == expectedPreviousHash else {
            throw ToolAuditError.previousHashMismatch(
                expected: expectedPreviousHash,
                actual: record.payload.previousEntryHash
            )
        }

        let fileName = "entry-" + String(format: "%012d", record.payload.sequence) + ".json"
        let path = try ColonyVirtualPath(pathPrefix.rawValue + "/" + fileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        let content = String(decoding: data, as: UTF8.self)
        try await filesystem.write(at: path, content: content)
    }

    public func records() async throws -> [ColonySignedToolAuditRecord] {
        let infos: [ColonyFileInfo]
        do {
            infos = try await filesystem.list(at: pathPrefix)
        } catch FileSystemError.notFound {
            return []
        }

        let paths = infos
            .filter { $0.isDirectory == false && Self.isAuditEntryFile($0.path) }
            .map(\.path)
            .sorted { $0.rawValue.utf8.lexicographicallyPrecedes($1.rawValue.utf8) }

        var decoded: [ColonySignedToolAuditRecord] = []
        decoded.reserveCapacity(paths.count)

        let decoder = JSONDecoder()
        for path in paths {
            let raw = try await filesystem.read(at: path)
            let data = Data(raw.utf8)
            decoded.append(try decoder.decode(ColonySignedToolAuditRecord.self, from: data))
        }
        return decoded
    }

    private static func isAuditEntryFile(_ path: ColonyVirtualPath) -> Bool {
        guard let fileName = path.rawValue.split(separator: "/").last else { return false }
        return fileName.hasPrefix("entry-") && fileName.hasSuffix(".json")
    }
}

/// Records tool approval events to a cryptographically signed audit log.
///
/// Combines a signing mechanism with append-only storage to produce a tamper-evident
/// chain of audit records. Each record links to the previous entry via SHA-256 hash.
public actor ColonyToolAuditRecorder {
    private let store: any ColonyImmutableToolAuditLogStore
    private let signer: any ColonyToolAuditSigner

    /// Creates a new audit recorder with the specified store and signer.
    ///
    /// - Parameters:
    ///   - store: The append-only store for signed records.
    ///   - signer: The cryptographic signer for record integrity.
    public init(
        store: any ColonyImmutableToolAuditLogStore,
        signer: any ColonyToolAuditSigner
    ) {
        self.store = store
        self.signer = signer
    }

    @discardableResult
    public func record(event: ColonyToolAuditEvent) async throws -> ColonySignedToolAuditRecord {
        let existing = try await store.records()
        let previousHash = existing.last?.entryHash
        let payload = ColonyToolAuditRecordPayload(
            sequence: (existing.last?.payload.sequence ?? 0) + 1,
            previousEntryHash: previousHash,
            event: event
        )

        let chainData = try Self.chainData(payload: payload)
        let entryHash = Self.sha256Hex(chainData)
        let signature = try signer.sign(message: Data(entryHash.utf8))

        let record = ColonySignedToolAuditRecord(
            payload: payload,
            entryHash: entryHash,
            signatureBase64: signature.base64EncodedString(),
            signatureAlgorithm: signer.algorithm,
            signerKeyID: signer.keyID
        )
        try await store.append(record)
        return record
    }

    public func records() async throws -> [ColonySignedToolAuditRecord] {
        try await store.records()
    }

    public func verifyIntegrity() async throws -> Bool {
        let all = try await store.records()
        return try ColonyToolAuditVerifier.verify(records: all, signer: signer)
    }

    fileprivate static func chainData(payload: ColonyToolAuditRecordPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payloadData = try encoder.encode(payload)

        var data = Data()
        data.append(contentsOf: (payload.previousEntryHash ?? "GENESIS").utf8)
        data.append(0x0A)
        data.append(payloadData)
        return data
    }

    fileprivate static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Verifies the integrity and authenticity of a chain of signed audit records.
///
/// Validates:
/// - Sequence numbers are continuous starting at 1
/// - Each record's previous hash matches the prior record's entry hash
/// - Entry hashes match the computed SHA-256 of chained payload data
/// - Cryptographic signatures are valid for each record
public enum ColonyToolAuditVerifier {
    /// Verifies the complete audit chain.
    ///
    /// - Parameters:
    ///   - records: The ordered list of signed audit records to verify.
    ///   - signer: The signer to use for signature verification.
    /// - Returns: `true` if the chain is intact and all signatures are valid.
    public static func verify(
        records: [ColonySignedToolAuditRecord],
        signer: any ColonyToolAuditSigner
    ) throws -> Bool {
        var expectedSequence = 1
        var previousHash: String?

        for record in records {
            guard record.payload.sequence == expectedSequence else { return false }
            guard record.payload.previousEntryHash == previousHash else { return false }

            let chainData = try ColonyToolAuditRecorder.chainData(payload: record.payload)
            let expectedHash = ColonyToolAuditRecorder.sha256Hex(chainData)
            guard expectedHash == record.entryHash else { return false }

            guard let signature = Data(base64Encoded: record.signatureBase64) else { return false }
            guard signer.verify(signature: signature, message: Data(record.entryHash.utf8)) else { return false }

            previousHash = record.entryHash
            expectedSequence += 1
        }

        return true
    }
}
