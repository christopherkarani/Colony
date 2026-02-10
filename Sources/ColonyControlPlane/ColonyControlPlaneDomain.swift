import Foundation

public typealias ColonyRecordMetadata = [String: String]

public struct ColonyProjectID: Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct ColonyProductSessionID: Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct ColonyProductSessionVersionID: Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct ColonySessionShareToken: Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct ColonyProjectRecord: Codable, Equatable, Sendable {
    public let projectID: ColonyProjectID
    public var name: String
    public var metadata: ColonyRecordMetadata
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        projectID: ColonyProjectID,
        name: String,
        metadata: ColonyRecordMetadata,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.projectID = projectID
        self.name = name
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ColonyProductSessionVersionRecord: Codable, Equatable, Sendable {
    public let versionID: ColonyProductSessionVersionID
    public let createdAt: Date
    public var metadata: ColonyRecordMetadata

    public init(
        versionID: ColonyProductSessionVersionID,
        createdAt: Date,
        metadata: ColonyRecordMetadata
    ) {
        self.versionID = versionID
        self.createdAt = createdAt
        self.metadata = metadata
    }
}

public struct ColonyProductSessionShareRecord: Codable, Equatable, Sendable {
    public let token: ColonySessionShareToken
    public let createdAt: Date
    public var updatedAt: Date
    public var metadata: ColonyRecordMetadata

    public init(
        token: ColonySessionShareToken,
        createdAt: Date,
        updatedAt: Date,
        metadata: ColonyRecordMetadata
    ) {
        self.token = token
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
    }
}

public struct ColonyProductSessionRecord: Codable, Equatable, Sendable {
    public let sessionID: ColonyProductSessionID
    public let projectID: ColonyProjectID
    public var metadata: ColonyRecordMetadata
    public let createdAt: Date
    public var updatedAt: Date
    public var versionLineage: [ColonyProductSessionVersionRecord]
    public var activeVersionID: ColonyProductSessionVersionID
    public var shareRecord: ColonyProductSessionShareRecord?

    public init(
        sessionID: ColonyProductSessionID,
        projectID: ColonyProjectID,
        metadata: ColonyRecordMetadata,
        createdAt: Date,
        updatedAt: Date,
        versionLineage: [ColonyProductSessionVersionRecord],
        activeVersionID: ColonyProductSessionVersionID,
        shareRecord: ColonyProductSessionShareRecord? = nil
    ) {
        self.sessionID = sessionID
        self.projectID = projectID
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.versionLineage = versionLineage
        self.activeVersionID = activeVersionID
        self.shareRecord = shareRecord
    }
}

public struct ColonyProjectCreateInput: Sendable {
    public let projectID: ColonyProjectID?
    public let name: String
    public let metadata: ColonyRecordMetadata
    public let createdAt: Date?

    public init(
        projectID: ColonyProjectID? = nil,
        name: String,
        metadata: ColonyRecordMetadata = [:],
        createdAt: Date? = nil
    ) {
        self.projectID = projectID
        self.name = name
        self.metadata = metadata
        self.createdAt = createdAt
    }
}

public struct ColonySessionCreateInput: Sendable {
    public let sessionID: ColonyProductSessionID?
    public let projectID: ColonyProjectID
    public let metadata: ColonyRecordMetadata
    public let versionLineage: [ColonyProductSessionVersionRecord]?
    public let activeVersionID: ColonyProductSessionVersionID?
    public let createdAt: Date?

    public init(
        sessionID: ColonyProductSessionID? = nil,
        projectID: ColonyProjectID,
        metadata: ColonyRecordMetadata = [:],
        versionLineage: [ColonyProductSessionVersionRecord]? = nil,
        activeVersionID: ColonyProductSessionVersionID? = nil,
        createdAt: Date? = nil
    ) {
        self.sessionID = sessionID
        self.projectID = projectID
        self.metadata = metadata
        self.versionLineage = versionLineage
        self.activeVersionID = activeVersionID
        self.createdAt = createdAt
    }
}

public struct ColonySessionForkInput: Sendable {
    public let sourceSessionID: ColonyProductSessionID
    public let newSessionID: ColonyProductSessionID?
    public let projectID: ColonyProjectID?
    public let metadata: ColonyRecordMetadata?
    public let createdAt: Date?

    public init(
        sourceSessionID: ColonyProductSessionID,
        newSessionID: ColonyProductSessionID? = nil,
        projectID: ColonyProjectID? = nil,
        metadata: ColonyRecordMetadata? = nil,
        createdAt: Date? = nil
    ) {
        self.sourceSessionID = sourceSessionID
        self.newSessionID = newSessionID
        self.projectID = projectID
        self.metadata = metadata
        self.createdAt = createdAt
    }
}

public struct ColonySessionShareInput: Sendable {
    public let sessionID: ColonyProductSessionID
    public let metadata: ColonyRecordMetadata
    public let sharedAt: Date?

    public init(
        sessionID: ColonyProductSessionID,
        metadata: ColonyRecordMetadata = [:],
        sharedAt: Date? = nil
    ) {
        self.sessionID = sessionID
        self.metadata = metadata
        self.sharedAt = sharedAt
    }
}

public enum ColonyProjectStoreError: Error, Sendable, Equatable {
    case duplicateProjectID(ColonyProjectID)
}

public enum ColonySessionStoreError: Error, Sendable, Equatable {
    case duplicateSessionID(ColonyProductSessionID)
    case sessionNotFound(ColonyProductSessionID)
    case invalidVersionLineage
    case activeVersionMissing(ColonyProductSessionVersionID)
    case noPreviousVersion(ColonyProductSessionID)
}
