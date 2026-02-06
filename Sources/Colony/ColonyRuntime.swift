import HiveCore
import ColonyCore

public struct ColonyRuntime: Sendable {
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

    public func sendUserMessage(_ text: String) async -> HiveRunHandle<ColonySchema> {
        await runtime.run(threadID: threadID, input: text, options: options)
    }

    public func resumeToolApproval(
        interruptID: HiveInterruptID,
        decision: ColonyToolApprovalDecision
    ) async -> HiveRunHandle<ColonySchema> {
        await runtime.resume(
            threadID: threadID,
            interruptID: interruptID,
            payload: .toolApproval(decision: decision),
            options: options
        )
    }
}

