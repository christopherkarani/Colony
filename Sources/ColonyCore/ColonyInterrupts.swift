/// Payload attached to an interrupt when the runtime pauses for human input.
///
/// `ColonyInterruptPayload` describes why the runtime interrupted its execution
/// and what information is needed to resume.
public enum ColonyInterruptPayload: Codable, Sendable {
    /// Runtime paused because tool approval is required before execution.
    ///
    /// Contains the list of tool calls that need approval.
    case toolApprovalRequired(toolCalls: [ColonyToolCall])
}

/// Payload attached to a resume operation to continue interrupted execution.
///
/// `ColonyResumePayload` provides the data needed to continue from an interrupt.
public enum ColonyResumePayload: Codable, Sendable {
    /// Resume after a tool approval decision.
    ///
    /// Contains the approval decision for the pending tool calls.
    case toolApproval(decision: ColonyToolApprovalDecision)
}
