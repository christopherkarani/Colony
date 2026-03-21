import HiveCore
import ColonyCore

public struct ColonyRuntime: Sendable {
    package let runControl: ColonyRunControl

    public var threadID: ColonyThreadID { ColonyThreadID(runControl.threadID) }
    public var options: ColonyRun.Options { ColonyRun.Options(runControl.options) }

    package init(
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

    package init(runControl: ColonyRunControl) {
        self.runControl = runControl
    }

    public func sendUserMessage(
        _ text: String,
        optionsOverride: ColonyRun.Options? = nil
    ) async -> ColonyRun.Handle {
        let handle = await runControl.startRaw(input: text, optionsOverride: optionsOverride?.hive)
        return makePublicHandle(from: handle)
    }

    public func resumeToolApproval(
        interruptID: ColonyInterruptID,
        decision: ColonyToolApproval.Decision,
        optionsOverride: ColonyRun.Options? = nil
    ) async -> ColonyRun.Handle {
        let handle = await runControl.resumeRaw(
            interruptID: interruptID.hive,
            decision: decision,
            optionsOverride: optionsOverride?.hive
        )
        return makePublicHandle(from: handle)
    }

    public func resumeToolApproval(
        interruptID: ColonyInterruptID,
        perToolDecisions: [ColonyToolCallID: ColonyToolApproval.PerToolDecision],
        optionsOverride: ColonyRun.Options? = nil
    ) async -> ColonyRun.Handle {
        await resumeToolApproval(
            interruptID: interruptID,
            decision: .perTool(
                perToolDecisions
                    .map { ColonyToolApproval.PerToolEntry(toolCallID: $0.key, decision: $0.value) }
                    .sorted { $0.toolCallID.rawValue.utf8.lexicographicallyPrecedes($1.toolCallID.rawValue.utf8) }
            ),
            optionsOverride: optionsOverride
        )
    }

    package func sendUserMessageRaw(_ text: String, optionsOverride: HiveRunOptions? = nil) async -> HiveRunHandle<ColonySchema> {
        await runControl.startRaw(input: text, optionsOverride: optionsOverride)
    }

    package func resumeToolApprovalRaw(
        interruptID: HiveInterruptID,
        decision: ColonyToolApproval.Decision,
        optionsOverride: HiveRunOptions? = nil
    ) async -> HiveRunHandle<ColonySchema> {
        await runControl.resumeRaw(
            interruptID: interruptID,
            decision: decision,
            optionsOverride: optionsOverride
        )
    }

    private func makePublicHandle(from handle: HiveRunHandle<ColonySchema>) -> ColonyRun.Handle {
        ColonyRun.Handle(
            runID: ColonyRunID(handle.runID.rawValue.uuidString),
            attemptID: ColonyAttemptID(handle.attemptID.rawValue.uuidString),
            outcome: Task {
                try await Self.mapOutcome(handle.outcome.value)
            }
        )
    }

    private static func mapOutcome(_ outcome: HiveRunOutcome<ColonySchema>) throws -> ColonyRun.Outcome {
        switch outcome {
        case let .finished(output, checkpointID):
            return .finished(
                transcript: try transcript(from: output),
                checkpointID: checkpointID.map { ColonyCheckpointID($0.rawValue) }
            )
        case let .interrupted(interruption):
            let toolCalls: [ColonyTool.Call]
            switch interruption.interrupt.payload {
            case .toolApprovalRequired(let rawToolCalls):
                toolCalls = rawToolCalls
            }

            return .interrupted(
                ColonyRun.Interruption(
                    interruptID: ColonyInterruptID(interruption.interrupt.id),
                    toolCalls: toolCalls,
                    checkpointID: ColonyCheckpointID(interruption.checkpointID.rawValue)
                )
            )
        case let .cancelled(output, checkpointID):
            return .cancelled(
                transcript: try transcript(from: output),
                checkpointID: checkpointID.map { ColonyCheckpointID($0.rawValue) }
            )
        case let .outOfSteps(maxSteps, output, checkpointID):
            return .outOfSteps(
                maxSteps: maxSteps,
                transcript: try transcript(from: output),
                checkpointID: checkpointID.map { ColonyCheckpointID($0.rawValue) }
            )
        }
    }

    private static func transcript(from output: HiveRunOutput<ColonySchema>) throws -> ColonyRun.Transcript {
        switch output {
        case .fullStore(let store):
            return ColonyRun.Transcript(
                messages: try store.get(ColonySchema.Channels.messages).map(ColonyChatMessage.init),
                finalAnswer: try store.get(ColonySchema.Channels.finalAnswer),
                todos: try store.get(ColonySchema.Channels.todos)
            )
        case .channels(let values):
            var messages: [ColonyChatMessage] = []
            var finalAnswer: String?
            var todos: [ColonyTodo] = []

            for value in values {
                switch value.id.rawValue {
                case ColonySchema.Channels.messages.id.rawValue:
                    if let raw = value.value as? [HiveChatMessage] {
                        messages = raw.map(ColonyChatMessage.init)
                    }
                case ColonySchema.Channels.finalAnswer.id.rawValue:
                    finalAnswer = value.value as? String
                case ColonySchema.Channels.todos.id.rawValue:
                    if let raw = value.value as? [ColonyTodo] {
                        todos = raw
                    }
                default:
                    continue
                }
            }

            return ColonyRun.Transcript(messages: messages, finalAnswer: finalAnswer, todos: todos)
        }
    }
}
