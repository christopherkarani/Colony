import Dispatch
import Foundation
import Testing
@testable import Colony

private struct HarnessNoopClock: HiveClock {
    func nowNanoseconds() -> UInt64 { 0 }
    func sleep(nanoseconds: UInt64) async throws { try await Task.sleep(nanoseconds: nanoseconds) }
}

private struct HarnessNoopLogger: HiveLogger {
    func debug(_ message: String, metadata: [String: String]) {}
    func info(_ message: String, metadata: [String: String]) {}
    func error(_ message: String, metadata: [String: String]) {}
}

private final class InterruptThenFinishModel: HiveModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount: Int = 0

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        try await streamFinal(request)
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let index = self.nextCallIndex()
                continuation.yield(.token("delta-\(index)"))

                if index == 1 {
                    let call = HiveToolCall(
                        id: "call-1",
                        name: "write_file",
                        argumentsJSON: #"{"path":"/note.md","content":"hello"}"#
                    )
                    continuation.yield(
                        .final(
                            HiveChatResponse(
                                message: HiveChatMessage(
                                    id: "assistant-\(index)",
                                    role: .assistant,
                                    content: "need approval",
                                    toolCalls: [call]
                                )
                            )
                        )
                    )
                } else {
                    continuation.yield(
                        .final(
                            HiveChatResponse(
                                message: HiveChatMessage(
                                    id: "assistant-\(index)",
                                    role: .assistant,
                                    content: "done"
                                )
                            )
                        )
                    )
                }
                continuation.finish()
            }
        }
    }

    private func nextCallIndex() -> Int {
        lock.lock()
        defer { lock.unlock() }
        callCount += 1
        return callCount
    }
}

private final class SlowStreamingModel: HiveModelClient, @unchecked Sendable {
    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        try await streamFinal(request)
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                while Task.isCancelled == false {
                    continuation.yield(.token("working"))
                    try await Task.sleep(nanoseconds: 50_000_000)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

private actor HarnessEventSink {
    private var events: [ColonyHarnessEventEnvelope] = []

    func append(_ event: ColonyHarnessEventEnvelope) {
        events.append(event)
    }

    func snapshot() -> [ColonyHarnessEventEnvelope] {
        events
    }
}

private func waitUntil(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    pollNanoseconds: UInt64 = 10_000_000,
    _ condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    let start = DispatchTime.now().uptimeNanoseconds
    while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
        if await condition() {
            return true
        }

        try? await Task.sleep(nanoseconds: pollNanoseconds)
    }

    return await condition()
}

@Test("Harness protocol envelope contracts are Codable and preserve v1 payload shape")
func harnessProtocolEnvelopeContractsAreCodable() throws {
    let sessionID = ColonyHarnessSessionID(rawValue: "session-1")
    let runID = UUID(uuidString: "0E984725-C51C-4BF4-9960-E1C80E27ABA0")!
    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

    let envelopes: [ColonyHarnessEventEnvelope] = [
        ColonyHarnessEventEnvelope(
            protocolVersion: .v1,
            eventType: .assistantDelta,
            sequence: 1,
            timestamp: timestamp,
            runID: runID,
            sessionID: sessionID,
            payload: .assistantDelta(.init(delta: "hello"))
        ),
        ColonyHarnessEventEnvelope(
            protocolVersion: .v1,
            eventType: .toolRequest,
            sequence: 2,
            timestamp: timestamp,
            runID: runID,
            sessionID: sessionID,
            payload: .toolRequest(.init(toolCallID: "call-1", toolName: "write_file", argumentsJSON: "{}"))
        ),
        ColonyHarnessEventEnvelope(
            protocolVersion: .v1,
            eventType: .toolResult,
            sequence: 3,
            timestamp: timestamp,
            runID: runID,
            sessionID: sessionID,
            payload: .toolResult(.init(toolCallID: "call-1", toolName: "write_file", success: true))
        ),
        ColonyHarnessEventEnvelope(
            protocolVersion: .v1,
            eventType: .toolDenied,
            sequence: 4,
            timestamp: timestamp,
            runID: runID,
            sessionID: sessionID,
            payload: .toolDenied(.init(toolCallID: "call-1", toolName: "write_file", reason: "rejected"))
        ),
    ]

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    let decoder = JSONDecoder()

    for envelope in envelopes {
        let data = try encoder.encode(envelope)
        let decoded = try decoder.decode(ColonyHarnessEventEnvelope.self, from: data)

        #expect(decoded.protocolVersion == .v1)
        #expect(decoded.eventType == envelope.eventType)
        #expect(decoded.sequence == envelope.sequence)
        #expect(decoded.runID == envelope.runID)
        #expect(decoded.sessionID.rawValue == envelope.sessionID.rawValue)
        #expect(decoded.payload == envelope.payload)
    }
}

@Test("Harness session supports start/stream/interrupted/resume with ordered versioned events")
func harnessSessionLifecycleAndOrdering() async throws {
    let runtime = try ColonyAgentFactory().makeRuntime(
        threadID: HiveThreadID("thread-harness-lifecycle"),
        modelName: "test-model",
        model: AnyHiveModelClient(InterruptThenFinishModel()),
        clock: HarnessNoopClock(),
        logger: HarnessNoopLogger(),
        configure: { configuration in
            configuration.toolApprovalPolicy = .always
        }
    )

    let session = ColonyHarnessSession.create(runtime: runtime)
    let sink = HarnessEventSink()
    let stream = await session.stream()
    let streamTask = Task {
        for try await event in stream {
            await sink.append(event)
        }
    }

    try await session.start(input: "start")

    let interruptedObserved = await waitUntil {
        let events = await sink.snapshot()
        return events.contains { $0.eventType == .runInterrupted }
    }
    #expect(interruptedObserved)

    let interruption = await session.interrupted()
    let pendingInterruptions = await session.pendingInterruptions()
    #expect(interruption != nil)
    #expect(interruption?.toolCalls.count == 1)
    #expect(interruption?.toolCalls.first?.id == "call-1")
    #expect(pendingInterruptions.count == 1)

    try await session.resume(decision: .rejected)
    #expect(await session.pendingInterruptions().isEmpty)

    let finishedObserved = await waitUntil {
        let events = await sink.snapshot()
        return events.contains { $0.eventType == .runFinished }
    }
    #expect(finishedObserved)

    let events = await sink.snapshot()
    let sequences = events.map(\.sequence)
    let sortedSequences = sequences.sorted()
    #expect(sequences == sortedSequences)

    let toolRequest = events.first {
        if case .toolRequest = $0.payload {
            return true
        }
        return false
    }

    let toolDenied = events.first {
        if case .toolDenied = $0.payload {
            return true
        }
        return false
    }

    #expect(toolRequest != nil)
    #expect(toolDenied != nil)

    if let toolRequest, let toolDenied {
        #expect(toolRequest.sequence < toolDenied.sequence)
    }

    let deltaFound = events.contains {
        if case let .assistantDelta(payload) = $0.payload {
            return payload.delta.contains("delta-")
        }
        return false
    }
    #expect(deltaFound)

    await session.stop()
    streamTask.cancel()
}

@Test("Harness session stop cancels active run")
func harnessSessionStopCancelsActiveRun() async throws {
    let runtime = try ColonyAgentFactory().makeRuntime(
        threadID: HiveThreadID("thread-harness-stop"),
        modelName: "slow-model",
        model: AnyHiveModelClient(SlowStreamingModel()),
        clock: HarnessNoopClock(),
        logger: HarnessNoopLogger(),
        configure: { configuration in
            configuration.toolApprovalPolicy = .never
        }
    )

    let session = ColonyHarnessSession.create(runtime: runtime)
    let sink = HarnessEventSink()
    let stream = await session.stream()
    let streamTask = Task {
        for try await event in stream {
            await sink.append(event)
        }
    }

    try await session.start(input: "start")

    let startedObserved = await waitUntil {
        let events = await sink.snapshot()
        return events.contains { $0.eventType == .runStarted }
    }
    #expect(startedObserved)

    await session.stop()

    let cancelledObserved = await waitUntil {
        let events = await sink.snapshot()
        return events.contains { $0.eventType == .runCancelled }
    }
    #expect(cancelledObserved)

    #expect(await session.lifecycleState == .stopped)
    streamTask.cancel()
}
