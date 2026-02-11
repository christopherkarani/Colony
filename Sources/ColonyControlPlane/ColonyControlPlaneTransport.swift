import Foundation

public enum ColonyControlPlaneTransportKind: String, Codable, Sendable {
    case rest
    case sse
    case webSocket = "web_socket"
}

public enum ColonyControlPlaneHTTPMethod: String, Codable, Sendable {
    case get = "GET"
    case post = "POST"
    case delete = "DELETE"
}

public enum ColonyControlPlaneOperation: String, Codable, Sendable, CaseIterable {
    case createProject = "project.create"
    case getProject = "project.get"
    case listProjects = "project.list"
    case deleteProject = "project.delete"

    case createSession = "session.create"
    case getSession = "session.get"
    case listSessions = "session.list"
    case deleteSession = "session.delete"
    case forkSession = "session.fork"
    case revertSession = "session.revert"
    case shareSession = "session.share"

    case streamSessionEventsSSE = "session.events.sse"
    case streamSessionEventsWebSocket = "session.events.websocket"
}

public struct ColonyControlPlaneRouteDescriptor: Codable, Equatable, Sendable {
    public let operation: ColonyControlPlaneOperation
    public let transport: ColonyControlPlaneTransportKind
    public let path: String
    public let method: ColonyControlPlaneHTTPMethod?
    public let streamEvent: String?

    public init(
        operation: ColonyControlPlaneOperation,
        transport: ColonyControlPlaneTransportKind,
        path: String,
        method: ColonyControlPlaneHTTPMethod? = nil,
        streamEvent: String? = nil
    ) {
        self.operation = operation
        self.transport = transport
        self.path = path
        self.method = method
        self.streamEvent = streamEvent
    }
}

public protocol ColonyControlPlaneTransport: Sendable {
    var transportKind: ColonyControlPlaneTransportKind { get }
    func register(routes: [ColonyControlPlaneRouteDescriptor]) async throws
}

public protocol ColonyControlPlaneRESTTransport: ColonyControlPlaneTransport {}
public protocol ColonyControlPlaneSSETransport: ColonyControlPlaneTransport {}
public protocol ColonyControlPlaneWebSocketTransport: ColonyControlPlaneTransport {}
