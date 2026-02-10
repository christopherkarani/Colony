import Foundation

public protocol ColonyProjectStore: Sendable {
    func createProject(_ input: ColonyProjectCreateInput) async throws -> ColonyProjectRecord
    func getProject(id: ColonyProjectID) async -> ColonyProjectRecord?
    func listProjects() async -> [ColonyProjectRecord]
    func deleteProject(id: ColonyProjectID) async -> Bool
}

public actor InMemoryColonyProjectStore: ColonyProjectStore {
    private var records: [ColonyProjectID: ColonyProjectRecord] = [:]

    public init() {}

    public func createProject(_ input: ColonyProjectCreateInput) throws -> ColonyProjectRecord {
        let projectID = input.projectID ?? ColonyProjectID(rawValue: "project:" + UUID().uuidString.lowercased())
        guard records[projectID] == nil else {
            throw ColonyProjectStoreError.duplicateProjectID(projectID)
        }

        let now = input.createdAt ?? Date()
        let record = ColonyProjectRecord(
            projectID: projectID,
            name: input.name,
            metadata: input.metadata,
            createdAt: now,
            updatedAt: now
        )
        records[projectID] = record
        return record
    }

    public func getProject(id: ColonyProjectID) -> ColonyProjectRecord? {
        records[id]
    }

    public func listProjects() -> [ColonyProjectRecord] {
        records.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.projectID.rawValue < rhs.projectID.rawValue
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    public func deleteProject(id: ColonyProjectID) -> Bool {
        records.removeValue(forKey: id) != nil
    }
}
