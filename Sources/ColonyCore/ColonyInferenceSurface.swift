import Foundation

// ColonyThreadID and ColonyInterruptID are now typealiases
// defined in ColonyID.swift via ColonyID<Domain> generic.

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

// MARK: - ColonyTool.Definition

extension ColonyTool {
    public struct Definition: Codable, Sendable, Equatable {
        public let name: ColonyTool.Name
        public let description: String
        public let parametersJSONSchema: String

        public init(name: ColonyTool.Name, description: String, parametersJSONSchema: String) {
            self.name = name
            self.description = description
            self.parametersJSONSchema = parametersJSONSchema
        }
    }
}

// MARK: - ColonyTool.Call

extension ColonyTool {
    public struct Call: Codable, Sendable, Equatable {
        public let id: ColonyToolCallID
        public let name: ColonyTool.Name
        public let argumentsJSON: String

        public init(id: ColonyToolCallID, name: ColonyTool.Name, argumentsJSON: String) {
            self.id = id
            self.name = name
            self.argumentsJSON = argumentsJSON
        }
    }
}

// MARK: - ColonyTool.Result

extension ColonyTool {
    public struct Result: Codable, Sendable, Equatable {
        public let toolCallID: ColonyToolCallID
        public let content: String

        public init(toolCallID: ColonyToolCallID, content: String) {
            self.toolCallID = toolCallID
            self.content = content
        }
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
    public let id: ColonyMessageID
    public let role: ColonyChatRole
    public let content: String
    public let name: ColonyTool.Name?
    public let toolCallID: ColonyToolCallID?
    public let toolCalls: [ColonyTool.Call]
    public let structuredOutput: ColonyStructuredOutputPayload?
    public let operation: ColonyChatMessageOperation?

    public init(
        id: ColonyMessageID,
        role: ColonyChatRole,
        content: String,
        name: ColonyTool.Name? = nil,
        toolCallID: ColonyToolCallID? = nil,
        toolCalls: [ColonyTool.Call] = [],
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
    public let model: ColonyModelName
    public let messages: [ColonyChatMessage]
    public let tools: [ColonyTool.Definition]
    public let structuredOutput: ColonyStructuredOutput?

    public init(
        model: ColonyModelName,
        messages: [ColonyChatMessage],
        tools: [ColonyTool.Definition],
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

public protocol ColonyToolRegistry: Sendable {
    func listTools() -> [ColonyTool.Definition]
    func invoke(_ call: ColonyTool.Call) async throws -> ColonyTool.Result
}

public protocol ColonyModelRouter: Sendable {
    func route(_ request: ColonyModelRequest, hints: ColonyInferenceHints?) -> any ColonyModelClient
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
    public let tokenBudget: ColonyTokenCount?
    public let networkState: ColonyNetworkState

    public init(
        latencyTier: ColonyLatencyTier = .interactive,
        privacyRequired: Bool = false,
        tokenBudget: ColonyTokenCount? = nil,
        networkState: ColonyNetworkState = .online
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
