import CryptoKit
import Foundation

// MARK: - Namespace

/// Namespace for tool audit trail types — an immutable, cryptographically-signed log of every tool call decision.
///
/// The audit log records every tool call with its risk level, the approval decision made
/// (auto-approved, user-approved, user-denied), and a reason. Each entry is signed using
/// HMAC-SHA256 and chained to the previous entry via SHA-256, creating an tamper-evident
/// chain that can be verified with `ColonyToolAudit.Recorder.verifyIntegrity()`.
///
/// ## Setup
///
/// ```swift
/// let signer = ColonyHMACSHA256ToolAuditSigner(keyData: secretKey, keyID: "prod-key")
/// let store = ColonyInMemoryToolAuditLogStore()
/// let recorder = ColonyToolAudit.Recorder(store: store, signer: signer)
///
/// var config = ColonyConfiguration(modelName: .claudeSonnet)
/// config.safety.toolAuditRecorder = recorder
/// ```
public enum ColonyToolAudit {}

// MARK: - ColonyToolAudit.DecisionKind

/// The category of approval decision recorded in an audit entry.
extension ColonyToolAudit {
    public enum DecisionKind: String, Codable, Sendable, Equatable {
        /// Tool required approval — human decision pending.
        case approvalRequired = "approval_required"
        /// Tool was automatically approved by policy without human input.
        case autoApproved = "auto_approved"
        /// Human explicitly approved this tool call.
        case userApproved = "user_approved"
        /// Human explicitly denied this tool call.
        case userDenied = "user_denied"
    }
}

// MARK: - ColonyToolAudit.Event

/// A single tool call decision event recorded in the audit trail.
extension ColonyToolAudit {
    public struct Event: Codable, Sendable, Equatable {
        /// Timestamp in nanoseconds since an arbitrary epoch.
        public var timestampNanoseconds: UInt64
        /// The thread in which this tool was invoked.
        public var threadID: String
        /// The task ID within the thread.
        public var taskID: String
        /// The unique ID of the tool call.
        public var toolCallID: ColonyToolCallID
        /// The name of the tool invoked.
        public var toolName: String
        /// The assessed risk level at the time of the call.
        public var riskLevel: ColonyTool.RiskLevel
        /// The approval decision that was made.
        public var decision: ColonyToolAudit.DecisionKind
        /// Why approval was required (if applicable).
        public var reason: ColonyToolApproval.RequirementReason?

        public init(
            timestampNanoseconds: UInt64,
            threadID: String,
            taskID: String,
            toolCallID: ColonyToolCallID,
            toolName: String,
            riskLevel: ColonyTool.RiskLevel,
            decision: ColonyToolAudit.DecisionKind,
            reason: ColonyToolApproval.RequirementReason? = nil
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
}

// MARK: - ColonyToolAudit.RecordPayload

/// The unsigned payload of an audit log entry, containing the sequence number and event.
extension ColonyToolAudit {
    public struct RecordPayload: Codable, Sendable, Equatable {
        /// Monotonically increasing sequence number starting at 1.
        public var sequence: Int
        /// SHA-256 hash of the previous entry in the chain (nil for the first entry).
        public var previousEntryHash: String?
        /// The tool audit event.
        public var event: ColonyToolAudit.Event

        public init(sequence: Int, previousEntryHash: String?, event: ColonyToolAudit.Event) {
            self.sequence = sequence
            self.previousEntryHash = previousEntryHash
            self.event = event
        }
    }
}

// MARK: - ColonyToolAudit.SignedRecord

/// A complete audit log entry with cryptographic signature for tamper evidence.
extension ColonyToolAudit {
    public struct SignedRecord: Codable, Sendable, Equatable {
        /// The sequenced event payload with previous-hash chain.
        public var payload: ColonyToolAudit.RecordPayload
        /// SHA-256 hash of this entry's payload for chain verification.
        public var entryHash: String
        /// The cryptographic signature of `entryHash` in base64.
        public var signatureBase64: String
        /// The algorithm used for the signature (e.g., "hmac-sha256").
        public var signatureAlgorithm: String
        /// The key identifier used to sign this entry.
        public var signerKeyID: String

        public init(
            payload: ColonyToolAudit.RecordPayload,
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
}

// MARK: - ColonyToolAudit.AuditError

/// Errors that can occur when appending or verifying audit log entries.
extension ColonyToolAudit {
    public enum AuditError: Error, Sendable, Equatable {
        /// The appended entry's sequence number does not follow the last entry.
        case invalidSequence(expected: Int, actual: Int)
        /// The appended entry's previous-hash does not match the last entry's hash.
        case previousHashMismatch(expected: String?, actual: String?)
    }
}

// MARK: - Protocols (top-level)

/// Signs and verifies audit log entries using a symmetric HMAC-SHA256 scheme.
public protocol ColonyToolAuditSigner: Sendable {
    /// The identifier for the signing key.
    var keyID: String { get }
    /// The signing algorithm identifier (e.g., "hmac-sha256").
    var algorithm: String { get }
    /// Sign a message and return the raw signature bytes.
    func sign(message: Data) throws -> Data
    /// Verify a signature against a message — returns true if valid.
    func verify(signature: Data, message: Data) -> Bool
}

package struct ColonyHMACSHA256ToolAuditSigner: ColonyToolAuditSigner {
    package let keyID: String
    package let algorithm: String = "hmac-sha256"
    private let keyData: Data

    package init(keyData: Data, keyID: String = "default") {
        self.keyData = keyData
        self.keyID = keyID
    }

    package func sign(message: Data) throws -> Data {
        let key = SymmetricKey(data: keyData)
        let code = HMAC<SHA256>.authenticationCode(for: message, using: key)
        return Data(code)
    }

    package func verify(signature: Data, message: Data) -> Bool {
        let key = SymmetricKey(data: keyData)
        let expected = HMAC<SHA256>.authenticationCode(for: message, using: key)
        return Data(expected) == signature
    }
}

/// An append-only store for signed audit records.
///
/// Implementations must enforce immutability — records once appended cannot be modified
/// or deleted, and sequence numbers must be monotonically increasing.
public protocol ColonyImmutableToolAuditLogStore: Sendable {
    /// Append a signed record to the log. Must enforce sequence and hash chain integrity.
    func append(_ record: ColonyToolAudit.SignedRecord) async throws
    /// Return all records in the log in order.
    func records() async throws -> [ColonyToolAudit.SignedRecord]
}

package actor ColonyInMemoryToolAuditLogStore: ColonyImmutableToolAuditLogStore {
    private var storage: [ColonyToolAudit.SignedRecord] = []

    package init() {}

    package func append(_ record: ColonyToolAudit.SignedRecord) async throws {
        let expectedSequence = (storage.last?.payload.sequence ?? 0) + 1
        guard record.payload.sequence == expectedSequence else {
            throw ColonyToolAudit.AuditError.invalidSequence(expected: expectedSequence, actual: record.payload.sequence)
        }

        let expectedPreviousHash = storage.last?.entryHash
        guard record.payload.previousEntryHash == expectedPreviousHash else {
            throw ColonyToolAudit.AuditError.previousHashMismatch(
                expected: expectedPreviousHash,
                actual: record.payload.previousEntryHash
            )
        }

        storage.append(record)
    }

    package func records() async throws -> [ColonyToolAudit.SignedRecord] {
        storage
    }
}

// MARK: - ColonyToolAudit.FileSystemLogStore

/// A file-system-backed audit log store, suitable for durable persistent audit trails.
///
/// Stores each signed record as a JSON file named `entry-<sequence>.json` within the
/// configured virtual path. Files are written atomically.
extension ColonyToolAudit {
    public actor FileSystemLogStore: ColonyImmutableToolAuditLogStore {
        private let filesystem: any ColonyFileSystemBackend
        private let pathPrefix: ColonyFileSystem.VirtualPath

        public init(
            filesystem: any ColonyFileSystemBackend,
            pathPrefix: ColonyFileSystem.VirtualPath = try! ColonyFileSystem.VirtualPath("/audit/tool_decisions")
        ) {
            self.filesystem = filesystem
            self.pathPrefix = pathPrefix
        }

        public func append(_ record: ColonyToolAudit.SignedRecord) async throws {
            let existing = try await records()
            let expectedSequence = (existing.last?.payload.sequence ?? 0) + 1
            guard record.payload.sequence == expectedSequence else {
                throw ColonyToolAudit.AuditError.invalidSequence(expected: expectedSequence, actual: record.payload.sequence)
            }

            let expectedPreviousHash = existing.last?.entryHash
            guard record.payload.previousEntryHash == expectedPreviousHash else {
                throw ColonyToolAudit.AuditError.previousHashMismatch(
                    expected: expectedPreviousHash,
                    actual: record.payload.previousEntryHash
                )
            }

            let fileName = "entry-" + String(format: "%012d", record.payload.sequence) + ".json"
            let path = try ColonyFileSystem.VirtualPath(pathPrefix.rawValue + "/" + fileName)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(record)
            let content = String(decoding: data, as: UTF8.self)
            try await filesystem.write(at: path, content: content)
        }

        public func records() async throws -> [ColonyToolAudit.SignedRecord] {
            let infos: [ColonyFileSystem.FileInfo]
            do {
                infos = try await filesystem.list(at: pathPrefix)
            } catch ColonyFileSystem.Error.notFound {
                return []
            }

            let paths = infos
                .filter { $0.isDirectory == false && Self.isAuditEntryFile($0.path) }
                .map(\.path)
                .sorted { $0.rawValue.utf8.lexicographicallyPrecedes($1.rawValue.utf8) }

            var decoded: [ColonyToolAudit.SignedRecord] = []
            decoded.reserveCapacity(paths.count)

            let decoder = JSONDecoder()
            for path in paths {
                let raw = try await filesystem.read(at: path)
                let data = Data(raw.utf8)
                decoded.append(try decoder.decode(ColonyToolAudit.SignedRecord.self, from: data))
            }
            return decoded
        }

        private static func isAuditEntryFile(_ path: ColonyFileSystem.VirtualPath) -> Bool {
            guard let fileName = path.rawValue.split(separator: "/").last else { return false }
            return fileName.hasPrefix("entry-") && fileName.hasSuffix(".json")
        }
    }
}

// MARK: - ColonyToolAudit.Recorder

/// The main entry point for recording tool audit events.
///
/// `Recorder` constructs a `SignedRecord` by:
/// 1. Assigning the next sequence number and previous-hash chain link
/// 2. Computing a SHA-256 hash of the payload
/// 3. Signing the hash with the configured `ColonyToolAuditSigner`
/// 4. Persisting to the configured `ColonyImmutableToolAuditLogStore`
///
/// Call `verifyIntegrity()` at any time to validate the entire chain.
extension ColonyToolAudit {
    public actor Recorder {
        private let store: any ColonyImmutableToolAuditLogStore
        private let signer: any ColonyToolAuditSigner

        public init(
            store: any ColonyImmutableToolAuditLogStore,
            signer: any ColonyToolAuditSigner
        ) {
            self.store = store
            self.signer = signer
        }

        @discardableResult
        public func record(event: ColonyToolAudit.Event) async throws -> ColonyToolAudit.SignedRecord {
            let existing = try await store.records()
            let previousHash = existing.last?.entryHash
            let payload = ColonyToolAudit.RecordPayload(
                sequence: (existing.last?.payload.sequence ?? 0) + 1,
                previousEntryHash: previousHash,
                event: event
            )

            let chainData = try Self.chainData(payload: payload)
            let entryHash = Self.sha256Hex(chainData)
            let signature = try signer.sign(message: Data(entryHash.utf8))

            let record = ColonyToolAudit.SignedRecord(
                payload: payload,
                entryHash: entryHash,
                signatureBase64: signature.base64EncodedString(),
                signatureAlgorithm: signer.algorithm,
                signerKeyID: signer.keyID
            )
            try await store.append(record)
            return record
        }

        public func records() async throws -> [ColonyToolAudit.SignedRecord] {
            try await store.records()
        }

        public func verifyIntegrity() async throws -> Bool {
            let all = try await store.records()
            return try ColonyToolAuditVerifier.verify(records: all, signer: signer)
        }

        fileprivate static func chainData(payload: ColonyToolAudit.RecordPayload) throws -> Data {
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
}

// MARK: - ColonyToolAuditVerifier (package, kept in extension)

package enum ColonyToolAuditVerifier {
    package static func verify(
        records: [ColonyToolAudit.SignedRecord],
        signer: any ColonyToolAuditSigner
    ) throws -> Bool {
        var expectedSequence = 1
        var previousHash: String?

        for record in records {
            guard record.payload.sequence == expectedSequence else { return false }
            guard record.payload.previousEntryHash == previousHash else { return false }

            let chainData = try ColonyToolAudit.Recorder.chainData(payload: record.payload)
            let expectedHash = ColonyToolAudit.Recorder.sha256Hex(chainData)
            guard expectedHash == record.entryHash else { return false }

            guard let signature = Data(base64Encoded: record.signatureBase64) else { return false }
            guard signer.verify(signature: signature, message: Data(record.entryHash.utf8)) else { return false }

            previousHash = record.entryHash
            expectedSequence += 1
        }

        return true
    }
}

