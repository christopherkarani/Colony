import CryptoKit
import Foundation

public enum ColonyToolAuditDecisionKind: String, Codable, Sendable, Equatable {
    case approvalRequired = "approval_required"
    case autoApproved = "auto_approved"
    case userApproved = "user_approved"
    case userDenied = "user_denied"
}

public struct ColonyToolAuditEvent: Codable, Sendable, Equatable {
    public var timestampNanoseconds: UInt64
    public var threadID: String
    public var taskID: String
    public var toolCallID: String
    public var toolName: String
    public var riskLevel: ColonyToolRiskLevel
    public var decision: ColonyToolAuditDecisionKind
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

public struct ColonyToolAuditRecordPayload: Codable, Sendable, Equatable {
    public var sequence: Int
    public var previousEntryHash: String?
    public var event: ColonyToolAuditEvent

    public init(sequence: Int, previousEntryHash: String?, event: ColonyToolAuditEvent) {
        self.sequence = sequence
        self.previousEntryHash = previousEntryHash
        self.event = event
    }
}

public struct ColonySignedToolAuditRecord: Codable, Sendable, Equatable {
    public var payload: ColonyToolAuditRecordPayload
    public var entryHash: String
    public var signatureBase64: String
    public var signatureAlgorithm: String
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

public enum ColonyToolAuditError: Error, Sendable, Equatable {
    case invalidSequence(expected: Int, actual: Int)
    case previousHashMismatch(expected: String?, actual: String?)
}

public protocol ColonyToolAuditSigner: Sendable {
    var keyID: String { get }
    var algorithm: String { get }
    func sign(message: Data) throws -> Data
    func verify(signature: Data, message: Data) -> Bool
}

public struct ColonyHMACSHA256ToolAuditSigner: ColonyToolAuditSigner {
    public let keyID: String
    public let algorithm: String = "hmac-sha256"
    private let keyData: Data

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

public protocol ColonyImmutableToolAuditLogStore: Sendable {
    func append(_ record: ColonySignedToolAuditRecord) async throws
    func records() async throws -> [ColonySignedToolAuditRecord]
}

public actor ColonyInMemoryToolAuditLogStore: ColonyImmutableToolAuditLogStore {
    private var storage: [ColonySignedToolAuditRecord] = []

    public init() {}

    public func append(_ record: ColonySignedToolAuditRecord) async throws {
        let expectedSequence = (storage.last?.payload.sequence ?? 0) + 1
        guard record.payload.sequence == expectedSequence else {
            throw ColonyToolAuditError.invalidSequence(expected: expectedSequence, actual: record.payload.sequence)
        }

        let expectedPreviousHash = storage.last?.entryHash
        guard record.payload.previousEntryHash == expectedPreviousHash else {
            throw ColonyToolAuditError.previousHashMismatch(
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

public actor ColonyFileSystemToolAuditLogStore: ColonyImmutableToolAuditLogStore {
    private let filesystem: any ColonyFileSystemBackend
    private let pathPrefix: ColonyVirtualPath

    public init(
        filesystem: any ColonyFileSystemBackend,
        pathPrefix: ColonyVirtualPath = try! ColonyVirtualPath("/audit/tool_decisions")
    ) {
        self.filesystem = filesystem
        self.pathPrefix = pathPrefix
    }

    public func append(_ record: ColonySignedToolAuditRecord) async throws {
        let existing = try await records()
        let expectedSequence = (existing.last?.payload.sequence ?? 0) + 1
        guard record.payload.sequence == expectedSequence else {
            throw ColonyToolAuditError.invalidSequence(expected: expectedSequence, actual: record.payload.sequence)
        }

        let expectedPreviousHash = existing.last?.entryHash
        guard record.payload.previousEntryHash == expectedPreviousHash else {
            throw ColonyToolAuditError.previousHashMismatch(
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
        } catch ColonyFileSystemError.notFound {
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

public actor ColonyToolAuditRecorder {
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

public enum ColonyToolAuditVerifier {
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
