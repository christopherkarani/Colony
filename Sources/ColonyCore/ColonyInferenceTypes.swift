import Foundation
@_spi(ColonyInternal) import Swarm

public protocol ColonyModelClient: Sendable {
    func generate(_ request: ColonyInferenceRequest) async throws -> ColonyInferenceResponse
    func stream(_ request: ColonyInferenceRequest) -> AsyncThrowingStream<ColonyInferenceStreamChunk, Error>
}

public enum ColonyMessageRole: String, Codable, Sendable, Equatable {
    case system
    case user
    case assistant
    case tool
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

public enum ColonyMessageOp: String, Codable, Sendable, Equatable {
    case remove
    case removeAll
}

public struct ColonyMessage: Codable, Sendable, Equatable {
    public let id: String
    public let role: ColonyMessageRole
    public let content: String
    public let name: String?
    public let toolCallID: String?
    public let toolCalls: [ColonyToolCall]
    public let op: ColonyMessageOp?

    public init(
        id: String,
        role: ColonyMessageRole,
        content: String,
        name: String? = nil,
        toolCallID: String? = nil,
        toolCalls: [ColonyToolCall] = [],
        op: ColonyMessageOp? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.name = name
        self.toolCallID = toolCallID
        self.toolCalls = toolCalls
        self.op = op
    }
}

public struct ColonyInferenceRequest: Sendable, Equatable {
    public enum Complexity: Sendable, Equatable {
        case automatic
        case simple
        case complex
    }

    public let messages: [ColonyMessage]
    public let tools: [ColonyToolDefinition]
    public let complexity: Complexity
    public let modelName: String?

    public init(
        messages: [ColonyMessage],
        tools: [ColonyToolDefinition],
        complexity: Complexity = .automatic,
        modelName: String? = nil
    ) {
        self.messages = messages
        self.tools = tools
        self.complexity = complexity
        self.modelName = modelName
    }
}

public struct ColonyInferenceResponse: Sendable, Equatable {
    public struct Usage: Sendable, Equatable {
        public let promptTokens: Int
        public let completionTokens: Int

        public init(promptTokens: Int, completionTokens: Int) {
            self.promptTokens = promptTokens
            self.completionTokens = completionTokens
        }

        public var totalTokens: Int {
            promptTokens + completionTokens
        }
    }

    public let message: ColonyMessage
    public let usage: Usage?
    public let providerID: String?

    public init(
        message: ColonyMessage,
        usage: Usage? = nil,
        providerID: String? = nil
    ) {
        self.message = message
        self.usage = usage
        self.providerID = providerID
    }

    public var content: String {
        message.content
    }
}

public enum ColonyInferenceStreamChunk: Sendable, Equatable {
    case token(String)
    case final(ColonyInferenceResponse)
}

package extension ColonyToolDefinition {
    init(_ hive: HiveToolDefinition) {
        self.init(
            name: hive.name,
            description: hive.description,
            parametersJSONSchema: hive.parametersJSONSchema
        )
    }

    var hiveToolDefinition: HiveToolDefinition {
        HiveToolDefinition(
            name: name,
            description: description,
            parametersJSONSchema: parametersJSONSchema
        )
    }
}

package extension ColonyToolCall {
    init(_ hive: HiveToolCall) {
        self.init(id: hive.id, name: hive.name, argumentsJSON: hive.argumentsJSON)
    }

    var hiveToolCall: HiveToolCall {
        HiveToolCall(id: id, name: name, argumentsJSON: argumentsJSON)
    }
}

package extension ColonyMessageRole {
    init(_ hive: HiveChatRole) {
        self = ColonyMessageRole(rawValue: hive.rawValue) ?? .assistant
    }

    var hiveChatRole: HiveChatRole {
        HiveChatRole(rawValue: rawValue) ?? .assistant
    }
}

package extension ColonyMessageOp {
    init(_ hive: HiveChatMessageOp) {
        self = ColonyMessageOp(rawValue: hive.rawValue) ?? .remove
    }

    var hiveChatMessageOp: HiveChatMessageOp {
        HiveChatMessageOp(rawValue: rawValue) ?? .remove
    }
}

package extension ColonyMessage {
    init(_ hive: HiveChatMessage) {
        self.init(
            id: hive.id,
            role: ColonyMessageRole(hive.role),
            content: hive.content,
            name: hive.name,
            toolCallID: hive.toolCallID,
            toolCalls: hive.toolCalls.map(ColonyToolCall.init),
            op: hive.op.map(ColonyMessageOp.init)
        )
    }

    var hiveChatMessage: HiveChatMessage {
        HiveChatMessage(
            id: id,
            role: role.hiveChatRole,
            content: content,
            name: name,
            toolCallID: toolCallID,
            toolCalls: toolCalls.map(\.hiveToolCall),
            op: op?.hiveChatMessageOp
        )
    }
}

package extension ColonyInferenceRequest {
    init(_ hive: HiveChatRequest, complexity: Complexity = .automatic) {
        self.init(
            messages: hive.messages.map(ColonyMessage.init),
            tools: hive.tools.map(ColonyToolDefinition.init),
            complexity: complexity,
            modelName: hive.model.isEmpty ? nil : hive.model
        )
    }

    var hiveChatRequest: HiveChatRequest {
        HiveChatRequest(
            model: modelName ?? "",
            messages: messages.map(\.hiveChatMessage),
            tools: tools.map(\.hiveToolDefinition)
        )
    }
}

package extension ColonyInferenceResponse {
    init(_ hive: HiveChatResponse, usage: Usage? = nil, providerID: String? = nil) {
        self.init(
            message: ColonyMessage(hive.message),
            usage: usage,
            providerID: providerID
        )
    }

    var hiveChatResponse: HiveChatResponse {
        HiveChatResponse(message: message.hiveChatMessage)
    }
}
