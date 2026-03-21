public enum ColonyInterruptPayload: Codable, Sendable {
    case toolApprovalRequired(toolCalls: [ColonyTool.Call])
}

public enum ColonyResumePayload: Codable, Sendable {
    case toolApproval(decision: ColonyToolApproval.Decision)
}
