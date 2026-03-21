import Foundation
import ColonyCore

extension ControlPlane {
    public actor Service {
        public nonisolated static let defaultRouteDescriptors: [ControlPlane.RouteDescriptor] = [
            ControlPlane.RouteDescriptor(
                operation: .createProject,
                transport: .rest,
                path: "/v1/projects",
                method: .post
            ),
            ControlPlane.RouteDescriptor(
                operation: .getProject,
                transport: .rest,
                path: "/v1/projects/{project_id}",
                method: .get
            ),
            ControlPlane.RouteDescriptor(
                operation: .listProjects,
                transport: .rest,
                path: "/v1/projects",
                method: .get
            ),
            ControlPlane.RouteDescriptor(
                operation: .deleteProject,
                transport: .rest,
                path: "/v1/projects/{project_id}",
                method: .delete
            ),
            ControlPlane.RouteDescriptor(
                operation: .createSession,
                transport: .rest,
                path: "/v1/projects/{project_id}/sessions",
                method: .post
            ),
            ControlPlane.RouteDescriptor(
                operation: .getSession,
                transport: .rest,
                path: "/v1/sessions/{session_id}",
                method: .get
            ),
            ControlPlane.RouteDescriptor(
                operation: .listSessions,
                transport: .rest,
                path: "/v1/projects/{project_id}/sessions",
                method: .get
            ),
            ControlPlane.RouteDescriptor(
                operation: .deleteSession,
                transport: .rest,
                path: "/v1/sessions/{session_id}",
                method: .delete
            ),
            ControlPlane.RouteDescriptor(
                operation: .forkSession,
                transport: .rest,
                path: "/v1/sessions/{session_id}/fork",
                method: .post
            ),
            ControlPlane.RouteDescriptor(
                operation: .revertSession,
                transport: .rest,
                path: "/v1/sessions/{session_id}/revert",
                method: .post
            ),
            ControlPlane.RouteDescriptor(
                operation: .shareSession,
                transport: .rest,
                path: "/v1/sessions/{session_id}/share",
                method: .post
            ),
            ControlPlane.RouteDescriptor(
                operation: .streamSessionEventsSSE,
                transport: .sse,
                path: "/v1/sessions/{session_id}/events",
                streamEvent: "session_event"
            ),
            ControlPlane.RouteDescriptor(
                operation: .streamSessionEventsWebSocket,
                transport: .webSocket,
                path: "/v1/sessions/{session_id}/ws",
                streamEvent: "session_event"
            ),
        ]

        private let projectStore: any ControlPlaneProjectStore
        private let sessionStore: ControlPlane.SessionStore

        package init(
            projectStore: any ControlPlaneProjectStore = InMemoryControlPlaneProjectStore(),
            sessionStore: ControlPlane.SessionStore = ControlPlane.SessionStore()
        ) {
            self.projectStore = projectStore
            self.sessionStore = sessionStore
        }

        public func routeDescriptors() -> [ControlPlane.RouteDescriptor] {
            Self.defaultRouteDescriptors
        }

        public func registerRoutes(
            rest: (any ControlPlaneTransport)? = nil,
            sse: (any ControlPlaneTransport)? = nil,
            webSocket: (any ControlPlaneTransport)? = nil
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

        public func createProject(_ input: ControlPlane.ProjectCreateInput) async throws -> ControlPlane.ProjectRecord {
            try await projectStore.createProject(input)
        }

        public func getProject(id: ColonyProjectID) async -> ControlPlane.ProjectRecord? {
            await projectStore.getProject(id: id)
        }

        public func listProjects() async -> [ControlPlane.ProjectRecord] {
            await projectStore.listProjects()
        }

        public func deleteProject(id: ColonyProjectID) async -> Bool {
            await projectStore.deleteProject(id: id)
        }

        public func createSession(_ input: ControlPlane.SessionCreateInput) async throws -> ControlPlane.SessionRecord {
            try await sessionStore.createSession(input)
        }

        public func getSession(id: ColonyProductSessionID) async -> ControlPlane.SessionRecord? {
            await sessionStore.getSession(id: id)
        }

        public func listSessions(projectID: ColonyProjectID? = nil) async -> [ControlPlane.SessionRecord] {
            await sessionStore.listSessions(projectID: projectID)
        }

        public func deleteSession(id: ColonyProductSessionID) async -> Bool {
            await sessionStore.deleteSession(id: id)
        }

        public func forkSession(_ input: ControlPlane.SessionForkInput) async throws -> ControlPlane.SessionRecord {
            try await sessionStore.forkSession(input)
        }

        public func revertSession(sessionID: ColonyProductSessionID) async throws -> ControlPlane.SessionRecord {
            try await sessionStore.revertSession(sessionID: sessionID)
        }

        public func shareSession(_ input: ControlPlane.SessionShareInput) async throws -> ControlPlane.SessionShareRecord {
            try await sessionStore.shareSession(input)
        }

        private func registerRoutes(on transport: any ControlPlaneTransport) async throws {
            let routes = Self.defaultRouteDescriptors.filter { $0.transport == transport.transportKind }
            try await transport.register(routes: routes)
        }
    }
}

// MARK: - Tier-1 Factory

extension ControlPlane {
    /// Create an in-memory control plane service with zero configuration.
    ///
    /// ```swift
    /// let service = ControlPlane.inMemory()
    /// let project = try await service.createProject(.init(name: "My Project"))
    /// ```
    public static func inMemory() -> ControlPlane.Service {
        ControlPlane.Service()
    }
}

