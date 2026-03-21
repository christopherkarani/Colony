import Foundation
import ColonyCore

public protocol ControlPlaneProjectStore: Sendable {
    func createProject(_ input: ControlPlane.ProjectCreateInput) async throws -> ControlPlane.ProjectRecord
    func getProject(id: ColonyProjectID) async -> ControlPlane.ProjectRecord?
    func listProjects() async -> [ControlPlane.ProjectRecord]
    func deleteProject(id: ColonyProjectID) async -> Bool
}

package actor InMemoryControlPlaneProjectStore: ControlPlaneProjectStore {
    private var records: [ColonyProjectID: ControlPlane.ProjectRecord] = [:]

    package init() {}

    package func createProject(_ input: ControlPlane.ProjectCreateInput) throws -> ControlPlane.ProjectRecord {
        let projectID = input.projectID ?? ColonyProjectID(rawValue: "project:" + UUID().uuidString.lowercased())
        guard records[projectID] == nil else {
            throw ControlPlane.ProjectStoreError.duplicateProjectID(projectID)
        }

        let now = input.createdAt ?? Date()
        let record = ControlPlane.ProjectRecord(
            projectID: projectID,
            name: input.name,
            metadata: input.metadata,
            createdAt: now,
            updatedAt: now
        )
        records[projectID] = record
        return record
    }

    package func getProject(id: ColonyProjectID) -> ControlPlane.ProjectRecord? {
        records[id]
    }

    package func listProjects() -> [ControlPlane.ProjectRecord] {
        records.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.projectID.rawValue < rhs.projectID.rawValue
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    package func deleteProject(id: ColonyProjectID) -> Bool {
        records.removeValue(forKey: id) != nil
    }
}

