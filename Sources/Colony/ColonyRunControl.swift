import ColonyCore

public struct ColonyRunStartRequest: Sendable {
    public var input: String
    public var optionsOverride: ColonyRun.Options?

    public init(
        input: String,
        optionsOverride: ColonyRun.Options? = nil
    ) {
        self.input = input
        self.optionsOverride = optionsOverride
    }
}

public struct ColonyRunResumeRequest: Sendable {
    public var interruptID: ColonyInterruptID
    public var decision: ColonyToolApprovalDecision
    public var optionsOverride: ColonyRun.Options?

    public init(
        interruptID: ColonyInterruptID,
        decision: ColonyToolApprovalDecision,
        optionsOverride: ColonyRun.Options? = nil
    ) {
        self.interruptID = interruptID
        self.decision = decision
        self.optionsOverride = optionsOverride
    }
}

public struct ColonyRunControl: Sendable {
    public let threadID: ColonyThreadID
    public let options: ColonyRun.Options

    private let engine: ColonyRuntimeEngine

    package init(
        threadID: ColonyThreadID,
        engine: ColonyRuntimeEngine,
        options: ColonyRun.Options
    ) {
        self.threadID = threadID
        self.engine = engine
        self.options = options
    }

    public func start(_ request: ColonyRunStartRequest) async -> ColonyRun.Handle {
        await engine.start(input: request.input, options: request.optionsOverride ?? options)
    }

    public func resume(_ request: ColonyRunResumeRequest) async -> ColonyRun.Handle {
        await engine.resume(
            interruptID: request.interruptID,
            decision: request.decision,
            options: request.optionsOverride ?? options
        )
    }
}
