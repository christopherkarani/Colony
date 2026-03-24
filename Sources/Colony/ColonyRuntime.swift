import HiveCore
import ColonyCore

/// The main runtime wrapper for Colony agent execution.
///
/// `ColonyRuntime` wraps a `HiveRuntime<ColonySchema>` and provides a high-level
/// API for running Colony agents. It manages the agent lifecycle including
/// starting new runs, resuming from interruptions, and handling tool approvals.
///
/// Use `ColonyRuntime` to:
/// - Start new agent runs with `sendUserMessage()`
/// - Resume from tool approval interruptions with `resumeToolApproval()`
/// - Access the underlying `runControl` for advanced control
///
/// Example:
/// ```swift
/// let runtime = try Colony.start(modelName: "llama3.2")
/// let handle = await runtime.sendUserMessage("Hello, Colony!")
/// let outcome = try await handle.outcome.value
/// ```
public struct ColonyRuntime: Sendable {
    /// The underlying run control handle for this runtime.
    public let runControl: ColonyRunControl

    /// The thread ID for this runtime's conversation.
    public var threadID: HiveThreadID { runControl.threadID }

    /// The underlying Hive runtime.
    public var runtime: HiveRuntime<ColonySchema> { runControl.runtime }

    /// Run options controlling execution behavior.
    public var options: HiveRunOptions { runControl.options }

    /// Creates a new runtime with the specified run control.
    ///
    /// - Parameter runControl: The run control handle to wrap.
    public init(
        threadID: HiveThreadID,
        runtime: HiveRuntime<ColonySchema>,
        options: HiveRunOptions
    ) {
        self.runControl = ColonyRunControl(
            threadID: threadID,
            runtime: runtime,
            options: options
        )
    }

    public init(runControl: ColonyRunControl) {
        self.runControl = runControl
    }

    /// Sends a user message to the agent and starts a new run.
    ///
    /// This method creates a new run with the given input text and returns
    /// a handle that can be used to observe the run's progress and outcome.
    ///
    /// - Parameter text: The user's message to send to the agent.
    /// - Returns: A handle for the started run.
    public func sendUserMessage(_ text: String) async -> HiveRunHandle<ColonySchema> {
        await runControl.start(.init(input: text))
    }

    /// Resumes the runtime after a tool approval interruption.
    ///
    /// Call this method when the run was interrupted for tool approval
    /// and the user has made a decision about which tools to approve.
    ///
    /// - Parameters:
    ///   - interruptID: The ID of the interruption to resume from.
    ///   - decision: The user's decision about the pending tool calls.
    /// - Returns: A handle for the resumed run.
    public func resumeToolApproval(
        interruptID: HiveInterruptID,
        decision: ColonyToolApprovalDecision
    ) async -> HiveRunHandle<ColonySchema> {
        await runControl.resume(
            .init(
                interruptID: interruptID,
                decision: decision
            )
        )
    }

    /// Resumes the runtime after a tool approval interruption with per-tool decisions.
    ///
    /// This overload allows specifying individual decisions for each tool call
    /// by tool call ID rather than a single decision for all calls.
    ///
    /// - Parameters:
    ///   - interruptID: The ID of the interruption to resume from.
    ///   - perToolDecisions: A dictionary mapping tool call IDs to their decisions.
    /// - Returns: A handle for the resumed run.
    public func resumeToolApproval(
        interruptID: HiveInterruptID,
        perToolDecisions: [String: ColonyPerToolApprovalDecision]
    ) async -> HiveRunHandle<ColonySchema> {
        await resumeToolApproval(
            interruptID: interruptID,
            decision: .perTool(
                perToolDecisions
                    .map { ColonyPerToolApproval(toolCallID: $0.key, decision: $0.value) }
                    .sorted { $0.toolCallID.utf8.lexicographicallyPrecedes($1.toolCallID.utf8) }
            )
        )
    }
}
