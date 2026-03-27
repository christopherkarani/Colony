import ColonyCore

public struct ColonyRuntime: Sendable {
    public let runControl: ColonyRunControl

    public var threadID: ColonyThreadID { runControl.threadID }
    public var options: ColonyRun.Options { runControl.options }

    package init(
        threadID: ColonyThreadID,
        engine: ColonyRuntimeEngine,
        options: ColonyRun.Options
    ) {
        runControl = ColonyRunControl(
            threadID: threadID,
            engine: engine,
            options: options
        )
    }

    package init(runControl: ColonyRunControl) {
        self.runControl = runControl
    }

    public func sendUserMessage(_ text: String) async -> ColonyRun.Handle {
        await runControl.start(.init(input: text))
    }

    public func resumeToolApproval(
        interruptID: ColonyInterruptID,
        decision: ColonyToolApprovalDecision
    ) async -> ColonyRun.Handle {
        await runControl.resume(
            .init(
                interruptID: interruptID,
                decision: decision
            )
        )
    }

    public func resumeToolApproval(
        interruptID: ColonyInterruptID,
        perToolDecisions: [String: ColonyPerToolApprovalDecision]
    ) async -> ColonyRun.Handle {
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
