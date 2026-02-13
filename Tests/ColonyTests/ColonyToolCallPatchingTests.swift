import Foundation
import Testing
@testable import Colony

private struct NoopClock: HiveClock {
    func nowNanoseconds() -> UInt64 { 0 }
    func sleep(nanoseconds: UInt64) async throws { try await Task.sleep(nanoseconds: nanoseconds) }
}

private struct NoopLogger: HiveLogger {
    func debug(_ message: String, metadata: [String: String]) {}
    func info(_ message: String, metadata: [String: String]) {}
    func error(_ message: String, metadata: [String: String]) {}
}

private actor InMemoryCheckpointStore<Schema: HiveSchema>: HiveCheckpointStore {
    private var checkpoints: [HiveCheckpoint<Schema>] = []

    func save(_ checkpoint: HiveCheckpoint<Schema>) async throws {
        checkpoints.append(checkpoint)
    }

    func loadLatest(threadID: HiveThreadID) async throws -> HiveCheckpoint<Schema>? {
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

private final class ToolCallThenValidateModel: HiveModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount: Int = 0

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        try await streamFinal(request)
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
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

    private func respond(to request: HiveChatRequest) throws -> HiveChatResponse {
        let currentCall: Int = {
            lock.lock()
            defer { lock.unlock() }
            callCount += 1
            return callCount
        }()

        if currentCall == 1 {
            let call = HiveToolCall(
                id: "call-1",
                name: "write_file",
                argumentsJSON: #"{"path":"/note.md","content":"hello"}"#
            )
            return HiveChatResponse(
                message: HiveChatMessage(id: "assistant", role: .assistant, content: "writing", toolCalls: [call])
            )
        }

        try validateNoDanglingToolCalls(in: request.messages)
        return HiveChatResponse(
            message: HiveChatMessage(id: "assistant", role: .assistant, content: "done")
        )
    }

    private func validateNoDanglingToolCalls(in messages: [HiveChatMessage]) throws {
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
    let environment = HiveEnvironment(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(ToolCallThenValidateModel()),
        checkpointStore: AnyHiveCheckpointStore(checkpointStore)
    )

    let runtime = HiveRuntime(graph: graph, environment: environment)
    let threadID = HiveThreadID("thread-patch-toolcalls")

    let first = await runtime.run(
        threadID: threadID,
        input: "hi",
        options: HiveRunOptions(checkpointPolicy: .onInterrupt)
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
        options: HiveRunOptions(checkpointPolicy: .onInterrupt)
    )

    let secondOutcome = try await second.outcome.value
    guard case let .finished(output, _) = secondOutcome, case let .fullStore(store) = output else {
        #expect(Bool(false))
        return
    }

    #expect((try store.get(ColonySchema.Channels.finalAnswer)) == "done")
}

