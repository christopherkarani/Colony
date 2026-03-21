import HiveCore
import ColonyCore

public struct ColonyRuntime: Sendable {
    package let runControl: ColonyRunControl

    public var threadID: ColonyThreadID { ColonyThreadID(runControl.threadID) }
    public var options: ColonyRunOptions { ColonyRunOptions(runControl.options) }

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
        optionsOverride: ColonyRunOptions? = nil
    ) async -> ColonyRunHandle {
        let handle = await runControl.startRaw(input: text, optionsOverride: optionsOverride?.hive)
        return makePublicHandle(from: handle)
    }

    public func resumeToolApproval(
        interruptID: ColonyInterruptID,
        decision: ColonyToolApprovalDecision,
        optionsOverride: ColonyRunOptions? = nil
    ) async -> ColonyRunHandle {
        let handle = await runControl.resumeRaw(
            interruptID: interruptID.hive,
            decision: decision,
            optionsOverride: optionsOverride?.hive
        )
        return makePublicHandle(from: handle)
    }

    public func resumeToolApproval(
        interruptID: ColonyInterruptID,
        perToolDecisions: [String: ColonyPerToolApprovalDecision],
        optionsOverride: ColonyRunOptions? = nil
    ) async -> ColonyRunHandle {
        await resumeToolApproval(
            interruptID: interruptID,
            decision: .perTool(
                perToolDecisions
                    .map { ColonyPerToolApproval(toolCallID: $0.key, decision: $0.value) }
                    .sorted { $0.toolCallID.utf8.lexicographicallyPrecedes($1.toolCallID.utf8) }
            ),
            optionsOverride: optionsOverride
        )
    }

    package func sendUserMessageRaw(_ text: String, optionsOverride: HiveRunOptions? = nil) async -> HiveRunHandle<ColonySchema> {
        await runControl.startRaw(input: text, optionsOverride: optionsOverride)
    }

    package func resumeToolApprovalRaw(
        interruptID: HiveInterruptID,
        decision: ColonyToolApprovalDecision,
        optionsOverride: HiveRunOptions? = nil
    ) async -> HiveRunHandle<ColonySchema> {
        await runControl.resumeRaw(
            interruptID: interruptID,
            decision: decision,
            optionsOverride: optionsOverride
        )
    }

    private func makePublicHandle(from handle: HiveRunHandle<ColonySchema>) -> ColonyRunHandle {
        ColonyRunHandle(
            runID: handle.runID.rawValue,
            attemptID: handle.attemptID.rawValue,
            outcome: Task {
                try await Self.mapOutcome(handle.outcome.value)
            }
        )
    }

    private static func mapOutcome(_ outcome: HiveRunOutcome<ColonySchema>) throws -> ColonyRunOutcome {
        switch outcome {
        case let .finished(output, checkpointID):
            return .finished(
                transcript: try transcript(from: output),
                checkpointID: checkpointID?.rawValue
            )
        case let .interrupted(interruption):
            let toolCalls: [ColonyToolCall]
            switch interruption.interrupt.payload {
            case .toolApprovalRequired(let rawToolCalls):
                toolCalls = rawToolCalls
            }

            return .interrupted(
                ColonyRunInterruption(
                    interruptID: ColonyInterruptID(interruption.interrupt.id),
                    toolCalls: toolCalls,
                    checkpointID: interruption.checkpointID.rawValue
                )
            )
        case let .cancelled(output, checkpointID):
            return .cancelled(
                transcript: try transcript(from: output),
                checkpointID: checkpointID?.rawValue
            )
        case let .outOfSteps(maxSteps, output, checkpointID):
            return .outOfSteps(
                maxSteps: maxSteps,
                transcript: try transcript(from: output),
                checkpointID: checkpointID?.rawValue
            )
        }
    }

    private static func transcript(from output: HiveRunOutput<ColonySchema>) throws -> ColonyTranscript {
        switch output {
        case .fullStore(let store):
            return ColonyTranscript(
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

            return ColonyTranscript(messages: messages, finalAnswer: finalAnswer, todos: todos)
        }
    }
}
