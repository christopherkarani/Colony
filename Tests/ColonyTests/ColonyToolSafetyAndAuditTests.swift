import Foundation
import Testing
@testable import Colony

private struct SafetyNoopClock: HiveClock {
    func nowNanoseconds() -> UInt64 { 42 }
    func sleep(nanoseconds: UInt64) async throws { try await Task.sleep(nanoseconds: nanoseconds) }
}

private struct SafetyNoopLogger: HiveLogger {
    func debug(_ message: String, metadata: [String: String]) {}
    func info(_ message: String, metadata: [String: String]) {}
    func error(_ message: String, metadata: [String: String]) {}
}

private actor SafetyInMemoryCheckpointStore<Schema: HiveSchema>: HiveCheckpointStore {
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

private final class SingleMutatingCallModel: HiveModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        try await streamFinal(request)
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let response = self.respond()
                continuation.yield(.final(response))
                continuation.finish()
            }
        }
    }

    private func respond() -> HiveChatResponse {
        let index: Int = {
            lock.lock()
            defer { lock.unlock() }
            callCount += 1
            return callCount
        }()

        if index == 1 {
            let call = HiveToolCall(
                id: "write-1",
                name: "write_file",
                argumentsJSON: #"{"path":"/approved.md","content":"ok"}"#
            )
            return HiveChatResponse(
                message: HiveChatMessage(id: "assistant-1", role: .assistant, content: "write", toolCalls: [call])
            )
        }

        return HiveChatResponse(
            message: HiveChatMessage(id: "assistant-2", role: .assistant, content: "done")
        )
    }
}

private final class DualMutatingCallsModel: HiveModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        try await streamFinal(request)
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let response = self.respond()
                continuation.yield(.final(response))
                continuation.finish()
            }
        }
    }

    private func respond() -> HiveChatResponse {
        let index: Int = {
            lock.lock()
            defer { lock.unlock() }
            callCount += 1
            return callCount
        }()

        if index == 1 {
            let callA = HiveToolCall(
                id: "write-a",
                name: "write_file",
                argumentsJSON: #"{"path":"/a.md","content":"A"}"#
            )
            let callB = HiveToolCall(
                id: "write-b",
                name: "write_file",
                argumentsJSON: #"{"path":"/b.md","content":"B"}"#
            )
            return HiveChatResponse(
                message: HiveChatMessage(id: "assistant-1", role: .assistant, content: "write", toolCalls: [callA, callB])
            )
        }

        return HiveChatResponse(
            message: HiveChatMessage(id: "assistant-2", role: .assistant, content: "done")
        )
    }
}

@Test("Mutating tools require approval even when toolApprovalPolicy is never")
func mutatingToolsStillRequireApprovalWhenPolicyNever() async throws {
    let graph = try ColonyAgent.compile()
    let fs = ColonyInMemoryFileSystemBackend()
    let configuration = ColonyConfiguration(
        capabilities: [.filesystem],
        modelName: "test-model",
        toolApprovalPolicy: .never
    )
    let context = ColonyContext(configuration: configuration, filesystem: fs)

    let environment = HiveEnvironment(
        context: context,
        clock: SafetyNoopClock(),
        logger: SafetyNoopLogger(),
        model: AnyHiveModelClient(SingleMutatingCallModel()),
        checkpointStore: AnyHiveCheckpointStore(SafetyInMemoryCheckpointStore<ColonySchema>())
    )
    let runtime = HiveRuntime(graph: graph, environment: environment)

    let handle = await runtime.run(
        threadID: HiveThreadID("tool-safety-never"),
        input: "hi",
        options: HiveRunOptions(checkpointPolicy: .onInterrupt)
    )

    let outcome = try await handle.outcome.value
    guard case let .interrupted(interruption) = outcome else {
        #expect(Bool(false))
        return
    }

    guard case let .toolApprovalRequired(toolCalls) = interruption.interrupt.payload else {
        #expect(Bool(false))
        return
    }

    #expect(toolCalls.count == 1)
    #expect(toolCalls.first?.id == "write-1")
    #expect(toolCalls.first?.name == "write_file")
}

@Test("Per-tool approval decisions support partial approve/deny on a single interrupt")
func perToolApprovalSupportsPartialAllowAndDeny() async throws {
    let graph = try ColonyAgent.compile()
    let fs = ColonyInMemoryFileSystemBackend()
    let configuration = ColonyConfiguration(
        capabilities: [.filesystem],
        modelName: "test-model",
        toolApprovalPolicy: .never
    )
    let context = ColonyContext(configuration: configuration, filesystem: fs)

    let environment = HiveEnvironment(
        context: context,
        clock: SafetyNoopClock(),
        logger: SafetyNoopLogger(),
        model: AnyHiveModelClient(DualMutatingCallsModel()),
        checkpointStore: AnyHiveCheckpointStore(SafetyInMemoryCheckpointStore<ColonySchema>())
    )
    let runtime = HiveRuntime(graph: graph, environment: environment)
    let threadID = HiveThreadID("tool-safety-partial")

    let handle = await runtime.run(
        threadID: threadID,
        input: "hi",
        options: HiveRunOptions(checkpointPolicy: .onInterrupt)
    )
    let outcome = try await handle.outcome.value
    guard case let .interrupted(interruption) = outcome else {
        #expect(Bool(false))
        return
    }

    let resumed = await runtime.resume(
        threadID: threadID,
        interruptID: interruption.interrupt.id,
        payload: .toolApproval(decision: .perTool([.init(toolCallID: "write-a", decision: .approved)])),
        options: HiveRunOptions(checkpointPolicy: .onInterrupt)
    )

    let resumedOutcome = try await resumed.outcome.value
    guard case let .finished(output, _) = resumedOutcome else {
        #expect(Bool(false))
        return
    }

    guard case let .fullStore(store) = output else {
        #expect(Bool(false))
        return
    }

    #expect(try await fs.read(at: ColonyVirtualPath("/a.md")) == "A")
    do {
        _ = try await fs.read(at: ColonyVirtualPath("/b.md"))
        #expect(Bool(false))
    } catch {
        // Expected: denied call did not execute.
    }

    let messages = try store.get(ColonySchema.Channels.messages)
    let deniedToolMessage = messages.first { message in
        message.role == .tool && message.toolCallID == "write-b"
    }
    #expect(deniedToolMessage != nil)
}

@Test("Signed immutable audit records verify signature and hash chain integrity")
func signedAuditRecordVerification() async throws {
    let signer = ColonyHMACSHA256ToolAuditSigner(keyData: Data("audit-key".utf8), keyID: "k1")
    let store = ColonyInMemoryToolAuditLogStore()
    let recorder = ColonyToolAuditRecorder(store: store, signer: signer)

    try await recorder.record(
        event: ColonyToolAuditEvent(
            timestampNanoseconds: 1,
            threadID: "thread-audit",
            taskID: "task-1",
            toolCallID: "call-1",
            toolName: "write_file",
            riskLevel: .mutation,
            decision: .approvalRequired,
            reason: .mandatoryRiskLevel
        )
    )
    try await recorder.record(
        event: ColonyToolAuditEvent(
            timestampNanoseconds: 2,
            threadID: "thread-audit",
            taskID: "task-1",
            toolCallID: "call-1",
            toolName: "write_file",
            riskLevel: .mutation,
            decision: .userApproved,
            reason: .mandatoryRiskLevel
        )
    )

    #expect(try await recorder.verifyIntegrity())

    var tampered = try await recorder.records()
    tampered[1].payload.event.toolName = "tampered"
    #expect(try ColonyToolAuditVerifier.verify(records: tampered, signer: signer) == false)
}

@Test("Filesystem audit log store is append-only and enforces sequence/hash linkage")
func fileSystemAuditStoreEnforcesAppendOnlyChain() async throws {
    let fs = ColonyInMemoryFileSystemBackend()
    let store = ColonyFileSystemToolAuditLogStore(
        filesystem: fs,
        pathPrefix: try ColonyVirtualPath("/audit/logs")
    )
    let signer = ColonyHMACSHA256ToolAuditSigner(keyData: Data("audit-key".utf8), keyID: "k1")
    let recorder = ColonyToolAuditRecorder(store: store, signer: signer)

    _ = try await recorder.record(
        event: ColonyToolAuditEvent(
            timestampNanoseconds: 1,
            threadID: "thread-audit",
            taskID: "task-1",
            toolCallID: "call-1",
            toolName: "write_file",
            riskLevel: .mutation,
            decision: .approvalRequired,
            reason: .mandatoryRiskLevel
        )
    )
    let second = try await recorder.record(
        event: ColonyToolAuditEvent(
            timestampNanoseconds: 2,
            threadID: "thread-audit",
            taskID: "task-1",
            toolCallID: "call-1",
            toolName: "write_file",
            riskLevel: .mutation,
            decision: .userApproved,
            reason: .mandatoryRiskLevel
        )
    )
    #expect(try await recorder.verifyIntegrity())

    let invalid = ColonySignedToolAuditRecord(
        payload: ColonyToolAuditRecordPayload(
            sequence: 2,
            previousEntryHash: second.entryHash,
            event: ColonyToolAuditEvent(
                timestampNanoseconds: 3,
                threadID: "thread-audit",
                taskID: "task-1",
                toolCallID: "call-2",
                toolName: "write_file",
                riskLevel: .mutation,
                decision: .userDenied,
                reason: .mandatoryRiskLevel
            )
        ),
        entryHash: second.entryHash,
        signatureBase64: second.signatureBase64,
        signatureAlgorithm: second.signatureAlgorithm,
        signerKeyID: second.signerKeyID
    )

    do {
        try await store.append(invalid)
        #expect(Bool(false))
    } catch let error as ColonyToolAuditError {
        switch error {
        case .invalidSequence:
            #expect(Bool(true))
        case .previousHashMismatch:
            #expect(Bool(false))
        }
    } catch {
        #expect(Bool(false))
    }
}

@Test("Runtime integration appends audit records for approval request and explicit deny decision")
func runtimeWritesAuditRecordsForToolApprovalFlow() async throws {
    let graph = try ColonyAgent.compile()
    let fs = ColonyInMemoryFileSystemBackend()

    let signer = ColonyHMACSHA256ToolAuditSigner(keyData: Data("audit-key".utf8), keyID: "k1")
    let store = ColonyInMemoryToolAuditLogStore()
    let recorder = ColonyToolAuditRecorder(store: store, signer: signer)

    let configuration = ColonyConfiguration(
        capabilities: [.filesystem],
        modelName: "test-model",
        toolApprovalPolicy: .never,
        toolAuditRecorder: recorder
    )
    let context = ColonyContext(configuration: configuration, filesystem: fs)

    let environment = HiveEnvironment(
        context: context,
        clock: SafetyNoopClock(),
        logger: SafetyNoopLogger(),
        model: AnyHiveModelClient(SingleMutatingCallModel()),
        checkpointStore: AnyHiveCheckpointStore(SafetyInMemoryCheckpointStore<ColonySchema>())
    )
    let runtime = HiveRuntime(graph: graph, environment: environment)
    let threadID = HiveThreadID("tool-audit-runtime")

    let handle = await runtime.run(
        threadID: threadID,
        input: "hi",
        options: HiveRunOptions(checkpointPolicy: .onInterrupt)
    )

    let outcome = try await handle.outcome.value
    guard case let .interrupted(interruption) = outcome else {
        #expect(Bool(false))
        return
    }

    var records = try await recorder.records()
    #expect(records.count == 1)
    #expect(records.first?.payload.event.decision == .approvalRequired)

    let resumed = await runtime.resume(
        threadID: threadID,
        interruptID: interruption.interrupt.id,
        payload: .toolApproval(decision: .rejected),
        options: HiveRunOptions(checkpointPolicy: .onInterrupt)
    )
    _ = try await resumed.outcome.value

    records = try await recorder.records()
    #expect(records.count == 2)
    #expect(records[0].payload.event.decision == .approvalRequired)
    #expect(records[1].payload.event.decision == .userDenied)
    #expect(try await recorder.verifyIntegrity())
}
