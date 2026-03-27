import Foundation
import Swarm

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
    init(_ schema: ToolSchema) {
        self.init(
            name: schema.name,
            description: schema.description,
            parametersJSONSchema: ColonyInferenceBridge.encodeJSONSchema(parameters: schema.parameters)
        )
    }

    var toolSchema: ToolSchema {
        ToolSchema(
            name: name,
            description: description,
            parameters: ColonyInferenceBridge.decodeJSONSchema(parametersJSONSchema)
        )
    }
}

package extension ColonyToolCall {
    init(_ toolCall: InferenceResponse.ParsedToolCall) {
        self.init(
            id: toolCall.id ?? UUID().uuidString,
            name: toolCall.name,
            argumentsJSON: ColonyInferenceBridge.encodeArguments(toolCall.arguments)
        )
    }

    var inferenceToolCall: InferenceResponse.ParsedToolCall {
        InferenceResponse.ParsedToolCall(
            id: id,
            name: name,
            arguments: ColonyInferenceBridge.decodeArguments(argumentsJSON)
        )
    }

    var inferenceMessageToolCall: InferenceMessage.ToolCall {
        InferenceMessage.ToolCall(
            id: id,
            name: name,
            arguments: ColonyInferenceBridge.decodeArguments(argumentsJSON)
        )
    }
}

package extension ColonyMessageRole {
    init(_ role: InferenceMessage.Role) {
        self = ColonyMessageRole(rawValue: role.rawValue) ?? .assistant
    }

    var inferenceRole: InferenceMessage.Role {
        InferenceMessage.Role(rawValue: rawValue) ?? .assistant
    }
}

package extension ColonyMessage {
    init(_ message: InferenceMessage, id: String = UUID().uuidString) {
        self.init(
            id: id,
            role: ColonyMessageRole(message.role),
            content: message.content,
            name: message.name,
            toolCallID: message.toolCallID,
            toolCalls: message.toolCalls.map { ColonyToolCall(id: $0.id ?? UUID().uuidString, name: $0.name, argumentsJSON: ColonyInferenceBridge.encodeArguments($0.arguments)) },
            op: nil
        )
    }

    var inferenceMessage: InferenceMessage {
        InferenceMessage(
            role: role.inferenceRole,
            content: content,
            name: name,
            toolCallID: toolCallID,
            toolCalls: toolCalls.map(\.inferenceMessageToolCall)
        )
    }
}

package extension ColonyInferenceRequest {
    init(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        complexity: Complexity = .automatic,
        modelName: String? = nil
    ) {
        self.init(
            messages: messages.map { ColonyMessage($0) },
            tools: tools.map { ColonyToolDefinition($0) },
            complexity: complexity,
            modelName: modelName
        )
    }

    var inferenceMessages: [InferenceMessage] {
        messages.map(\.inferenceMessage)
    }

    var toolSchemas: [ToolSchema] {
        tools.map(\.toolSchema)
    }
}

package extension ColonyInferenceResponse {
    init(_ response: InferenceResponse, providerID: String? = nil, messageID: String = UUID().uuidString) {
        self.init(
            message: ColonyMessage(
                id: messageID,
                role: .assistant,
                content: response.content ?? "",
                toolCalls: response.toolCalls.map(ColonyToolCall.init)
            ),
            usage: response.usage.map(Usage.init),
            providerID: providerID
        )
    }

    var inferenceResponse: InferenceResponse {
        InferenceResponse(
            content: message.content.isEmpty ? nil : message.content,
            toolCalls: message.toolCalls.map(\.inferenceToolCall),
            finishReason: message.toolCalls.isEmpty ? .completed : .toolCall,
            usage: usage.map(\.tokenUsage)
        )
    }
}

package extension ColonyInferenceResponse.Usage {
    init(_ usage: TokenUsage) {
        self.init(
            promptTokens: usage.inputTokens,
            completionTokens: usage.outputTokens
        )
    }

    var tokenUsage: TokenUsage {
        TokenUsage(
            inputTokens: promptTokens,
            outputTokens: completionTokens
        )
    }
}

private enum ColonyInferenceBridge {
    static func encodeArguments(_ arguments: [String: SendableValue]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(arguments),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }

    static func decodeArguments(_ argumentsJSON: String) -> [String: SendableValue] {
        guard let data = argumentsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: SendableValue].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    static func decodeJSONSchema(_ parametersJSONSchema: String) -> [ToolParameter] {
        guard let data = parametersJSONSchema.data(using: .utf8),
              let schema = try? JSONDecoder().decode([String: SendableValue].self, from: data),
              let properties = schema["properties"]?.dictionaryValue
        else {
            return []
        }

        let required = Set(
            schema["required"]?.arrayValue?.compactMap(\.stringValue) ?? []
        )

        return properties.keys.sorted().compactMap { name in
            guard let definition = properties[name]?.dictionaryValue else {
                return nil
            }
            return decodeParameter(
                name: name,
                definition: definition,
                required: required.contains(name)
            )
        }
    }

    static func encodeJSONSchema(parameters: [ToolParameter]) -> String {
        let properties = parameters.reduce(into: [String: SendableValue]()) { partial, parameter in
            partial[parameter.name] = encodeParameter(parameter)
        }

        var schema: [String: SendableValue] = [
            "type": "object",
            "properties": .dictionary(properties),
        ]

        let required = parameters
            .filter(\.isRequired)
            .map(\.name)
            .map { SendableValue($0) }

        if required.isEmpty == false {
            schema["required"] = .array(required)
        }

        return encodeArguments(schema)
    }

    private static func decodeParameter(
        name: String,
        definition: [String: SendableValue],
        required: Bool
    ) -> ToolParameter {
        let description = definition["description"]?.stringValue ?? ""
        let defaultValue = definition["default"]
        let type = decodeParameterType(definition)

        return ToolParameter(
            name: name,
            description: description,
            type: type,
            isRequired: required,
            defaultValue: defaultValue
        )
    }

    private static func decodeParameterType(_ definition: [String: SendableValue]) -> ToolParameter.ParameterType {
        if let enumValues = definition["enum"]?.arrayValue?.compactMap(\.stringValue),
           enumValues.isEmpty == false
        {
            return .oneOf(enumValues)
        }

        switch definition["type"]?.stringValue {
        case "string":
            return .string
        case "integer":
            return .int
        case "number":
            return .double
        case "boolean":
            return .bool
        case "array":
            let element = definition["items"]?.dictionaryValue ?? [:]
            return .array(elementType: decodeParameterType(element))
        case "object":
            let properties = definition["properties"]?.dictionaryValue ?? [:]
            let required = Set(definition["required"]?.arrayValue?.compactMap(\.stringValue) ?? [])
            let nested: [ToolParameter] = properties.keys.sorted().compactMap { key in
                guard let nestedDefinition = properties[key]?.dictionaryValue else {
                    return nil
                }
                return decodeParameter(
                    name: key,
                    definition: nestedDefinition,
                    required: required.contains(key)
                )
            }
            return .object(properties: nested)
        default:
            return .any
        }
    }

    private static func encodeParameter(_ parameter: ToolParameter) -> SendableValue {
        var payload: [String: SendableValue] = [
            "description": .string(parameter.description),
        ]

        switch parameter.type {
        case .string:
            payload["type"] = "string"
        case .int:
            payload["type"] = "integer"
        case .double:
            payload["type"] = "number"
        case .bool:
            payload["type"] = "boolean"
        case .array(let elementType):
            payload["type"] = "array"
            payload["items"] = encodeParameterType(elementType)
        case .object(let properties):
            payload["type"] = "object"
            payload["properties"] = .dictionary(
                properties.reduce(into: [String: SendableValue]()) { partial, nested in
                    partial[nested.name] = encodeParameter(nested)
                }
            )
            let required = properties.filter(\.isRequired).map(\.name).map { SendableValue($0) }
            if required.isEmpty == false {
                payload["required"] = .array(required)
            }
        case .oneOf(let options):
            payload["type"] = "string"
            payload["enum"] = .array(options.map { SendableValue($0) })
        case .any:
            break
        }

        if let defaultValue = parameter.defaultValue {
            payload["default"] = defaultValue
        }

        return .dictionary(payload)
    }

    private static func encodeParameterType(_ type: ToolParameter.ParameterType) -> SendableValue {
        switch type {
        case .string:
            return ["type": "string"]
        case .int:
            return ["type": "integer"]
        case .double:
            return ["type": "number"]
        case .bool:
            return ["type": "boolean"]
        case .array(let elementType):
            return [
                "type": "array",
                "items": encodeParameterType(elementType),
            ]
        case .object(let properties):
            var payload: [String: SendableValue] = [
                "type": "object",
                "properties": .dictionary(
                    properties.reduce(into: [String: SendableValue]()) { partial, nested in
                        partial[nested.name] = encodeParameter(nested)
                    }
                ),
            ]
            let required = properties.filter(\.isRequired).map(\.name).map { SendableValue($0) }
            if required.isEmpty == false {
                payload["required"] = .array(required)
            }
            return .dictionary(payload)
        case .oneOf(let options):
            return [
                "type": "string",
                "enum": .array(options.map { SendableValue($0) }),
            ]
        case .any:
            return [:]
        }
    }
}
