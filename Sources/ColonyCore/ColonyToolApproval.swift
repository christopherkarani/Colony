public enum ColonyPerToolApprovalDecision: String, Codable, Sendable, Equatable {
    case approved
    case rejected
}

public struct ColonyPerToolApproval: Codable, Sendable, Equatable {
    public var toolCallID: String
    public var decision: ColonyPerToolApprovalDecision

    public init(toolCallID: String, decision: ColonyPerToolApprovalDecision) {
        self.toolCallID = toolCallID
        self.decision = decision
    }

    private enum CodingKeys: String, CodingKey {
        case toolCallID = "tool_call_id"
        case decision
    }
}

public enum ColonyToolApprovalDecision: Codable, Sendable, Equatable {
    case approved
    case rejected
    case perTool([ColonyPerToolApproval])

    public static func perTool(_ decisions: [String: ColonyPerToolApprovalDecision]) -> ColonyToolApprovalDecision {
        let normalized = decisions
            .map { ColonyPerToolApproval(toolCallID: $0.key, decision: $0.value) }
            .sorted { $0.toolCallID.utf8.lexicographicallyPrecedes($1.toolCallID.utf8) }
        return .perTool(normalized)
    }

    public func decision(forToolCallID toolCallID: String) -> ColonyPerToolApprovalDecision? {
        switch self {
        case .approved:
            return .approved
        case .rejected:
            return .rejected
        case .perTool(let decisions):
            return decisions.last(where: { $0.toolCallID == toolCallID })?.decision
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case decisions
    }

    private enum Kind: String, Codable {
        case approved
        case rejected
        case perTool = "per_tool"
    }

    public init(from decoder: any Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let raw = try? single.decode(String.self)
        {
            switch raw {
            case Kind.approved.rawValue:
                self = .approved
                return
            case Kind.rejected.rawValue:
                self = .rejected
                return
            default:
                break
            }
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .approved:
            self = .approved
        case .rejected:
            self = .rejected
        case .perTool:
            self = .perTool(try container.decode([ColonyPerToolApproval].self, forKey: .decisions))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .approved:
            var single = encoder.singleValueContainer()
            try single.encode(Kind.approved.rawValue)
        case .rejected:
            var single = encoder.singleValueContainer()
            try single.encode(Kind.rejected.rawValue)
        case .perTool(let decisions):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Kind.perTool, forKey: .kind)
            try container.encode(decisions, forKey: .decisions)
        }
    }
}

public enum ColonyToolApprovalPolicy: Sendable {
    case never
    case always
    case allowList(Set<String>)

    public static func allowList(_ allowed: [String]) -> ColonyToolApprovalPolicy {
        .allowList(Set(allowed))
    }

    public func requiresApproval(for toolName: String) -> Bool {
        switch self {
        case .never:
            return false
        case .always:
            return true
        case .allowList(let allowed):
            return allowed.contains(toolName) == false
        }
    }

    public func requiresApproval(for toolCalls: [String]) -> Bool {
        toolCalls.contains(where: requiresApproval(for:))
    }
}
