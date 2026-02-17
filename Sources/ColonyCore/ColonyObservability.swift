/// Observability hooks for Colony agent execution.
///
/// Implement this protocol and set it on ``ColonyConfiguration/observabilityHandler``
/// to receive callbacks at key points in the agent loop. All methods have default
/// no-op implementations so conformers can opt in to only the hooks they need.
public protocol ColonyObservabilityHandler: Sendable {
    /// Called after the model returns a response (successful or not).
    func onModelRequestCompleted(_ event: ColonyModelRequestEvent) async

    /// Called after a tool finishes executing.
    func onToolExecuted(_ event: ColonyToolExecutionEvent) async

    /// Called when the agent loop completes a full turn (model + all tool executions
    /// before re-entering the model node, or producing a final answer).
    func onTurnCompleted(_ event: ColonyTurnEvent) async
}

// Default no-op implementations so conformers only need to implement the hooks they care about.
public extension ColonyObservabilityHandler {
    func onModelRequestCompleted(_ event: ColonyModelRequestEvent) async {}
    func onToolExecuted(_ event: ColonyToolExecutionEvent) async {}
    func onTurnCompleted(_ event: ColonyTurnEvent) async {}
}

/// Payload delivered to ``ColonyObservabilityHandler/onModelRequestCompleted(_:)``.
public struct ColonyModelRequestEvent: Sendable {
    /// The model name from the request.
    public let modelName: String
    /// Number of messages sent in the request.
    public let inputMessageCount: Int
    /// Number of tool definitions included in the request.
    public let toolCount: Int
    /// Whether the response contained tool calls (i.e. the loop continues).
    public let hasToolCalls: Bool

    public init(
        modelName: String,
        inputMessageCount: Int,
        toolCount: Int,
        hasToolCalls: Bool
    ) {
        self.modelName = modelName
        self.inputMessageCount = inputMessageCount
        self.toolCount = toolCount
        self.hasToolCalls = hasToolCalls
    }
}

/// Payload delivered to ``ColonyObservabilityHandler/onToolExecuted(_:)``.
public struct ColonyToolExecutionEvent: Sendable {
    /// The tool name that was invoked.
    public let toolName: String
    /// The tool call ID.
    public let toolCallID: String
    /// Whether the tool execution succeeded.
    public let success: Bool

    public init(toolName: String, toolCallID: String, success: Bool) {
        self.toolName = toolName
        self.toolCallID = toolCallID
        self.success = success
    }
}

/// Payload delivered to ``ColonyObservabilityHandler/onTurnCompleted(_:)``.
public struct ColonyTurnEvent: Sendable {
    /// Whether the turn produced a final answer (loop ended).
    public let isFinalAnswer: Bool
    /// Number of tool calls executed in this turn.
    public let toolCallCount: Int

    public init(isFinalAnswer: Bool, toolCallCount: Int) {
        self.isFinalAnswer = isFinalAnswer
        self.toolCallCount = toolCallCount
    }
}
