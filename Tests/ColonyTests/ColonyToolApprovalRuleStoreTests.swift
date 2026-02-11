import Foundation
import Testing
@testable import Colony

private final class RepeatingWriteModel: HiveModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private var invocationCount = 0

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        try await streamFinal(request)
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let response = self.nextResponse()
                continuation.yield(.final(response))
                continuation.finish()
            }
        }
    }

    private func nextResponse() -> HiveChatResponse {
        let count: Int = {
            lock.lock()
            defer { lock.unlock() }
            invocationCount += 1
            return invocationCount
        }()

        if count.isMultiple(of: 2) {
            return HiveChatResponse(
                message: HiveChatMessage(id: "assistant-\(count)", role: .assistant, content: "done")
            )
        }

        let fileIndex = (count + 1) / 2
        let call = HiveToolCall(
            id: "write-\(fileIndex)",
            name: "write_file",
            argumentsJSON: #"{"path":"/file-\#(fileIndex).md","content":"ok-\#(fileIndex)"}"#
        )
        return HiveChatResponse(
            message: HiveChatMessage(id: "assistant-\(count)", role: .assistant, content: "write", toolCalls: [call])
        )
    }
}

@Test("Tool approval rule store consumes allow-once rules")
func toolApprovalRuleStoreConsumesAllowOnceRules() async throws {
    let store = ColonyInMemoryToolApprovalRuleStore(
        rules: [
            ColonyToolApprovalRule(
                id: "once-write-file",
                pattern: .exact("write_file"),
                decision: .allowOnce
            )
        ]
    )

    let first = try await store.resolveDecision(forToolName: "write_file", consumeOneShot: true)
    #expect(first?.decision == .allowOnce)

    let second = try await store.resolveDecision(forToolName: "write_file", consumeOneShot: true)
    #expect(second == nil)
}

@Test("Persisted allow-always rule auto-approves mutating tool without interrupt")
func persistedAllowAlwaysRuleAutoApprovesMutatingTool() async throws {
    let fs = ColonyInMemoryFileSystemBackend()
    let store = ColonyInMemoryToolApprovalRuleStore(
        rules: [
            ColonyToolApprovalRule(
                id: "always-write",
                pattern: .exact("write_file"),
                decision: .allowAlways
            )
        ]
    )

    let runtime = try ColonyAgentFactory().makeRuntime(
        threadID: HiveThreadID("thread-rule-allow-always"),
        modelName: "test-model",
        model: AnyHiveModelClient(RepeatingWriteModel()),
        filesystem: fs,
        configure: { configuration in
            configuration.capabilities = [.filesystem]
            configuration.toolApprovalPolicy = .always
            configuration.toolApprovalRuleStore = store
        }
    )

    let handle = await runtime.sendUserMessage("write file")
    let outcome = try await handle.outcome.value

    guard case .finished = outcome else {
        #expect(Bool(false))
        return
    }

    let written = try await fs.read(at: ColonyVirtualPath("/file-1.md"))
    #expect(written == "ok-1")
}

@Test("Persisted reject-always rule denies mutating tool without interrupt")
func persistedRejectAlwaysRuleDeniesMutatingTool() async throws {
    let fs = ColonyInMemoryFileSystemBackend()
    let store = ColonyInMemoryToolApprovalRuleStore(
        rules: [
            ColonyToolApprovalRule(
                id: "reject-write",
                pattern: .exact("write_file"),
                decision: .rejectAlways
            )
        ]
    )

    let runtime = try ColonyAgentFactory().makeRuntime(
        threadID: HiveThreadID("thread-rule-reject-always"),
        modelName: "test-model",
        model: AnyHiveModelClient(RepeatingWriteModel()),
        filesystem: fs,
        configure: { configuration in
            configuration.capabilities = [.filesystem]
            configuration.toolApprovalPolicy = .always
            configuration.toolApprovalRuleStore = store
        }
    )

    let handle = await runtime.sendUserMessage("write file")
    let outcome = try await handle.outcome.value

    guard case .finished = outcome else {
        #expect(Bool(false))
        return
    }

    let missingPath = try ColonyVirtualPath("/file-1.md")
    await #expect(throws: ColonyFileSystemError.notFound(missingPath)) {
        _ = try await fs.read(at: missingPath)
    }
}

@Test("Persisted allow-once rule is consumed after one run")
func persistedAllowOnceRuleIsConsumedAfterOneRun() async throws {
    let fs = ColonyInMemoryFileSystemBackend()
    let store = ColonyInMemoryToolApprovalRuleStore(
        rules: [
            ColonyToolApprovalRule(
                id: "once-write",
                pattern: .exact("write_file"),
                decision: .allowOnce
            )
        ]
    )

    let runtime = try ColonyAgentFactory().makeRuntime(
        threadID: HiveThreadID("thread-rule-allow-once"),
        modelName: "test-model",
        model: AnyHiveModelClient(RepeatingWriteModel()),
        filesystem: fs,
        configure: { configuration in
            configuration.capabilities = [.filesystem]
            configuration.toolApprovalPolicy = .always
            configuration.toolApprovalRuleStore = store
        }
    )

    let first = await runtime.sendUserMessage("run one")
    let firstOutcome = try await first.outcome.value
    guard case .finished = firstOutcome else {
        #expect(Bool(false))
        return
    }

    let second = await runtime.sendUserMessage("run two")
    let secondOutcome = try await second.outcome.value

    guard case .interrupted = secondOutcome else {
        #expect(Bool(false))
        return
    }
}
