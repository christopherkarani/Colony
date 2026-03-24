import HiveCore
import ColonyCore

/// Request to start a new Colony run with a user message.
///
/// Contains the input text and optional runtime options override.
public struct ColonyRunStartRequest: Sendable {
    /// The user's message to send to the agent.
    public var input: String

    /// Optional override for runtime options. If nil, uses runtime defaults.
    public var optionsOverride: HiveRunOptions?

    /// Creates a new start request.
    ///
    /// - Parameters:
    ///   - input: The user's message.
    ///   - optionsOverride: Optional runtime options override.
    public init(
        input: String,
        optionsOverride: HiveRunOptions? = nil
    ) {
        self.input = input
        self.optionsOverride = optionsOverride
    }
}

/// Request to resume a Colony run after an interruption.
///
/// Contains the interruption ID, the user's decision about tool approvals,
/// and optional runtime options override.
public struct ColonyRunResumeRequest: Sendable {
    /// The ID of the interruption to resume from.
    public var interruptID: HiveInterruptID

    /// The user's decision about the pending tool calls.
    public var decision: ColonyToolApprovalDecision

    /// Optional override for runtime options. If nil, uses runtime defaults.
    public var optionsOverride: HiveRunOptions?

    /// Creates a new resume request.
    ///
    /// - Parameters:
    ///   - interruptID: The interruption ID.
    ///   - decision: The tool approval decision.
    ///   - optionsOverride: Optional runtime options override.
    public init(
        interruptID: HiveInterruptID,
        decision: ColonyToolApprovalDecision,
        optionsOverride: HiveRunOptions? = nil
    ) {
        self.interruptID = interruptID
        self.decision = decision
        self.optionsOverride = optionsOverride
    }
}

/// Low-level control handle for Colony runtime execution.
///
/// `ColonyRunControl` manages the lifecycle of Colony runs including
/// starting new runs and resuming from interruptions. It wraps the
/// underlying Hive runtime with Colony-specific logic.
public struct ColonyRunControl: Sendable {
    /// The thread ID for this run's conversation.
    public let threadID: HiveThreadID

    /// The underlying Hive runtime.
    public let runtime: HiveRuntime<ColonySchema>

    /// Default run options.
    public let options: HiveRunOptions

    /// Creates a new run control handle.
    ///
    /// - Parameters:
    ///   - threadID: The thread ID for the conversation.
    ///   - runtime: The underlying Hive runtime.
    ///   - options: Default run options.
    public init(
        threadID: HiveThreadID,
        runtime: HiveRuntime<ColonySchema>,
        options: HiveRunOptions
    ) {
        self.threadID = threadID
        self.runtime = runtime
        self.options = options
    }

    /// Starts a new run with the given request.
    ///
    /// - Parameter request: The start request containing the input message.
    /// - Returns: A handle for the started run.
    public func start(_ request: ColonyRunStartRequest) async -> HiveRunHandle<ColonySchema> {
        let effectiveOptions = request.optionsOverride ?? options
        return await runtime.run(
            threadID: threadID,
            input: request.input,
            options: effectiveOptions
        )
    }

    /// Resumes a run after an interruption.
    ///
    /// - Parameter request: The resume request containing interruption ID and decision.
    /// - Returns: A handle for the resumed run.
    public func resume(_ request: ColonyRunResumeRequest) async -> HiveRunHandle<ColonySchema> {
        let effectiveOptions = request.optionsOverride ?? options
        return await runtime.resume(
            threadID: threadID,
            interruptID: request.interruptID,
            payload: .toolApproval(decision: request.decision),
            options: effectiveOptions
        )
    }
}
