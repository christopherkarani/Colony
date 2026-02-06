public enum ColonyToolApprovalDecision: String, Codable, Sendable {
    case approved
    case rejected
}

public enum ColonyToolApprovalPolicy: Sendable {
    case never
    case always
    case allowList(Set<String>)

    public static func allowList(_ allowed: [String]) -> ColonyToolApprovalPolicy {
        .allowList(Set(allowed))
    }

    public func requiresApproval(for toolCalls: [String]) -> Bool {
        switch self {
        case .never:
            return false
        case .always:
            return !toolCalls.isEmpty
        case .allowList(let allowed):
            return toolCalls.contains { allowed.contains($0) == false }
        }
    }
}

