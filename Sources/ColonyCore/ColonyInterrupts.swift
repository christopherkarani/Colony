import HiveCore

public enum ColonyInterruptPayload: Codable, Sendable {
    case toolApprovalRequired(toolCalls: [HiveToolCall])
}

public enum ColonyResumePayload: Codable, Sendable {
    case toolApproval(decision: ColonyToolApprovalDecision)
}
