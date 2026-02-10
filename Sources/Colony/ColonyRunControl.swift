import HiveCore
import ColonyCore

public struct ColonyRunStartRequest: Sendable {
    public var input: String
    public var optionsOverride: HiveRunOptions?

    public init(
        input: String,
        optionsOverride: HiveRunOptions? = nil
    ) {
        self.input = input
        self.optionsOverride = optionsOverride
    }
}

public struct ColonyRunResumeRequest: Sendable {
    public var interruptID: HiveInterruptID
    public var decision: ColonyToolApprovalDecision
    public var optionsOverride: HiveRunOptions?

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

public struct ColonyRunControl: Sendable {
    public let threadID: HiveThreadID
    public let runtime: HiveRuntime<ColonySchema>
    public let options: HiveRunOptions

    public init(
        threadID: HiveThreadID,
        runtime: HiveRuntime<ColonySchema>,
        options: HiveRunOptions
    ) {
        self.threadID = threadID
        self.runtime = runtime
        self.options = options
    }

    public func start(_ request: ColonyRunStartRequest) async -> HiveRunHandle<ColonySchema> {
        let effectiveOptions = request.optionsOverride ?? options
        return await runtime.run(
            threadID: threadID,
            input: request.input,
            options: effectiveOptions
        )
    }

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
