import Foundation
import Testing
@_spi(ColonyInternal) import Swarm
import Colony

@Suite("ColonyRunControl")
struct ColonyRunControlTests {
    @Test("Run control start/resume preserves approval parity and interrupt correlation")
    func runControl_startResumeParityAndCorrelation() async throws {
        let filesystem = ColonyInMemoryFileSystemBackend()
        let runtime = try makeRuntime(
            threadID: "run-control-parity",
            model: SwarmAnyModelClient(ScriptedApprovalModel()),
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

        let eventInterruptID = startEvents.compactMap { event -> ColonyInterruptID? in
            guard case let .runInterrupted(interruptID) = event.kind else { return nil }
            return interruptID
        }.first
        let correlatedInterruptID = try #require(eventInterruptID)
        #expect(correlatedInterruptID == interruption.interruptID)

        let resumeHandle = await runtime.runControl.resume(
            .init(interruptID: interruption.interruptID, decision: .approved)
        )
        #expect(resumeHandle.runID == startHandle.runID)
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
            model: SwarmAnyModelClient(ScriptedApprovalModel())
        )

        let startHandle = await runtime.runControl.start(.init(input: "Write /note.md"))
        let startOutcome = try await startHandle.outcome.value
        guard case let .interrupted(interruption) = startOutcome else {
            Issue.record("Expected interrupted outcome before stale resume assertion.")
            return
        }

        let staleInterruptID = ColonyInterruptID("stale-interrupt-id")
        let staleHandle = await runtime.runControl.resume(
            .init(interruptID: staleInterruptID, decision: .approved)
        )

        do {
            _ = try await staleHandle.outcome.value
            Issue.record("Expected stale resume to fail with resumeInterruptMismatch.")
        } catch let error as SwarmRuntimeError {
            switch error {
            case let .resumeInterruptMismatch(expected, found):
                #expect(expected == interruption.interruptID)
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
            model: SwarmAnyModelClient(ScriptedApprovalModel())
        )

        let startHandle = await runtime.runControl.start(
            .init(
                input: "Write /note.md",
                optionsOverride: SwarmGraphRunOptions(checkpointPolicy: .onInterrupt)
            )
        )
        let startOutcome = try await startHandle.outcome.value
        guard case let .interrupted(interruption) = startOutcome else {
            Issue.record("Expected interrupted outcome before duplicate resume assertions.")
            return
        }

        let completionOptions = ColonyRun.Options(
            maxSteps: 200,
            maxConcurrentTasks: 4,
            checkpointPolicy: .everyStep
        )
        let firstResume = await runtime.runControl.resume(
            .init(
                interruptID: interruption.interruptID,
                decision: .approved,
                optionsOverride: completionOptions
            )
        )
        _ = try await firstResume.outcome.value

        let duplicateResume = await runtime.runControl.resume(
            .init(
                interruptID: interruption.interruptID,
                decision: .approved,
                optionsOverride: completionOptions
            )
        )

        do {
            _ = try await duplicateResume.outcome.value
            Issue.record("Expected duplicate resume to fail once no pending interrupt remains.")
        } catch let error as SwarmRuntimeError {
            switch error {
            case .noInterruptToResume:
                #expect(Bool(true))
            default:
                Issue.record("Expected noInterruptToResume but received \(error).")
            }
        }
    }

    @Test("Run control rejected decision skips tool execution")
    func runControl_rejectedDecisionSkipsToolExecution() async throws {
        let filesystem = ColonyInMemoryFileSystemBackend()
        let runtime = try makeRuntime(
            threadID: "run-control-cancelled",
            model: SwarmAnyModelClient(ScriptedApprovalModel()),
            filesystem: filesystem
        )

        let startHandle = await runtime.runControl.start(.init(input: "Write /note.md"))
        let startOutcome = try await startHandle.outcome.value
        guard case let .interrupted(interruption) = startOutcome else {
            Issue.record("Expected interrupted outcome before cancelled resume assertion.")
            return
        }

        let resumeHandle = await runtime.runControl.resume(
            .init(interruptID: interruption.interruptID, decision: .rejected)
        )
        let resumedOutcome = try await resumeHandle.outcome.value
        guard case let .finished(output, _) = resumedOutcome,
              case let .fullStore(store) = output else {
            Issue.record("Expected finished full-store outcome after rejected resume.")
            return
        }

        let messages = try store.get(ColonySchema.Channels.messages)
        let hasRejectionSystem = messages.contains(where: { message in
            message.role == SwarmChatRole.system && message.content.contains("rejected")
        })
        #expect(hasRejectionSystem)

        let hasRejectionTool = messages.contains(where: { message in
            message.role == SwarmChatRole.tool
                && message.toolCallID == "call-1"
                && message.content.contains("rejected")
        })
        #expect(hasRejectionTool)

        do {
            _ = try await filesystem.read(at: try ColonyVirtualPath("/note.md"))
            Issue.record("Tool output file should not exist after rejected decision.")
        } catch {
            #expect(Bool(true))
        }
    }

    @Test("Run control executes spawned tool work up to maxConcurrentTasks")
    func runControl_honorsMaxConcurrentTasksForSpawnedTools() async throws {
        let shell = ConcurrentExecuteShellBackend(delayNanoseconds: 100_000_000)
        let runtime = try ColonyBuilder()
            .profile(.onDevice4k)
            .threadID(SwarmThreadID("run-control-concurrency"))
            .model(name: "test-model")
            .model(SwarmAnyModelClient(ParallelExecuteModel()))
            .shell(shell)
            .configure { configuration in
                configuration.capabilities = [.shell]
                configuration.toolApprovalPolicy = .never
                configuration.mandatoryApprovalRiskLevels = []
                configuration.summarizationPolicy = nil
                configuration.toolResultEvictionTokenLimit = nil
            }
            .build()

        let handle = await runtime.runControl.start(
            .init(
                input: "run parallel work",
                optionsOverride: ColonyRun.Options(
                    maxSteps: 20,
                    maxConcurrentTasks: 2,
                    checkpointPolicy: .disabled
                )
            )
        )

        let outcome = try await handle.outcome.value
        guard case let .finished(output, _) = outcome,
              case let .fullStore(store) = output else {
            Issue.record("Expected finished outcome for parallel tool execution.")
            return
        }

        #expect(try store.get(ColonySchema.Channels.finalAnswer) == "done")
        #expect(await shell.maxObservedInFlight() == 2)
    }
}

private func makeRuntime(
    threadID: String,
    model: SwarmAnyModelClient,
    filesystem: (any ColonyFileSystemBackend)? = ColonyInMemoryFileSystemBackend()
) throws -> ColonyRuntime {
    try ColonyBuilder()
        .profile(.onDevice4k)
        .threadID(SwarmThreadID(threadID))
        .model(name: "test-model")
        .model(model)
        .filesystem(filesystem)
        .configure { configuration in
            configuration.capabilities = [.filesystem]
            configuration.toolApprovalPolicy = .always
            configuration.summarizationPolicy = nil
            configuration.toolResultEvictionTokenLimit = nil
        }
        .build()
}

private func collectEvents(_ stream: AsyncThrowingStream<ColonyRun.Event, Error>) async -> [ColonyRun.Event] {
    var events: [ColonyRun.Event] = []
    do {
        for try await event in stream {
            events.append(event)
        }
    } catch {
        return events
    }
    return events
}

private final class ScriptedApprovalModel: SwarmModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private var invocations = 0

    func complete(_ request: SwarmChatRequest) async throws -> SwarmChatResponse {
        nextResponse()
    }

    func stream(_ request: SwarmChatRequest) -> AsyncThrowingStream<SwarmChatStreamChunk, Error> {
        let response = nextResponse()
        return AsyncThrowingStream { continuation in
            continuation.yield(.final(response))
            continuation.finish()
        }
    }

    private func nextResponse() -> SwarmChatResponse {
        lock.lock()
        invocations += 1
        let invocation = invocations
        lock.unlock()

        if invocation == 1 {
            let call = SwarmToolCall(
                id: "call-1",
                name: ColonyBuiltInToolDefinitions.writeFile.name,
                argumentsJSON: #"{"path":"/note.md","content":"hello"}"#
            )
            return SwarmChatResponse(
                message: SwarmChatMessage(id: "assistant-1", role: .assistant, content: "delegating", toolCalls: [call])
            )
        }

        return SwarmChatResponse(
            message: SwarmChatMessage(id: "assistant-\(invocation)", role: .assistant, content: "done")
        )
    }
}

private actor ConcurrentExecuteShellBackend: ColonyShellBackend {
    private let delayNanoseconds: UInt64
    private var inFlight = 0
    private var maxObserved = 0

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    func execute(_ request: ColonyShellExecutionRequest) async throws -> ColonyShellExecutionResponse {
        inFlight += 1
        maxObserved = max(maxObserved, inFlight)
        defer { inFlight -= 1 }

        try await Task.sleep(nanoseconds: delayNanoseconds)
        return ColonyShellExecutionResponse(
            exitCode: 0,
            stdout: "ok:\(request.command)",
            stderr: ""
        )
    }

    func maxObservedInFlight() -> Int {
        maxObserved
    }
}

private final class ParallelExecuteModel: SwarmModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private var invocations = 0

    func complete(_ request: SwarmChatRequest) async throws -> SwarmChatResponse {
        nextResponse()
    }

    func stream(_ request: SwarmChatRequest) -> AsyncThrowingStream<SwarmChatStreamChunk, Error> {
        let response = nextResponse()
        return AsyncThrowingStream { continuation in
            continuation.yield(.final(response))
            continuation.finish()
        }
    }

    private func nextResponse() -> SwarmChatResponse {
        lock.lock()
        invocations += 1
        let invocation = invocations
        lock.unlock()

        if invocation == 1 {
            return SwarmChatResponse(
                message: SwarmChatMessage(
                    id: "assistant-parallel-1",
                    role: .assistant,
                    content: "parallel",
                    toolCalls: [
                        SwarmToolCall(
                            id: "exec-1",
                            name: ColonyBuiltInToolDefinitions.execute.name,
                            argumentsJSON: #"{"command":"first"}"#
                        ),
                        SwarmToolCall(
                            id: "exec-2",
                            name: ColonyBuiltInToolDefinitions.execute.name,
                            argumentsJSON: #"{"command":"second"}"#
                        ),
                    ]
                )
            )
        }

        return SwarmChatResponse(
            message: SwarmChatMessage(id: "assistant-parallel-\(invocation)", role: .assistant, content: "done")
        )
    }
}
