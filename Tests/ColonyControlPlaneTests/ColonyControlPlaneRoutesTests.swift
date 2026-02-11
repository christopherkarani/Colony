import Testing
@testable import ColonyControlPlane

private actor CapturingRESTTransport: ColonyControlPlaneRESTTransport {
    nonisolated let transportKind: ColonyControlPlaneTransportKind = .rest
    private var capturedRoutes: [ColonyControlPlaneRouteDescriptor] = []

    func register(routes: [ColonyControlPlaneRouteDescriptor]) async throws {
        capturedRoutes = routes
    }

    func routes() -> [ColonyControlPlaneRouteDescriptor] {
        capturedRoutes
    }
}

private actor CapturingSSETransport: ColonyControlPlaneSSETransport {
    nonisolated let transportKind: ColonyControlPlaneTransportKind = .sse
    private var capturedRoutes: [ColonyControlPlaneRouteDescriptor] = []

    func register(routes: [ColonyControlPlaneRouteDescriptor]) async throws {
        capturedRoutes = routes
    }

    func routes() -> [ColonyControlPlaneRouteDescriptor] {
        capturedRoutes
    }
}

private actor CapturingWebSocketTransport: ColonyControlPlaneWebSocketTransport {
    nonisolated let transportKind: ColonyControlPlaneTransportKind = .webSocket
    private var capturedRoutes: [ColonyControlPlaneRouteDescriptor] = []

    func register(routes: [ColonyControlPlaneRouteDescriptor]) async throws {
        capturedRoutes = routes
    }

    func routes() -> [ColonyControlPlaneRouteDescriptor] {
        capturedRoutes
    }
}

@Test("Control-plane route metadata is registered by transport")
func controlPlaneRouteRegistrationMetadata() async throws {
    let service = ColonyControlPlaneService()
    let restTransport = CapturingRESTTransport()
    let sseTransport = CapturingSSETransport()
    let webSocketTransport = CapturingWebSocketTransport()

    try await service.registerRoutes(
        rest: restTransport,
        sse: sseTransport,
        webSocket: webSocketTransport
    )

    let restRoutes = await restTransport.routes()
    let sseRoutes = await sseTransport.routes()
    let webSocketRoutes = await webSocketTransport.routes()

    #expect(restRoutes.count == 11)
    #expect(restRoutes.allSatisfy { $0.transport == .rest && $0.method != nil })

    let createProjectRoute = restRoutes.first { $0.operation == .createProject }
    #expect(createProjectRoute?.path == "/v1/projects")
    #expect(createProjectRoute?.method == .post)

    let shareSessionRoute = restRoutes.first { $0.operation == .shareSession }
    #expect(shareSessionRoute?.path == "/v1/sessions/{session_id}/share")
    #expect(shareSessionRoute?.method == .post)

    #expect(sseRoutes.count == 1)
    #expect(sseRoutes.first?.operation == .streamSessionEventsSSE)
    #expect(sseRoutes.first?.path == "/v1/sessions/{session_id}/events")
    #expect(sseRoutes.first?.method == nil)
    #expect(sseRoutes.first?.streamEvent == "session_event")

    #expect(webSocketRoutes.count == 1)
    #expect(webSocketRoutes.first?.operation == .streamSessionEventsWebSocket)
    #expect(webSocketRoutes.first?.path == "/v1/sessions/{session_id}/ws")
    #expect(webSocketRoutes.first?.method == nil)
    #expect(webSocketRoutes.first?.streamEvent == "session_event")
}

@Test("Advertised route descriptors remain unique by operation + transport")
func routeDescriptorUniqueness() async throws {
    let service = ColonyControlPlaneService()
    let descriptors = await service.routeDescriptors()
    let operationTransportPairs = Set(
        descriptors.map { descriptor in
            descriptor.operation.rawValue + "::" + descriptor.transport.rawValue
        }
    )

    #expect(descriptors.count == operationTransportPairs.count)
    #expect(descriptors.contains { $0.operation == .forkSession && $0.method == .post })
    #expect(descriptors.contains { $0.operation == .revertSession && $0.method == .post })
    #expect(descriptors.contains { $0.operation == .streamSessionEventsWebSocket && $0.transport == .webSocket })
}
