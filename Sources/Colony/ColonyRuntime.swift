import HiveCore
import ColonyCore

public struct ColonyRuntime: Sendable {
    public let runControl: ColonyRunControl

    public var threadID: HiveThreadID { runControl.threadID }
    public var runtime: HiveRuntime<ColonySchema> { runControl.runtime }
    public var options: HiveRunOptions { runControl.options }

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

    public func sendUserMessage(_ text: String) async -> HiveRunHandle<ColonySchema> {
        await runControl.start(.init(input: text))
    }

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
