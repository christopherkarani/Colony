import Foundation

public actor ColonyControlPlaneService {
    public nonisolated static let defaultRouteDescriptors: [ColonyControlPlaneRouteDescriptor] = [
        ColonyControlPlaneRouteDescriptor(
            operation: .createProject,
            transport: .rest,
            path: "/v1/projects",
            method: .post
        ),
        ColonyControlPlaneRouteDescriptor(
            operation: .getProject,
            transport: .rest,
            path: "/v1/projects/{project_id}",
            method: .get
        ),
        ColonyControlPlaneRouteDescriptor(
            operation: .listProjects,
            transport: .rest,
            path: "/v1/projects",
            method: .get
        ),
        ColonyControlPlaneRouteDescriptor(
            operation: .deleteProject,
            transport: .rest,
            path: "/v1/projects/{project_id}",
            method: .delete
        ),
        ColonyControlPlaneRouteDescriptor(
            operation: .createSession,
            transport: .rest,
            path: "/v1/projects/{project_id}/sessions",
            method: .post
        ),
        ColonyControlPlaneRouteDescriptor(
            operation: .getSession,
            transport: .rest,
            path: "/v1/sessions/{session_id}",
            method: .get
        ),
        ColonyControlPlaneRouteDescriptor(
            operation: .listSessions,
            transport: .rest,
            path: "/v1/projects/{project_id}/sessions",
            method: .get
        ),
        ColonyControlPlaneRouteDescriptor(
            operation: .deleteSession,
            transport: .rest,
            path: "/v1/sessions/{session_id}",
            method: .delete
        ),
        ColonyControlPlaneRouteDescriptor(
            operation: .forkSession,
            transport: .rest,
            path: "/v1/sessions/{session_id}/fork",
            method: .post
        ),
        ColonyControlPlaneRouteDescriptor(
            operation: .revertSession,
            transport: .rest,
            path: "/v1/sessions/{session_id}/revert",
            method: .post
        ),
        ColonyControlPlaneRouteDescriptor(
            operation: .shareSession,
            transport: .rest,
            path: "/v1/sessions/{session_id}/share",
            method: .post
        ),
        ColonyControlPlaneRouteDescriptor(
            operation: .streamSessionEventsSSE,
            transport: .sse,
            path: "/v1/sessions/{session_id}/events",
            streamEvent: "session_event"
        ),
        ColonyControlPlaneRouteDescriptor(
            operation: .streamSessionEventsWebSocket,
            transport: .webSocket,
            path: "/v1/sessions/{session_id}/ws",
            streamEvent: "session_event"
        ),
    ]

    private let projectStore: any ColonyProjectStore
    private let sessionStore: ColonySessionStore

    public init(
        projectStore: any ColonyProjectStore = InMemoryColonyProjectStore(),
        sessionStore: ColonySessionStore = ColonySessionStore()
    ) {
        self.projectStore = projectStore
        self.sessionStore = sessionStore
    }

    public func routeDescriptors() -> [ColonyControlPlaneRouteDescriptor] {
        Self.defaultRouteDescriptors
    }

    public func registerRoutes(
        rest: (any ColonyControlPlaneRESTTransport)? = nil,
        sse: (any ColonyControlPlaneSSETransport)? = nil,
        webSocket: (any ColonyControlPlaneWebSocketTransport)? = nil
    ) async throws {
        if let rest {
            try await registerRoutes(on: rest)
        }
        if let sse {
            try await registerRoutes(on: sse)
        }
        if let webSocket {
            try await registerRoutes(on: webSocket)
        }
    }

    public func createProject(_ input: ColonyProjectCreateInput) async throws -> ColonyProjectRecord {
        try await projectStore.createProject(input)
    }

    public func getProject(id: ColonyProjectID) async -> ColonyProjectRecord? {
        await projectStore.getProject(id: id)
    }

    public func listProjects() async -> [ColonyProjectRecord] {
        await projectStore.listProjects()
    }

    public func deleteProject(id: ColonyProjectID) async -> Bool {
        await projectStore.deleteProject(id: id)
    }

    public func createSession(_ input: ColonySessionCreateInput) async throws -> ColonyProductSessionRecord {
        try await sessionStore.createSession(input)
    }

    public func getSession(id: ColonyProductSessionID) async -> ColonyProductSessionRecord? {
        await sessionStore.getSession(id: id)
    }

    public func listSessions(projectID: ColonyProjectID? = nil) async -> [ColonyProductSessionRecord] {
        await sessionStore.listSessions(projectID: projectID)
    }

    public func deleteSession(id: ColonyProductSessionID) async -> Bool {
        await sessionStore.deleteSession(id: id)
    }

    public func forkSession(_ input: ColonySessionForkInput) async throws -> ColonyProductSessionRecord {
        try await sessionStore.forkSession(input)
    }

    public func revertSession(sessionID: ColonyProductSessionID) async throws -> ColonyProductSessionRecord {
        try await sessionStore.revertSession(sessionID: sessionID)
    }

    public func shareSession(_ input: ColonySessionShareInput) async throws -> ColonyProductSessionShareRecord {
        try await sessionStore.shareSession(input)
    }

    private func registerRoutes(on transport: any ColonyControlPlaneTransport) async throws {
        let routes = Self.defaultRouteDescriptors.filter { $0.transport == transport.transportKind }
        try await transport.register(routes: routes)
    }
}
