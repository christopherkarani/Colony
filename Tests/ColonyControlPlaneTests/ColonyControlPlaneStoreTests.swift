import Foundation
import Testing
@testable import ColonyControlPlane

@Test("Project store supports deterministic CRUD semantics")
func projectStoreCRUD() async throws {
    let store = InMemoryColonyProjectStore()
    let projectID = ColonyProjectID(rawValue: "project:alpha")
    let createdAt = Date(timeIntervalSince1970: 1_000)

    let created = try await store.createProject(
        ColonyProjectCreateInput(
            projectID: projectID,
            name: "Alpha",
            metadata: ["owner": "platform"],
            createdAt: createdAt
        )
    )

    #expect(created.projectID == projectID)
    #expect(created.createdAt == createdAt)
    #expect(created.updatedAt == createdAt)
    #expect(created.metadata["owner"] == "platform")

    let fetched = await store.getProject(id: projectID)
    #expect(fetched == created)

    let listed = await store.listProjects()
    #expect(listed.count == 1)
    #expect(listed.first == created)

    let deleted = await store.deleteProject(id: projectID)
    #expect(deleted)
    #expect(await store.getProject(id: projectID) == nil)
}

@Test("Session store supports CRUD, fork, revert, and stable share token behavior")
func sessionStoreOperations() async throws {
    let store = ColonySessionStore()
    let sourceProjectID = ColonyProjectID(rawValue: "project:alpha")
    let targetProjectID = ColonyProjectID(rawValue: "project:beta")
    let sourceSessionID = ColonyProductSessionID(rawValue: "session:root")
    let forkedSessionID = ColonyProductSessionID(rawValue: "session:fork")
    let v1 = ColonyProductSessionVersionRecord(
        versionID: ColonyProductSessionVersionID(rawValue: "version:1"),
        createdAt: Date(timeIntervalSince1970: 10),
        metadata: ["checkpoint": "baseline"]
    )
    let v2 = ColonyProductSessionVersionRecord(
        versionID: ColonyProductSessionVersionID(rawValue: "version:2"),
        createdAt: Date(timeIntervalSince1970: 20),
        metadata: ["checkpoint": "refined"]
    )

    let created = try await store.createSession(
        ColonySessionCreateInput(
            sessionID: sourceSessionID,
            projectID: sourceProjectID,
            metadata: ["name": "Root Session"],
            versionLineage: [v1, v2],
            activeVersionID: v2.versionID,
            createdAt: Date(timeIntervalSince1970: 30)
        )
    )
    #expect(created.activeVersionID == v2.versionID)

    let listed = await store.listSessions(projectID: sourceProjectID)
    #expect(listed.count == 1)
    #expect(listed.first?.sessionID == sourceSessionID)

    let reverted = try await store.revertSession(sessionID: sourceSessionID)
    #expect(reverted.activeVersionID == v1.versionID)

    let firstShare = try await store.shareSession(
        ColonySessionShareInput(
            sessionID: sourceSessionID,
            metadata: ["scope": "read-only"],
            sharedAt: Date(timeIntervalSince1970: 40)
        )
    )
    let secondShare = try await store.shareSession(
        ColonySessionShareInput(
            sessionID: sourceSessionID,
            metadata: ["audience": "qa"],
            sharedAt: Date(timeIntervalSince1970: 50)
        )
    )

    #expect(firstShare.token == secondShare.token)
    #expect(secondShare.metadata["scope"] == "read-only")
    #expect(secondShare.metadata["audience"] == "qa")

    let forked = try await store.forkSession(
        ColonySessionForkInput(
            sourceSessionID: sourceSessionID,
            newSessionID: forkedSessionID,
            projectID: targetProjectID,
            metadata: ["branch": "experiment"],
            createdAt: Date(timeIntervalSince1970: 60)
        )
    )

    #expect(forked.sessionID == forkedSessionID)
    #expect(forked.projectID == targetProjectID)
    #expect(forked.metadata["name"] == "Root Session")
    #expect(forked.metadata["branch"] == "experiment")
    #expect(forked.versionLineage == reverted.versionLineage)
    #expect(forked.activeVersionID == reverted.activeVersionID)
    #expect(forked.shareRecord == nil)

    let deleted = await store.deleteSession(id: sourceSessionID)
    #expect(deleted)
    #expect(await store.getSession(id: sourceSessionID) == nil)
}

@Test("Session revert fails when there is no previous saved version")
func sessionRevertNoPreviousVersion() async throws {
    let store = ColonySessionStore()
    let sessionID = ColonyProductSessionID(rawValue: "session:single")
    _ = try await store.createSession(
        ColonySessionCreateInput(
            sessionID: sessionID,
            projectID: ColonyProjectID(rawValue: "project:solo"),
            metadata: [:],
            versionLineage: [
                ColonyProductSessionVersionRecord(
                    versionID: ColonyProductSessionVersionID(rawValue: "version:only"),
                    createdAt: Date(timeIntervalSince1970: 1),
                    metadata: [:]
                )
            ],
            activeVersionID: ColonyProductSessionVersionID(rawValue: "version:only"),
            createdAt: Date(timeIntervalSince1970: 1)
        )
    )

    await #expect(throws: ColonySessionStoreError.noPreviousVersion(sessionID)) {
        _ = try await store.revertSession(sessionID: sessionID)
    }
}

@Test("Control-plane service methods map to project/session operations")
func controlPlaneServiceOperations() async throws {
    let service = ColonyControlPlaneService(
        projectStore: InMemoryColonyProjectStore(),
        sessionStore: ColonySessionStore()
    )
    let projectID = ColonyProjectID(rawValue: "project:service")
    let sessionID = ColonyProductSessionID(rawValue: "session:service")

    let project = try await service.createProject(
        ColonyProjectCreateInput(projectID: projectID, name: "Service Project")
    )
    #expect(project.projectID == projectID)

    let session = try await service.createSession(
        ColonySessionCreateInput(
            sessionID: sessionID,
            projectID: projectID,
            metadata: ["purpose": "integration"]
        )
    )
    #expect(session.sessionID == sessionID)

    let loadedProject = await service.getProject(id: projectID)
    let loadedSession = await service.getSession(id: sessionID)
    #expect(loadedProject?.projectID == projectID)
    #expect(loadedSession?.sessionID == sessionID)

    let shared = try await service.shareSession(
        ColonySessionShareInput(sessionID: sessionID, metadata: ["scope": "internal"])
    )
    #expect(shared.token.rawValue == "share:session:service")
}
