import Foundation
import ColonyCore

// MARK: - Nested Domain Types

extension ControlPlane {
    public typealias RecordMetadata = [String: String]
}

// Control plane identity types are defined in ColonyCore/ColonyID.swift:
// ColonyProjectID, ColonyProductSessionID, ColonyProductSessionVersionID, ColonySessionShareToken

extension ControlPlane {
    public struct ProjectRecord: Codable, Equatable, Sendable {
        public let projectID: ColonyProjectID
        public var name: String
        public var metadata: ControlPlane.RecordMetadata
        public let createdAt: Date
        public var updatedAt: Date

        public init(
            projectID: ColonyProjectID,
            name: String,
            metadata: ControlPlane.RecordMetadata,
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

    public struct SessionVersionRecord: Codable, Equatable, Sendable {
        public let versionID: ColonyProductSessionVersionID
        public let createdAt: Date
        public var metadata: ControlPlane.RecordMetadata

        public init(
            versionID: ColonyProductSessionVersionID,
            createdAt: Date,
            metadata: ControlPlane.RecordMetadata
        ) {
            self.versionID = versionID
            self.createdAt = createdAt
            self.metadata = metadata
        }
    }

    public struct SessionShareRecord: Codable, Equatable, Sendable {
        public let token: ColonySessionShareToken
        public let createdAt: Date
        public var updatedAt: Date
        public var metadata: ControlPlane.RecordMetadata

        public init(
            token: ColonySessionShareToken,
            createdAt: Date,
            updatedAt: Date,
            metadata: ControlPlane.RecordMetadata
        ) {
            self.token = token
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.metadata = metadata
        }
    }

    public struct SessionRecord: Codable, Equatable, Sendable {
        public let sessionID: ColonyProductSessionID
        public let projectID: ColonyProjectID
        public var metadata: ControlPlane.RecordMetadata
        public let createdAt: Date
        public var updatedAt: Date
        public var versionLineage: [ControlPlane.SessionVersionRecord]
        public var activeVersionID: ColonyProductSessionVersionID
        public var shareRecord: ControlPlane.SessionShareRecord?

        public init(
            sessionID: ColonyProductSessionID,
            projectID: ColonyProjectID,
            metadata: ControlPlane.RecordMetadata,
            createdAt: Date,
            updatedAt: Date,
            versionLineage: [ControlPlane.SessionVersionRecord],
            activeVersionID: ColonyProductSessionVersionID,
            shareRecord: ControlPlane.SessionShareRecord? = nil
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

    public struct ProjectCreateInput: Sendable {
        public let projectID: ColonyProjectID?
        public let name: String
        public let metadata: ControlPlane.RecordMetadata
        public let createdAt: Date?

        public init(
            projectID: ColonyProjectID? = nil,
            name: String,
            metadata: ControlPlane.RecordMetadata = [:],
            createdAt: Date? = nil
        ) {
            self.projectID = projectID
            self.name = name
            self.metadata = metadata
            self.createdAt = createdAt
        }
    }

    public struct SessionCreateInput: Sendable {
        public let sessionID: ColonyProductSessionID?
        public let projectID: ColonyProjectID
        public let metadata: ControlPlane.RecordMetadata
        public let versionLineage: [ControlPlane.SessionVersionRecord]?
        public let activeVersionID: ColonyProductSessionVersionID?
        public let createdAt: Date?

        public init(
            sessionID: ColonyProductSessionID? = nil,
            projectID: ColonyProjectID,
            metadata: ControlPlane.RecordMetadata = [:],
            versionLineage: [ControlPlane.SessionVersionRecord]? = nil,
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

    public struct SessionForkInput: Sendable {
        public let sourceSessionID: ColonyProductSessionID
        public let newSessionID: ColonyProductSessionID?
        public let projectID: ColonyProjectID?
        public let metadata: ControlPlane.RecordMetadata?
        public let createdAt: Date?

        public init(
            sourceSessionID: ColonyProductSessionID,
            newSessionID: ColonyProductSessionID? = nil,
            projectID: ColonyProjectID? = nil,
            metadata: ControlPlane.RecordMetadata? = nil,
            createdAt: Date? = nil
        ) {
            self.sourceSessionID = sourceSessionID
            self.newSessionID = newSessionID
            self.projectID = projectID
            self.metadata = metadata
            self.createdAt = createdAt
        }
    }

    public struct SessionShareInput: Sendable {
        public let sessionID: ColonyProductSessionID
        public let metadata: ControlPlane.RecordMetadata
        public let sharedAt: Date?

        public init(
            sessionID: ColonyProductSessionID,
            metadata: ControlPlane.RecordMetadata = [:],
            sharedAt: Date? = nil
        ) {
            self.sessionID = sessionID
            self.metadata = metadata
            self.sharedAt = sharedAt
        }
    }

    public enum ProjectStoreError: Error, Sendable, Equatable {
        case duplicateProjectID(ColonyProjectID)
    }

    public enum SessionStoreError: Error, Sendable, Equatable {
        case duplicateSessionID(ColonyProductSessionID)
        case sessionNotFound(ColonyProductSessionID)
        case invalidVersionLineage
        case activeVersionMissing(ColonyProductSessionVersionID)
        case noPreviousVersion(ColonyProductSessionID)
    }
}

