import Foundation

// ColonyThreadID and ColonyInterruptID are now typealiases
// defined in ColonyID.swift via ColonyID<Domain> generic.

/// The role of a participant in a chat message exchange.
public enum ColonyChatRole: String, Codable, Sendable {
    /// System-level instruction (e.g., the agent's system prompt).
    case system
    /// A message from the human user.
    case user
    /// A response from the AI model.
    case assistant
    /// The result of a tool invocation, returned to the model.
    case tool
}

/// Operations that manipulate the message history.
public enum ColonyChatMessageOperation: String, Codable, Sendable {
    /// Remove a specific message by ID.
    case remove
    /// Remove all messages from the conversation.
    case removeAll
}

// MARK: - ColonyTool.Definition

/// A tool definition passed to the model, describing what the tool does and its parameters.
///
/// `Definition` objects are included in `ColonyModelRequest.tools` so the model knows
/// what tools are available and how to invoke them.
extension ColonyTool {
    public struct Definition: Codable, Sendable, Equatable {
        /// The unique name identifying this tool.
        public let name: ColonyTool.Name
        /// A human-readable description of what the tool does.
        public let description: String
        /// A JSON Schema string describing the tool's input parameters.
        public let parametersJSONSchema: String

        public init(name: ColonyTool.Name, description: String, parametersJSONSchema: String) {
            self.name = name
            self.description = description
            self.parametersJSONSchema = parametersJSONSchema
        }
    }
}

// MARK: - ColonyTool.Call

/// An active tool invocation emitted by the model during a run.
///
/// `Call` objects are what appear in `ColonyRun.Interruption.toolCalls` when the
/// runtime pauses for human approval.
extension ColonyTool {
    public struct Call: Codable, Sendable, Equatable {
        /// Unique identifier for this call — used to match the result.
        public let id: ColonyToolCallID
        /// The tool being invoked.
        public let name: ColonyTool.Name
        /// The tool's input arguments as a JSON string.
        public let argumentsJSON: String

        public init(id: ColonyToolCallID, name: ColonyTool.Name, argumentsJSON: String) {
            self.id = id
            self.name = name
            self.argumentsJSON = argumentsJSON
        }
    }
}

// MARK: - ColonyTool.Result

/// The result of a tool invocation, returned to the model as a chat message.
extension ColonyTool {
    public struct Result: Codable, Sendable, Equatable {
        /// The ID of the call this result corresponds to.
        public let toolCallID: ColonyToolCallID
        /// The output of the tool as a string.
        public let content: String

        public init(toolCallID: ColonyToolCallID, content: String) {
            self.toolCallID = toolCallID
            self.content = content
        }
    }
}

/// Describes the structured output format requested from the model.
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

/// The parsed structured output payload returned by the model.
public struct ColonyStructuredOutputPayload: Codable, Sendable, Equatable {
    /// The format specification that was used for this output.
    public let format: ColonyStructuredOutput
    /// The JSON string content produced by the model.
    public let json: String

    public init(format: ColonyStructuredOutput, json: String) {
        self.format = format
        self.json = json
    }
}

/// A single message in the conversation history exchanged with the model.
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

/// A request sent to the AI model, containing messages, available tools, and output format.
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

/// A complete response from the AI model, wrapping a chat message.
public struct ColonyModelResponse: Codable, Sendable, Equatable {
    public let message: ColonyChatMessage

    public init(message: ColonyChatMessage) {
        self.message = message
    }
}

/// A chunk emitted during streamed model inference.
public enum ColonyModelStreamChunk: Sendable, Equatable {
    /// A single token delta — append to build the full response.
    case token(String)
    /// The final complete response signal.
    case final(ColonyModelResponse)
}

/// A protocol for sending requests to an AI model.
///
/// Colony ships with `HiveModelClient` (backed by the Hive runtime) as the default
/// implementation. Custom implementations can route to other model providers.
public protocol ColonyModelClient: Sendable {
    /// Send a non-streaming request and wait for the complete response.
    func complete(_ request: ColonyModelRequest) async throws -> ColonyModelResponse
    /// Send a streaming request and yield tokens as they arrive.
    func stream(_ request: ColonyModelRequest) -> AsyncThrowingStream<ColonyModelStreamChunk, Error>
}

public extension ColonyModelClient {
    /// Consume a stream and return only the final response.
    /// Throws `ColonyModelClientError.invalidStream` if the stream is malformed.
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

/// The registry of tools available to the agent at runtime.
///
/// The runtime queries `listTools()` to build the tool list sent to the model,
/// and calls `invoke(_:)` to execute a tool call approved by the human.
public protocol ColonyToolRegistry: Sendable {
    /// Returns all tool definitions available to the agent.
    func listTools() -> [ColonyTool.Definition]
    /// Invokes a specific tool call and returns its result.
    func invoke(_ call: ColonyTool.Call) async throws -> ColonyTool.Result
}

/// Routes a model request to the appropriate `ColonyModelClient` based on request hints.
///
/// The router enables multi-model setups where different models are selected based on
/// task type, latency requirements, or privacy constraints.
public protocol ColonyModelRouter: Sendable {
    /// Route a request to the appropriate model client.
    /// The `hints` parameter carries latency tier, privacy requirements, and token budget.
    func route(_ request: ColonyModelRequest, hints: ColonyInferenceHints?) -> any ColonyModelClient
}

/// The expected latency budget for a model request.
public enum ColonyLatencyTier: String, Codable, Sendable {
    /// Response needed within a few seconds — use fast models.
    case interactive
    /// Response can take longer — use capable but slower models.
    case background
}

/// The current network connectivity state.
public enum ColonyNetworkState: String, Codable, Sendable {
    /// No network access available.
    case offline
    /// Network available with no bandwidth restrictions.
    case online
    /// Network available but metered or expensive (e.g., cellular).
    case metered
}

/// Hints passed to `ColonyModelRouter` to select the right model for the current task.
public struct ColonyInferenceHints: Codable, Sendable, Equatable {
    /// The latency budget for this request.
    public let latencyTier: ColonyLatencyTier
    /// Whether the request must be processed on-device (privacy-sensitive).
    public let privacyRequired: Bool
    /// Maximum tokens to spend on this request.
    public let tokenBudget: ColonyTokenCount?
    /// Current network state affecting remote API availability.
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

/// Errors thrown by `ColonyModelClient` implementations.
public enum ColonyModelClientError: Error, Sendable, Equatable {
    case invalidStream(String)
}
