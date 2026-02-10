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
