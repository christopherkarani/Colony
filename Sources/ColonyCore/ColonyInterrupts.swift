public enum ColonyInterruptPayload: Codable, Sendable {
    case toolApprovalRequired(toolCalls: [ColonyToolCall])
}

public enum ColonyResumePayload: Codable, Sendable {
    case toolApproval(decision: ColonyToolApprovalDecision)
}
