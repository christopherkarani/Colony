import HiveCore
import ColonyCore

package struct ColonyRunControl: Sendable {
    package let threadID: HiveThreadID
    package let runtime: HiveRuntime<ColonySchema>
    package let options: HiveRunOptions

    package init(
        threadID: HiveThreadID,
        runtime: HiveRuntime<ColonySchema>,
        options: HiveRunOptions
    ) {
        self.threadID = threadID
        self.runtime = runtime
        self.options = options
    }

    package func startRaw(input: String, optionsOverride: HiveRunOptions? = nil) async -> HiveRunHandle<ColonySchema> {
        let effectiveOptions = optionsOverride ?? options
        return await runtime.run(
            threadID: threadID,
            input: input,
            options: effectiveOptions
        )
    }

    package func start(_ request: ColonyRun.StartRequest) async -> HiveRunHandle<ColonySchema> {
        await startRaw(input: request.input, optionsOverride: request.optionsOverride?.hive)
    }

    package func resumeRaw(
        interruptID: HiveInterruptID,
        decision: ColonyToolApproval.Decision,
        optionsOverride: HiveRunOptions? = nil
    ) async -> HiveRunHandle<ColonySchema> {
        let effectiveOptions = optionsOverride ?? options
        return await runtime.resume(
            threadID: threadID,
            interruptID: interruptID,
            payload: .toolApproval(decision: decision),
            options: effectiveOptions
        )
    }

    package func resume(_ request: ColonyRun.ResumeRequest) async -> HiveRunHandle<ColonySchema> {
        await resumeRaw(
            interruptID: request.interruptID.hive,
            decision: request.decision,
            optionsOverride: request.optionsOverride?.hive
        )
    }
}
