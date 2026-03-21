// MARK: - Namespace

public enum ColonyToolApproval {}

// MARK: - ColonyToolApproval.PerToolDecision

extension ColonyToolApproval {
    public enum PerToolDecision: String, Codable, Sendable, Equatable {
        case approved
        case rejected
        case cancelled
    }
}

// MARK: - ColonyToolApproval.PerToolEntry

extension ColonyToolApproval {
    public struct PerToolEntry: Codable, Sendable, Equatable {
        public var toolCallID: ColonyToolCallID
        public var decision: PerToolDecision

        public init(toolCallID: ColonyToolCallID, decision: PerToolDecision) {
            self.toolCallID = toolCallID
            self.decision = decision
        }

        private enum CodingKeys: String, CodingKey {
            case toolCallID = "tool_call_id"
            case decision
        }
    }
}

// MARK: - ColonyToolApproval.Decision

extension ColonyToolApproval {
    public enum Decision: Codable, Sendable, Equatable {
        case approved
        case rejected
        case cancelled
        case perTool([PerToolEntry])

        public static func perTool(_ decisions: [ColonyToolCallID: PerToolDecision]) -> Decision {
            let normalized = decisions
                .map { PerToolEntry(toolCallID: $0.key, decision: $0.value) }
                .sorted { $0.toolCallID.rawValue.utf8.lexicographicallyPrecedes($1.toolCallID.rawValue.utf8) }
            return .perTool(normalized)
        }

        public func decision(forToolCallID toolCallID: ColonyToolCallID) -> PerToolDecision? {
            switch self {
            case .approved:
                return .approved
            case .rejected:
                return .rejected
            case .cancelled:
                return .cancelled
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
            case cancelled
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
                case Kind.cancelled.rawValue:
                    self = .cancelled
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
            case .cancelled:
                self = .cancelled
            case .perTool:
                self = .perTool(try container.decode([PerToolEntry].self, forKey: .decisions))
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
            case .cancelled:
                var single = encoder.singleValueContainer()
                try single.encode(Kind.cancelled.rawValue)
            case .perTool(let decisions):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(Kind.perTool, forKey: .kind)
                try container.encode(decisions, forKey: .decisions)
            }
        }
    }
}

// MARK: - ColonyToolApproval.Policy

extension ColonyToolApproval {
    public enum Policy: Sendable {
        case never
        case always
        case allowList(Set<ColonyTool.Name>)

        public static func allowList(_ allowed: [ColonyTool.Name]) -> Policy {
            .allowList(Set(allowed))
        }

        public func requiresApproval(for toolName: ColonyTool.Name) -> Bool {
            switch self {
            case .never:
                return false
            case .always:
                return true
            case .allowList(let allowed):
                return allowed.contains(toolName) == false
            }
        }

        public func requiresApproval(for toolCalls: [ColonyTool.Name]) -> Bool {
            toolCalls.contains(where: requiresApproval(for:))
        }
    }
}

