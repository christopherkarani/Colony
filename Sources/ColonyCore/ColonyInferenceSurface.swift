import Foundation

public struct ColonyThreadID: Hashable, Codable, Sendable, ExpressibleByStringLiteral, LosslessStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public var description: String {
        rawValue
    }
}

public struct ColonyInterruptID: Hashable, Codable, Sendable, ExpressibleByStringLiteral, LosslessStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public var description: String {
        rawValue
    }
}

public enum ColonyChatRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

public enum ColonyChatMessageOperation: String, Codable, Sendable {
    case remove
    case removeAll
}

public struct ColonyToolDefinition: Codable, Sendable, Equatable {
    public let name: String
    public let description: String
    public let parametersJSONSchema: String

    public init(name: String, description: String, parametersJSONSchema: String) {
        self.name = name
        self.description = description
        self.parametersJSONSchema = parametersJSONSchema
    }
}

public struct ColonyToolCall: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let argumentsJSON: String

    public init(id: String, name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

public struct ColonyToolResult: Codable, Sendable, Equatable {
    public let toolCallID: String
    public let content: String

    public init(toolCallID: String, content: String) {
        self.toolCallID = toolCallID
        self.content = content
    }
}

public enum ColonyStructuredOutput: Codable, Sendable, Equatable {
    case jsonObject
    case jsonSchema(name: String, schemaJSON: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case name
        case schemaJSON
    }

    private enum Kind: String, Codable {
        case jsonObject = "json_object"
        case jsonSchema = "json_schema"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .jsonObject:
            try container.encode(Kind.jsonObject, forKey: .type)
        case let .jsonSchema(name, schemaJSON):
            try container.encode(Kind.jsonSchema, forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(schemaJSON, forKey: .schemaJSON)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .jsonObject:
            self = .jsonObject
        case .jsonSchema:
            self = .jsonSchema(
                name: try container.decode(String.self, forKey: .name),
                schemaJSON: try container.decode(String.self, forKey: .schemaJSON)
            )
        }
    }
}

public struct ColonyStructuredOutputPayload: Codable, Sendable, Equatable {
    public let format: ColonyStructuredOutput
    public let json: String

    public init(format: ColonyStructuredOutput, json: String) {
        self.format = format
        self.json = json
    }
}

public struct ColonyChatMessage: Codable, Sendable, Equatable {
    public let id: String
    public let role: ColonyChatRole
    public let content: String
    public let name: String?
    public let toolCallID: String?
    public let toolCalls: [ColonyToolCall]
    public let structuredOutput: ColonyStructuredOutputPayload?
    public let operation: ColonyChatMessageOperation?

    public init(
        id: String,
        role: ColonyChatRole,
        content: String,
        name: String? = nil,
        toolCallID: String? = nil,
        toolCalls: [ColonyToolCall] = [],
        structuredOutput: ColonyStructuredOutputPayload? = nil,
        operation: ColonyChatMessageOperation? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.name = name
        self.toolCallID = toolCallID
        self.toolCalls = toolCalls
        self.structuredOutput = structuredOutput
        self.operation = operation
    }
}

public struct ColonyModelRequest: Codable, Sendable, Equatable {
    public let model: String
    public let messages: [ColonyChatMessage]
    public let tools: [ColonyToolDefinition]
    public let structuredOutput: ColonyStructuredOutput?

    public init(
        model: String,
        messages: [ColonyChatMessage],
        tools: [ColonyToolDefinition],
        structuredOutput: ColonyStructuredOutput? = nil
    ) {
        self.model = model
        self.messages = messages
        self.tools = tools
        self.structuredOutput = structuredOutput
    }
}

public struct ColonyModelResponse: Codable, Sendable, Equatable {
    public let message: ColonyChatMessage

    public init(message: ColonyChatMessage) {
        self.message = message
    }
}

public enum ColonyModelStreamChunk: Sendable, Equatable {
    case token(String)
    case final(ColonyModelResponse)
}

public protocol ColonyModelClient: Sendable {
    func complete(_ request: ColonyModelRequest) async throws -> ColonyModelResponse
    func stream(_ request: ColonyModelRequest) -> AsyncThrowingStream<ColonyModelStreamChunk, Error>
}

public extension ColonyModelClient {
    func streamFinal(_ request: ColonyModelRequest) async throws -> ColonyModelResponse {
        var finalResponse: ColonyModelResponse?
        var sawFinal = false

        for try await chunk in stream(request) {
            switch chunk {
            case .token:
                if sawFinal {
                    throw ColonyModelClientError.invalidStream("Received token after final chunk.")
                }
            case .final(let response):
                if sawFinal {
                    throw ColonyModelClientError.invalidStream("Received multiple final chunks.")
                }
                sawFinal = true
                finalResponse = response
            }
        }

        guard let finalResponse else {
            throw ColonyModelClientError.invalidStream("Missing final chunk.")
        }

        return finalResponse
    }
}

public struct AnyColonyModelClient: ColonyModelClient, Sendable {
    private let completeClosure: @Sendable (ColonyModelRequest) async throws -> ColonyModelResponse
    private let streamClosure: @Sendable (ColonyModelRequest) -> AsyncThrowingStream<ColonyModelStreamChunk, Error>

    public init<Client: ColonyModelClient>(_ client: Client) {
        self.completeClosure = client.complete
        self.streamClosure = client.stream
    }

    public func complete(_ request: ColonyModelRequest) async throws -> ColonyModelResponse {
        try await completeClosure(request)
    }

    public func stream(_ request: ColonyModelRequest) -> AsyncThrowingStream<ColonyModelStreamChunk, Error> {
        streamClosure(request)
    }
}

public protocol ColonyToolRegistry: Sendable {
    func listTools() -> [ColonyToolDefinition]
    func invoke(_ call: ColonyToolCall) async throws -> ColonyToolResult
}

public struct AnyColonyToolRegistry: ColonyToolRegistry, Sendable {
    private let listClosure: @Sendable () -> [ColonyToolDefinition]
    private let invokeClosure: @Sendable (ColonyToolCall) async throws -> ColonyToolResult

    public init<Registry: ColonyToolRegistry>(_ registry: Registry) {
        self.listClosure = registry.listTools
        self.invokeClosure = registry.invoke
    }

    public func listTools() -> [ColonyToolDefinition] {
        listClosure()
    }

    public func invoke(_ call: ColonyToolCall) async throws -> ColonyToolResult {
        try await invokeClosure(call)
    }
}

public protocol ColonyModelRouter: Sendable {
    func route(_ request: ColonyModelRequest, hints: ColonyInferenceHints?) -> AnyColonyModelClient
}

public struct AnyColonyModelRouter: ColonyModelRouter, Sendable {
    private let routeClosure: @Sendable (ColonyModelRequest, ColonyInferenceHints?) -> AnyColonyModelClient

    public init<Router: ColonyModelRouter>(_ router: Router) {
        self.routeClosure = router.route
    }

    public func route(_ request: ColonyModelRequest, hints: ColonyInferenceHints?) -> AnyColonyModelClient {
        routeClosure(request, hints)
    }
}

public enum ColonyLatencyTier: String, Codable, Sendable {
    case interactive
    case background
}

public enum ColonyNetworkState: String, Codable, Sendable {
    case offline
    case online
    case metered
}

public struct ColonyInferenceHints: Codable, Sendable, Equatable {
    public let latencyTier: ColonyLatencyTier
    public let privacyRequired: Bool
    public let tokenBudget: Int?
    public let networkState: ColonyNetworkState

    public init(
        latencyTier: ColonyLatencyTier,
        privacyRequired: Bool,
        tokenBudget: Int?,
        networkState: ColonyNetworkState
    ) {
        self.latencyTier = latencyTier
        self.privacyRequired = privacyRequired
        self.tokenBudget = tokenBudget
        self.networkState = networkState
    }
}

public enum ColonyModelClientError: Error, Sendable, Equatable {
    case invalidStream(String)
}
