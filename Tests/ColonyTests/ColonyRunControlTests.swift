import Foundation
import Testing
import Colony

@Suite("ColonyRunControl")
struct ColonyRunControlTests {
    @Test("Run control start/resume preserves approval parity and interrupt correlation")
    func runControl_startResumeParityAndCorrelation() async throws {
        let filesystem = ColonyInMemoryFileSystemBackend()
        let runtime = try makeRuntime(
            threadID: "run-control-parity",
            model: AnyHiveModelClient(ScriptedApprovalModel()),
            filesystem: filesystem
        )

        let startHandle = await runtime.runControl.start(.init(input: "Write /note.md"))
        let startEvents = await collectEvents(startHandle.events)
        #expect(startEvents.allSatisfy { event in event.id.runID == startHandle.runID })
        #expect(startEvents.allSatisfy { event in event.id.attemptID == startHandle.attemptID })

        let startOutcome = try await startHandle.outcome.value
        guard case let .interrupted(interruption) = startOutcome else {
            Issue.record("Expected interrupted outcome from start request.")
            return
        }

        let eventInterruptID = startEvents.compactMap { event -> HiveInterruptID? in
            guard case let .runInterrupted(interruptID) = event.kind else { return nil }
            return interruptID
        }.first
        let correlatedInterruptID = try #require(eventInterruptID)
        #expect(correlatedInterruptID == interruption.interrupt.id)

        let resumeHandle = await runtime.runControl.resume(
            .init(interruptID: interruption.interrupt.id, decision: .approved)
        )
        #expect(resumeHandle.attemptID != startHandle.attemptID)

        let resumedOutcome = try await resumeHandle.outcome.value
        guard case let .finished(output, _) = resumedOutcome,
              case let .fullStore(store) = output else {
            Issue.record("Expected finished full-store outcome after approved resume.")
            return
        }

        let finalAnswer = try store.get(ColonySchema.Channels.finalAnswer)
        #expect(finalAnswer == "done")

        let written = try await filesystem.read(at: try ColonyVirtualPath("/note.md"))
        #expect(written == "hello")
    }

    @Test("Run control stale interrupt IDs fail deterministically")
    func runControl_staleInterruptMismatch() async throws {
        let runtime = try makeRuntime(
            threadID: "run-control-stale",
            model: AnyHiveModelClient(ScriptedApprovalModel())
        )

        let startHandle = await runtime.runControl.start(.init(input: "Write /note.md"))
        let startOutcome = try await startHandle.outcome.value
        guard case let .interrupted(interruption) = startOutcome else {
            Issue.record("Expected interrupted outcome before stale resume assertion.")
            return
        }

        let staleInterruptID = HiveInterruptID("stale-interrupt-id")
        let staleHandle = await runtime.runControl.resume(
            .init(interruptID: staleInterruptID, decision: .approved)
        )

        do {
            _ = try await staleHandle.outcome.value
            Issue.record("Expected stale resume to fail with resumeInterruptMismatch.")
        } catch let error as HiveRuntimeError {
            switch error {
            case let .resumeInterruptMismatch(expected, found):
                #expect(expected == interruption.interrupt.id)
                #expect(found == staleInterruptID)
            default:
                Issue.record("Expected resumeInterruptMismatch but received \(error).")
            }
        }
    }

    @Test("Run control duplicate resume becomes deterministic no-interrupt error")
    func runControl_duplicateResumeIsDeterministic() async throws {
        let runtime = try makeRuntime(
            threadID: "run-control-duplicate",
            model: AnyHiveModelClient(ScriptedApprovalModel())
        )

        let startHandle = await runtime.runControl.start(
            .init(
                input: "Write /note.md",
                optionsOverride: HiveRunOptions(checkpointPolicy: .onInterrupt)
            )
        )
        let startOutcome = try await startHandle.outcome.value
        guard case let .interrupted(interruption) = startOutcome else {
            Issue.record("Expected interrupted outcome before duplicate resume assertions.")
            return
        }

        let completionOptions = HiveRunOptions(
            maxSteps: 200,
            maxConcurrentTasks: 4,
            checkpointPolicy: .everyStep
        )
        let firstResume = await runtime.runControl.resume(
            .init(
                interruptID: interruption.interrupt.id,
                decision: .approved,
                optionsOverride: completionOptions
            )
        )
        _ = try await firstResume.outcome.value

        let duplicateResume = await runtime.runControl.resume(
            .init(
                interruptID: interruption.interrupt.id,
                decision: .approved,
                optionsOverride: completionOptions
            )
        )

        do {
            _ = try await duplicateResume.outcome.value
            Issue.record("Expected duplicate resume to fail once no pending interrupt remains.")
        } catch let error as HiveRuntimeError {
            switch error {
            case .noInterruptToResume:
                #expect(Bool(true))
            default:
                Issue.record("Expected noInterruptToResume but received \(error).")
            }
        }
    }

    @Test("Run control cancelled decision records cancellation and skips tool execution")
    func runControl_cancelledDecisionSkipsToolExecution() async throws {
        let filesystem = ColonyInMemoryFileSystemBackend()
        let runtime = try makeRuntime(
            threadID: "run-control-cancelled",
            model: AnyHiveModelClient(ScriptedApprovalModel()),
            filesystem: filesystem
        )

        let startHandle = await runtime.runControl.start(.init(input: "Write /note.md"))
        let startOutcome = try await startHandle.outcome.value
        guard case let .interrupted(interruption) = startOutcome else {
            Issue.record("Expected interrupted outcome before cancelled resume assertion.")
            return
        }

        let resumeHandle = await runtime.runControl.resume(
            .init(interruptID: interruption.interrupt.id, decision: .cancelled)
        )
        let resumedOutcome = try await resumeHandle.outcome.value
        guard case let .finished(output, _) = resumedOutcome,
              case let .fullStore(store) = output else {
            Issue.record("Expected finished full-store outcome after cancelled resume.")
            return
        }

        let messages = try store.get(ColonySchema.Channels.messages)
        let hasCancellationSystem = messages.contains(where: { message in
            message.role == .system && message.content == "Tool execution cancelled by user."
        })
        #expect(hasCancellationSystem)

        let hasCancellationTool = messages.contains(where: { message in
            message.role == .tool
                && message.toolCallID == "call-1"
                && message.content.contains("cancelled")
        })
        #expect(hasCancellationTool)

        do {
            _ = try await filesystem.read(at: try ColonyVirtualPath("/note.md"))
            Issue.record("Tool output file should not exist after cancelled decision.")
        } catch {
            #expect(Bool(true))
        }
    }
}

private func makeRuntime(
    threadID: String,
    model: AnyHiveModelClient,
    filesystem: (any ColonyFileSystemBackend)? = ColonyInMemoryFileSystemBackend()
) throws -> ColonyRuntime {
    try ColonyAgentFactory().makeRuntime(
        profile: .onDevice4k,
        threadID: HiveThreadID(threadID),
        modelName: "test-model",
        model: model,
        filesystem: filesystem,
        configure: { configuration in
            configuration.capabilities = [.filesystem]
            configuration.toolApprovalPolicy = .always
            configuration.summarizationPolicy = nil
            configuration.toolResultEvictionTokenLimit = nil
        }
    )
}

private func collectEvents(_ stream: AsyncThrowingStream<HiveEvent, Error>) async -> [HiveEvent] {
    var events: [HiveEvent] = []
    do {
        for try await event in stream {
            events.append(event)
        }
    } catch {
        return events
    }
    return events
}

private final class ScriptedApprovalModel: HiveModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private var invocations = 0

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        nextResponse()
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        let response = nextResponse()
        return AsyncThrowingStream { continuation in
            continuation.yield(.final(response))
            continuation.finish()
        }
    }

    private func nextResponse() -> HiveChatResponse {
        lock.lock()
        invocations += 1
        let invocation = invocations
        lock.unlock()

        if invocation == 1 {
            let call = HiveToolCall(
                id: "call-1",
                name: ColonyBuiltInToolDefinitions.writeFile.name,
                argumentsJSON: #"{"path":"/note.md","content":"hello"}"#
            )
            return HiveChatResponse(
                message: HiveChatMessage(id: "assistant-1", role: .assistant, content: "delegating", toolCalls: [call])
            )
        }

        return HiveChatResponse(
            message: HiveChatMessage(id: "assistant-\(invocation)", role: .assistant, content: "done")
        )
    }
}
