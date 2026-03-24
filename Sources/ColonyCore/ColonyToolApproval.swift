/// Decision for a single tool call during per-tool approval.
public enum ColonyPerToolApprovalDecision: String, Codable, Sendable, Equatable {
    /// The tool call has been approved for execution.
    case approved
    /// The tool call has been rejected; it will not execute.
    case rejected
}

/// Represents the approval decision for a single tool call.
public struct ColonyPerToolApproval: Codable, Sendable, Equatable {
    /// The unique identifier of the tool call this approval applies to.
    public var toolCallID: String
    /// The approval decision for this tool call.
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

/// Overall tool approval decision from a human-in-the-loop interaction.
///
/// Use `ColonyToolApprovalDecision` to represent the result of an approval
/// session where a user may approve all, reject all, or make per-tool decisions.
public enum ColonyToolApprovalDecision: Codable, Sendable, Equatable {
    /// All tool calls are approved for execution.
    case approved
    /// All tool calls are rejected; no tools will execute.
    case rejected
    /// Per-tool decisions; each tool call has its own approval/rejection.
    case perTool([ColonyPerToolApproval])

    /// Creates a per-tool decision from a dictionary mapping tool call IDs to decisions.
    ///
    /// - Parameter decisions: Dictionary from tool call ID to decision
    /// - Returns: A `ColonyToolApprovalDecision.perTool` value
    public static func perTool(_ decisions: [String: ColonyPerToolApprovalDecision]) -> ColonyToolApprovalDecision {
        let normalized = decisions
            .map { ColonyPerToolApproval(toolCallID: $0.key, decision: $0.value) }
            .sorted { $0.toolCallID.utf8.lexicographicallyPrecedes($1.toolCallID.utf8) }
        return .perTool(normalized)
    }

    /// Returns the decision for a specific tool call ID.
    ///
    /// - Parameter toolCallID: The tool call ID to look up
    /// - Returns: The decision for the tool call, or `nil` if not found
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

/// Policy determining when tool approval is required from a human.
///
/// `ColonyToolApprovalPolicy` controls the human-in-the-loop approval flow:
/// - `.never` — No approval required; all tools execute automatically
/// - `.always` — All tools require approval before execution
/// - `.allowList` — Only tools NOT in the allow list require approval
///
/// Example:
/// ```swift
/// // Default: tools not in the list require approval
/// let policy = ColonyToolApprovalPolicy.allowList(["ls", "read_file", "glob", "grep"])
///
/// // All tools require approval
/// let strictPolicy: ColonyToolApprovalPolicy = .always
///
/// // No approval required
/// let permissivePolicy: ColonyToolApprovalPolicy = .never
/// ```
public enum ColonyToolApprovalPolicy: Sendable {
    /// No tool requires approval; all tools execute automatically.
    case never
    /// Every tool requires approval before execution.
    case always
    /// Only tools NOT in the provided set require approval.
    case allowList(Set<String>)

    /// Convenience factory for creating an allow list from an array.
    ///
    /// - Parameter allowed: List of tool names that do NOT require approval
    /// - Returns: An `.allowList` policy with the provided set
    public static func allowList(_ allowed: [String]) -> ColonyToolApprovalPolicy {
        .allowList(Set(allowed))
    }

    /// Determines whether a specific tool requires approval.
    ///
    /// - Parameter toolName: The name of the tool to check
    /// - Returns: `true` if the tool requires approval
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

    /// Determines whether any of the provided tools require approval.
    ///
    /// - Parameter toolCalls: List of tool names to check
    /// - Returns: `true` if any tool requires approval
    public func requiresApproval(for toolCalls: [String]) -> Bool {
        toolCalls.contains(where: requiresApproval(for:))
    }
}
