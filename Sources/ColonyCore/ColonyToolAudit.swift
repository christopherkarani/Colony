import CryptoKit
import Foundation

// MARK: - Namespace

public enum ColonyToolAudit {}

// MARK: - ColonyToolAudit.DecisionKind

extension ColonyToolAudit {
    public enum DecisionKind: String, Codable, Sendable, Equatable {
        case approvalRequired = "approval_required"
        case autoApproved = "auto_approved"
        case userApproved = "user_approved"
        case userDenied = "user_denied"
    }
}

// MARK: - ColonyToolAudit.Event

extension ColonyToolAudit {
    public struct Event: Codable, Sendable, Equatable {
        public var timestampNanoseconds: UInt64
        public var threadID: String
        public var taskID: String
        public var toolCallID: ColonyToolCallID
        public var toolName: String
        public var riskLevel: ColonyTool.RiskLevel
        public var decision: ColonyToolAudit.DecisionKind
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

// MARK: - ColonyToolAudit.RecordPayload (package)

extension ColonyToolAudit {
    public struct RecordPayload: Codable, Sendable, Equatable {
        public var sequence: Int
        public var previousEntryHash: String?
        public var event: ColonyToolAudit.Event

        public init(sequence: Int, previousEntryHash: String?, event: ColonyToolAudit.Event) {
            self.sequence = sequence
            self.previousEntryHash = previousEntryHash
            self.event = event
        }
    }
}

// MARK: - ColonyToolAudit.SignedRecord

extension ColonyToolAudit {
    public struct SignedRecord: Codable, Sendable, Equatable {
        public var payload: ColonyToolAudit.RecordPayload
        public var entryHash: String
        public var signatureBase64: String
        public var signatureAlgorithm: String
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

extension ColonyToolAudit {
    public enum AuditError: Error, Sendable, Equatable {
        case invalidSequence(expected: Int, actual: Int)
        case previousHashMismatch(expected: String?, actual: String?)
    }
}

// MARK: - Protocols (top-level)

public protocol ColonyToolAuditSigner: Sendable {
    var keyID: String { get }
    var algorithm: String { get }
    func sign(message: Data) throws -> Data
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

public protocol ColonyImmutableToolAuditLogStore: Sendable {
    func append(_ record: ColonyToolAudit.SignedRecord) async throws
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

