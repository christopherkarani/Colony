import Foundation

public actor ColonySessionStore {
    private var records: [ColonyProductSessionID: ColonyProductSessionRecord] = [:]

    public init() {}

    public func createSession(_ input: ColonySessionCreateInput) throws -> ColonyProductSessionRecord {
        let sessionID = input.sessionID ?? ColonyProductSessionID(rawValue: "session:" + UUID().uuidString.lowercased())
        guard records[sessionID] == nil else {
            throw ColonySessionStoreError.duplicateSessionID(sessionID)
        }

        let createdAt = input.createdAt ?? Date()
        let versionLineage: [ColonyProductSessionVersionRecord]
        if let inputLineage = input.versionLineage {
            guard inputLineage.isEmpty == false else {
                throw ColonySessionStoreError.invalidVersionLineage
            }
            versionLineage = inputLineage
        } else {
            let versionID = ColonyProductSessionVersionID(rawValue: "version:" + UUID().uuidString.lowercased())
            versionLineage = [
                ColonyProductSessionVersionRecord(
                    versionID: versionID,
                    createdAt: createdAt,
                    metadata: input.metadata
                )
            ]
        }

        let activeVersionID = input.activeVersionID ?? versionLineage.last!.versionID
        guard versionLineage.contains(where: { $0.versionID == activeVersionID }) else {
            throw ColonySessionStoreError.activeVersionMissing(activeVersionID)
        }

        let record = ColonyProductSessionRecord(
            sessionID: sessionID,
            projectID: input.projectID,
            metadata: input.metadata,
            createdAt: createdAt,
            updatedAt: createdAt,
            versionLineage: versionLineage,
            activeVersionID: activeVersionID,
            shareRecord: nil
        )
        records[sessionID] = record
        return record
    }

    public func getSession(id: ColonyProductSessionID) -> ColonyProductSessionRecord? {
        records[id]
    }

    public func listSessions(projectID: ColonyProjectID? = nil) -> [ColonyProductSessionRecord] {
        let values = records.values.filter { record in
            guard let projectID else { return true }
            return record.projectID == projectID
        }
        return values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.sessionID.rawValue < rhs.sessionID.rawValue
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    public func deleteSession(id: ColonyProductSessionID) -> Bool {
        records.removeValue(forKey: id) != nil
    }

    public func forkSession(_ input: ColonySessionForkInput) throws -> ColonyProductSessionRecord {
        guard let source = records[input.sourceSessionID] else {
            throw ColonySessionStoreError.sessionNotFound(input.sourceSessionID)
        }

        let newSessionID = input.newSessionID ?? ColonyProductSessionID(rawValue: "session:" + UUID().uuidString.lowercased())
        guard records[newSessionID] == nil else {
            throw ColonySessionStoreError.duplicateSessionID(newSessionID)
        }

        let createdAt = input.createdAt ?? Date()
        let record = ColonyProductSessionRecord(
            sessionID: newSessionID,
            projectID: input.projectID ?? source.projectID,
            metadata: mergedMetadata(base: source.metadata, overrides: input.metadata),
            createdAt: createdAt,
            updatedAt: createdAt,
            versionLineage: source.versionLineage,
            activeVersionID: source.activeVersionID,
            shareRecord: nil
        )

        records[newSessionID] = record
        return record
    }

    public func revertSession(sessionID: ColonyProductSessionID) throws -> ColonyProductSessionRecord {
        guard var session = records[sessionID] else {
            throw ColonySessionStoreError.sessionNotFound(sessionID)
        }

        guard let activeIndex = session.versionLineage.firstIndex(where: { $0.versionID == session.activeVersionID }) else {
            throw ColonySessionStoreError.activeVersionMissing(session.activeVersionID)
        }
        guard activeIndex > 0 else {
            throw ColonySessionStoreError.noPreviousVersion(sessionID)
        }

        session.activeVersionID = session.versionLineage[activeIndex - 1].versionID
        session.updatedAt = Date()
        records[sessionID] = session
        return session
    }

    public func shareSession(_ input: ColonySessionShareInput) throws -> ColonyProductSessionShareRecord {
        guard var session = records[input.sessionID] else {
            throw ColonySessionStoreError.sessionNotFound(input.sessionID)
        }

        let timestamp = input.sharedAt ?? Date()
        let shareRecord: ColonyProductSessionShareRecord
        if var existing = session.shareRecord {
            existing.metadata = mergedMetadata(base: existing.metadata, overrides: input.metadata)
            existing.updatedAt = timestamp
            shareRecord = existing
        } else {
            shareRecord = ColonyProductSessionShareRecord(
                token: ColonySessionShareToken(rawValue: "share:" + input.sessionID.rawValue.lowercased()),
                createdAt: timestamp,
                updatedAt: timestamp,
                metadata: input.metadata
            )
        }

        session.shareRecord = shareRecord
        session.updatedAt = timestamp
        records[input.sessionID] = session
        return shareRecord
    }

    private func mergedMetadata(
        base: ColonyRecordMetadata,
        overrides: ColonyRecordMetadata?
    ) -> ColonyRecordMetadata {
        guard let overrides else {
            return base
        }

        var merged = base
        for (key, value) in overrides {
            merged[key] = value
        }
        return merged
    }
}
