import Foundation

// MARK: - Model Discovery

struct OllamaTagsResponse: Decodable, Sendable {
    let models: [OllamaModelInfo]
}

struct OllamaModelInfo: Identifiable, Decodable, Sendable {
    let name: String
    let size: Int64?
    let digest: String?
    let modifiedAt: String?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, size, digest
        case modifiedAt = "modified_at"
    }
}

// MARK: - Chat Completion

struct OllamaChatRequest: Encodable, Sendable {
    let model: String
    let messages: [OllamaChatMessage]
    let stream: Bool
    let tools: [OllamaToolDef]?
}

struct OllamaChatMessage: Codable, Sendable {
    let role: String
    let content: String
    let toolCalls: [OllamaToolCallWrapper]?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
    }
}

struct OllamaToolCallWrapper: Codable, Sendable {
    let function: OllamaToolCallFunction
}

struct OllamaToolCallFunction: Codable, Sendable {
    let name: String
    let arguments: [String: OllamaJSONValue]
}

struct OllamaToolDef: Encodable, Sendable {
    let type: String = "function"
    let function: OllamaToolFunction
}

struct OllamaToolFunction: Encodable, Sendable {
    let name: String
    let description: String
    let parameters: OllamaJSONValue
}

// MARK: - Streaming Chunk

struct OllamaChatChunk: Decodable, Sendable {
    let message: OllamaChatChunkMessage
    let done: Bool
}

struct OllamaChatChunkMessage: Decodable, Sendable {
    let role: String?
    let content: String
    let toolCalls: [OllamaToolCallWrapper]?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
    }
}

// MARK: - Flexible JSON Value

enum OllamaJSONValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([OllamaJSONValue])
    case object([String: OllamaJSONValue])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self) { self = .string(v) }
        else if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode(Double.self) { self = .double(v) }
        else if let v = try? container.decode([OllamaJSONValue].self) { self = .array(v) }
        else if let v = try? container.decode([String: OllamaJSONValue].self) { self = .object(v) }
        else { self = .null }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .null: try container.encodeNil()
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }

    static func from(jsonString: String) -> OllamaJSONValue {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return .object([:])
        }
        return from(any: json)
    }

    static func from(any value: Any) -> OllamaJSONValue {
        switch value {
        case let string as String: return .string(string)
        case let bool as Bool: return .bool(bool)
        case let int as Int: return .int(int)
        case let double as Double: return .double(double)
        case let array as [Any]: return .array(array.map { from(any: $0) })
        case let dict as [String: Any]: return .object(dict.mapValues { from(any: $0) })
        default: return .null
        }
    }
}
