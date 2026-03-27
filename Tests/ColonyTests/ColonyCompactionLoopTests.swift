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

private struct FixedOutputToolRegistry: SwarmToolRegistry, Sendable {
    func listTools() -> [SwarmToolDefinition] {
        [
            SwarmToolDefinition(
                name: "big_tool",
                description: "Returns output.",
                parametersJSONSchema: #"{"type":"object","properties":{}}"#
            )
        ]
    }

    func invoke(_ call: SwarmToolCall) async throws -> SwarmToolResult {
        SwarmToolResult(toolCallID: call.id, content: "ok")
    }
}

private enum CompactionValidationError: Error, Sendable {
    case expectedUserMessageToBeCompactedAway
}

private final class ToolThenValidateCompactionModel: SwarmModelClient, @unchecked Sendable {
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
                id: "compact-1",
                name: "big_tool",
                argumentsJSON: #"{}"#
            )
            return SwarmChatResponse(
                message: SwarmChatMessage(id: "assistant", role: .assistant, content: "running", toolCalls: [call])
            )
        }

        // Critical on-device behavior: after tool results are appended, we must still run `preModel`
        // so compaction applies before the next model invocation.
        //
        // With `.maxMessages(2)`, the initial user message should have been dropped by compaction.
        if request.messages.contains(where: { $0.role == .user && $0.content.contains("hi") }) {
            throw CompactionValidationError.expectedUserMessageToBeCompactedAway
        }

        return SwarmChatResponse(
            message: SwarmChatMessage(id: "assistant", role: .assistant, content: "done")
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

    let environment = SwarmGraphEnvironment<ColonySchema>(
        context: context,
        clock: NoopClock(),
        logger: NoopLogger(),
        model: SwarmAnyModelClient(ToolThenValidateCompactionModel()),
        tools: SwarmAnyToolRegistry(FixedOutputToolRegistry())
    )
    let runtime = try SwarmGraphRuntime(graph: graph, environment: environment)

    let handle = await runtime.run(
        threadID: SwarmThreadID("thread-compact-after-tool"),
        input: "hi",
        options: SwarmGraphRunOptions(checkpointPolicy: .disabled)
    )

    let outcome = try await handle.outcome.value
    guard case let .finished(output, _) = outcome, case let .fullStore(store) = output else {
        #expect(Bool(false))
        return
    }

    #expect((try store.get(ColonySchema.Channels.finalAnswer)) == "done")
}

