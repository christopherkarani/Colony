import Foundation

/// Namespace for all Colony control-plane domain types.
public enum ControlPlane {}

// MARK: - Nested Types

extension ControlPlane {
    public enum TransportKind: String, Codable, Sendable {
        case rest
        case sse
        case webSocket = "web_socket"
    }

    public enum HTTPMethod: String, Codable, Sendable {
        case get = "GET"
        case post = "POST"
        case delete = "DELETE"
    }

    public enum Operation: String, Codable, Sendable, CaseIterable {
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

    public struct RouteDescriptor: Codable, Equatable, Sendable {
        public let operation: ControlPlane.Operation
        public let transport: ControlPlane.TransportKind
        public let path: String
        public let method: ControlPlane.HTTPMethod?
        public let streamEvent: String?

        public init(
            operation: ControlPlane.Operation,
            transport: ControlPlane.TransportKind,
            path: String,
            method: ControlPlane.HTTPMethod? = nil,
            streamEvent: String? = nil
        ) {
            self.operation = operation
            self.transport = transport
            self.path = path
            self.method = method
            self.streamEvent = streamEvent
        }
    }
}

// MARK: - Protocol (top-level, protocols cannot be nested)

public protocol ControlPlaneTransport: Sendable {
    var transportKind: ControlPlane.TransportKind { get }
    func register(routes: [ControlPlane.RouteDescriptor]) async throws
}

