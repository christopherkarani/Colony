import Foundation
import ColonyCore

extension ControlPlane {
    package actor SessionStore {
        private var records: [ColonyProductSessionID: ControlPlane.SessionRecord] = [:]

        package init() {}

        package func createSession(_ input: ControlPlane.SessionCreateInput) throws -> ControlPlane.SessionRecord {
            let sessionID = input.sessionID ?? ColonyProductSessionID(rawValue: "session:" + UUID().uuidString.lowercased())
            guard records[sessionID] == nil else {
                throw ControlPlane.SessionStoreError.duplicateSessionID(sessionID)
            }

            let createdAt = input.createdAt ?? Date()
            let versionLineage: [ControlPlane.SessionVersionRecord]
            if let inputLineage = input.versionLineage {
                guard inputLineage.isEmpty == false else {
                    throw ControlPlane.SessionStoreError.invalidVersionLineage
                }
                versionLineage = inputLineage
            } else {
                let versionID = ColonyProductSessionVersionID(rawValue: "version:" + UUID().uuidString.lowercased())
                versionLineage = [
                    ControlPlane.SessionVersionRecord(
                        versionID: versionID,
                        createdAt: createdAt,
                        metadata: input.metadata
                    )
                ]
            }

            let activeVersionID = input.activeVersionID ?? versionLineage.last!.versionID
            guard versionLineage.contains(where: { $0.versionID == activeVersionID }) else {
                throw ControlPlane.SessionStoreError.activeVersionMissing(activeVersionID)
            }

            let record = ControlPlane.SessionRecord(
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

        package func getSession(id: ColonyProductSessionID) -> ControlPlane.SessionRecord? {
            records[id]
        }

        package func listSessions(projectID: ColonyProjectID? = nil) -> [ControlPlane.SessionRecord] {
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

        package func deleteSession(id: ColonyProductSessionID) -> Bool {
            records.removeValue(forKey: id) != nil
        }

        package func forkSession(_ input: ControlPlane.SessionForkInput) throws -> ControlPlane.SessionRecord {
            guard let source = records[input.sourceSessionID] else {
                throw ControlPlane.SessionStoreError.sessionNotFound(input.sourceSessionID)
            }

            let newSessionID = input.newSessionID ?? ColonyProductSessionID(rawValue: "session:" + UUID().uuidString.lowercased())
            guard records[newSessionID] == nil else {
                throw ControlPlane.SessionStoreError.duplicateSessionID(newSessionID)
            }

            let createdAt = input.createdAt ?? Date()
            let record = ControlPlane.SessionRecord(
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

        package func revertSession(sessionID: ColonyProductSessionID) throws -> ControlPlane.SessionRecord {
            guard var session = records[sessionID] else {
                throw ControlPlane.SessionStoreError.sessionNotFound(sessionID)
            }

            guard let activeIndex = session.versionLineage.firstIndex(where: { $0.versionID == session.activeVersionID }) else {
                throw ControlPlane.SessionStoreError.activeVersionMissing(session.activeVersionID)
            }
            guard activeIndex > 0 else {
                throw ControlPlane.SessionStoreError.noPreviousVersion(sessionID)
            }

            session.activeVersionID = session.versionLineage[activeIndex - 1].versionID
            session.updatedAt = Date()
            records[sessionID] = session
            return session
        }

        package func shareSession(_ input: ControlPlane.SessionShareInput) throws -> ControlPlane.SessionShareRecord {
            guard var session = records[input.sessionID] else {
                throw ControlPlane.SessionStoreError.sessionNotFound(input.sessionID)
            }

            let timestamp = input.sharedAt ?? Date()
            let shareRecord: ControlPlane.SessionShareRecord
            if var existing = session.shareRecord {
                existing.metadata = mergedMetadata(base: existing.metadata, overrides: input.metadata)
                existing.updatedAt = timestamp
                shareRecord = existing
            } else {
                shareRecord = ControlPlane.SessionShareRecord(
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
            base: ControlPlane.RecordMetadata,
            overrides: ControlPlane.RecordMetadata?
        ) -> ControlPlane.RecordMetadata {
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
}

