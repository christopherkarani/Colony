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

private struct FixedOutputToolRegistry: HiveToolRegistry, Sendable {
    func listTools() -> [HiveToolDefinition] {
        [
            HiveToolDefinition(
                name: "big_tool",
                description: "Returns output.",
                parametersJSONSchema: #"{"type":"object","properties":{}}"#
            )
        ]
    }

    func invoke(_ call: HiveToolCall) async throws -> HiveToolResult {
        HiveToolResult(toolCallID: call.id, content: "ok")
    }
}

private enum CompactionValidationError: Error, Sendable {
    case expectedUserMessageToBeCompactedAway
}

private final class ToolThenValidateCompactionModel: HiveModelClient, @unchecked Sendable {
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
                id: "compact-1",
                name: "big_tool",
                argumentsJSON: #"{}"#
            )
            return HiveChatResponse(
                message: HiveChatMessage(id: "assistant", role: .assistant, content: "running", toolCalls: [call])
            )
        }

        // Critical on-device behavior: after tool results are appended, we must still run `preModel`
        // so compaction applies before the next model invocation.
        //
        // With `.maxMessages(2)`, the initial user message should have been dropped by compaction.
        if request.messages.contains(where: { $0.role == .user && $0.content.contains("hi") }) {
            throw CompactionValidationError.expectedUserMessageToBeCompactedAway
        }

        return HiveChatResponse(
            message: HiveChatMessage(id: "assistant", role: .assistant, content: "done")
        )
    }
}

@Test("Colony runs preModel compaction before the post-tool model turn (on-device 4k safety)")
func colonyCompactsBeforeSecondModelTurnAfterTools() async throws {
    let graph = try ColonyAgent.compile()

    let configuration = ColonyConfiguration(
        capabilities: [],
        modelName: "test-model",
        toolApprovalPolicy: .never,
        compactionPolicy: .maxMessages(2)
    )
    let context = ColonyContext(configuration: configuration, filesystem: nil, shell: nil, subagents: nil)

    let environment = HiveEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: AnyHiveModelClient(ToolThenValidateCompactionModel()),
        tools: AnyHiveToolRegistry(FixedOutputToolRegistry())
    )
    let runtime = HiveRuntime(graph: graph, environment: environment)

    let handle = await runtime.run(
        threadID: HiveThreadID("thread-compact-after-tool"),
        input: "hi",
        options: HiveRunOptions(checkpointPolicy: .disabled)
    )

    let outcome = try await handle.outcome.value
    guard case let .finished(output, _) = outcome, case let .fullStore(store) = output else {
        #expect(Bool(false))
        return
    }

    #expect((try store.get(ColonySchema.Channels.finalAnswer)) == "done")
}

