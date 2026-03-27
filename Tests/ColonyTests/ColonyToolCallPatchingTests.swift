import Foundation
import Testing
@_spi(ColonyInternal) import Swarm
@testable import Colony

private struct NoopClock: SwarmClock {
    func nowNanoseconds() -> UInt64 { 0 }
    func sleep(nanoseconds: UInt64) async throws { try await Task.sleep(nanoseconds: nanoseconds) }
}

private struct NoopLogger: SwarmLogger {
    func debug(_ message: String, metadata: [String: String]) {}
    func info(_ message: String, metadata: [String: String]) {}
    func error(_ message: String, metadata: [String: String]) {}
}

private actor InMemoryCheckpointStore<Schema: SwarmGraphSchema>: SwarmCheckpointStore {
    private var checkpoints: [SwarmCheckpoint<Schema>] = []

    func save(_ checkpoint: SwarmCheckpoint<Schema>) async throws {
        checkpoints.append(checkpoint)
    }

    func loadLatest(threadID: SwarmThreadID) async throws -> SwarmCheckpoint<Schema>? {
        checkpoints
            .filter { $0.threadID == threadID }
            .max { lhs, rhs in
                if lhs.stepIndex == rhs.stepIndex { return lhs.id.rawValue < rhs.id.rawValue }
                return lhs.stepIndex < rhs.stepIndex
            }
    }
}

private enum ToolCallValidationError: Error, Sendable {
    case danglingToolCall(toolName: String, toolCallID: String)
}

private final class ToolCallThenValidateModel: SwarmModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount: Int = 0

    func complete(_ request: SwarmChatRequest) async throws -> SwarmChatResponse {
        try await streamFinal(request)
    }

    func stream(_ request: SwarmChatRequest) -> AsyncThrowingStream<SwarmChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let response = try self.respond(to: request)
                    continuation.yield(.final(response))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func respond(to request: SwarmChatRequest) throws -> SwarmChatResponse {
        let currentCall: Int = {
            lock.lock()
            defer { lock.unlock() }
            callCount += 1
            return callCount
        }()

        if currentCall == 1 {
            let call = SwarmToolCall(
                id: "call-1",
                name: "write_file",
                argumentsJSON: #"{"path":"/note.md","content":"hello"}"#
            )
            return SwarmChatResponse(
                message: SwarmChatMessage(id: "assistant", role: .assistant, content: "writing", toolCalls: [call])
            )
        }

        try validateNoDanglingToolCalls(in: request.messages)
        return SwarmChatResponse(
            message: SwarmChatMessage(id: "assistant", role: .assistant, content: "done")
        )
    }

    private func validateNoDanglingToolCalls(in messages: [SwarmChatMessage]) throws {
        for (index, message) in messages.enumerated() where message.role == .assistant {
            for call in message.toolCalls {
                let hasToolMessage = messages[(index + 1)...].contains { later in
                    later.role == .tool && later.toolCallID == call.id
                }
                if hasToolMessage == false {
                    throw ToolCallValidationError.danglingToolCall(toolName: call.name, toolCallID: call.id)
                }
            }
        }
    }
}

@Test("Colony patches dangling tool calls when a new user message arrives after an interrupt")
func colonyPatchesDanglingToolCallsOnNewInput() async throws {
    let graph = try ColonyAgent.compile()
    let fs = ColonyInMemoryFileSystemBackend()

    let configuration = ColonyConfiguration(
        capabilities: [.filesystem],
        modelName: "test-model",
        toolApprovalPolicy: .always
    )
    let context = ColonyContext(configuration: configuration, filesystem: fs)

    let checkpointStore = InMemoryCheckpointStore<ColonySchema>()
    let environment = SwarmGraphEnvironment(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: SwarmAnyModelClient(ToolCallThenValidateModel()),
        checkpointStore: SwarmAnyCheckpointStore(checkpointStore)
    )

    let runtime = try SwarmGraphRuntime(graph: graph, environment: environment)
    let threadID = SwarmThreadID("thread-patch-toolcalls")

    let first = await runtime.run(
        threadID: threadID,
        input: "hi",
        options: SwarmGraphRunOptions(checkpointPolicy: .onInterrupt)
    )
    let firstOutcome = try await first.outcome.value
    guard case .interrupted = firstOutcome else {
        #expect(Bool(false))
        return
    }

    // Start a new user message without resuming the previous interrupt.
    // Without patching, the second model invocation sees an assistant tool call
    // without a corresponding tool message and should fail under strict providers.
    let second = await runtime.run(
        threadID: threadID,
        input: "new message",
        options: SwarmGraphRunOptions(checkpointPolicy: .onInterrupt)
    )

    let secondOutcome = try await second.outcome.value
    guard case let .finished(output, _) = secondOutcome, case let .fullStore(store) = output else {
        #expect(Bool(false))
        return
    }

    #expect((try store.get(ColonySchema.Channels.finalAnswer)) == "done")
}

