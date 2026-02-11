import Foundation
import Testing
@testable import Colony

private struct GitLSPNoopClock: HiveClock {
    func nowNanoseconds() -> UInt64 { 0 }
    func sleep(nanoseconds: UInt64) async throws { try await Task.sleep(nanoseconds: nanoseconds) }
}

private struct GitLSPNoopLogger: HiveLogger {
    func debug(_ message: String, metadata: [String: String]) {}
    func info(_ message: String, metadata: [String: String]) {}
    func error(_ message: String, metadata: [String: String]) {}
}

private final class GitLSPToolChainModel: HiveModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private var callIndex: Int = 0

    private static let toolCalls: [HiveToolCall] = [
        HiveToolCall(
            id: "git-status-1",
            name: ColonyBuiltInToolDefinitions.gitStatus.name,
            argumentsJSON: #"{"repo_path":"/repo","include_untracked":false}"#
        ),
        HiveToolCall(
            id: "git-diff-1",
            name: ColonyBuiltInToolDefinitions.gitDiff.name,
            argumentsJSON: #"{"repo_path":"/repo","base_ref":"origin/main","head_ref":"HEAD","pathspec":"Sources/App.swift","staged":true}"#
        ),
        HiveToolCall(
            id: "git-commit-1",
            name: ColonyBuiltInToolDefinitions.gitCommit.name,
            argumentsJSON: #"{"repo_path":"/repo","message":"Ship backend wiring","include_all":false,"amend":true,"signoff":true}"#
        ),
        HiveToolCall(
            id: "git-branch-1",
            name: ColonyBuiltInToolDefinitions.gitBranch.name,
            argumentsJSON: #"{"repo_path":"/repo","operation":"checkout","name":"feature/task-d","start_point":"origin/feature/task-d","force":true}"#
        ),
        HiveToolCall(
            id: "git-push-1",
            name: ColonyBuiltInToolDefinitions.gitPush.name,
            argumentsJSON: #"{"repo_path":"/repo","remote":"upstream","branch":"feature/task-d","set_upstream":true,"force_with_lease":true}"#
        ),
        HiveToolCall(
            id: "git-pr-1",
            name: ColonyBuiltInToolDefinitions.gitPreparePR.name,
            argumentsJSON: #"{"repo_path":"/repo","base_branch":"main","head_branch":"feature/task-d","title":"Task D: Git/LSP backends","body":"Implements typed backends and tool wiring.","draft":true}"#
        ),
        HiveToolCall(
            id: "lsp-symbols-1",
            name: ColonyBuiltInToolDefinitions.lspSymbols.name,
            argumentsJSON: #"{"path":"/Sources/App.swift","query":"Colony"}"#
        ),
        HiveToolCall(
            id: "lsp-diagnostics-1",
            name: ColonyBuiltInToolDefinitions.lspDiagnostics.name,
            argumentsJSON: #"{"path":"/Sources/App.swift"}"#
        ),
        HiveToolCall(
            id: "lsp-references-1",
            name: ColonyBuiltInToolDefinitions.lspReferences.name,
            argumentsJSON: #"{"path":"/Sources/App.swift","line":14,"character":7,"include_declaration":false}"#
        ),
        HiveToolCall(
            id: "lsp-edit-1",
            name: ColonyBuiltInToolDefinitions.lspApplyEdit.name,
            argumentsJSON: #"{"edits":[{"path":"/Sources/App.swift","start_line":1,"start_character":0,"end_line":1,"end_character":5,"new_text":"final"},{"path":"/Sources/App.swift","start_line":6,"start_character":4,"end_line":6,"end_character":10,"new_text":"runtime"}]}"#
        ),
    ]

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        try await streamFinal(request)
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.final(self.respond()))
                continuation.finish()
            }
        }
    }

    private func respond() -> HiveChatResponse {
        let index: Int = {
            lock.lock()
            defer { lock.unlock() }
            let current = callIndex
            callIndex += 1
            return current
        }()

        guard index < Self.toolCalls.count else {
            return HiveChatResponse(
                message: HiveChatMessage(id: "assistant-final", role: .assistant, content: "done")
            )
        }

        let call = Self.toolCalls[index]
        return HiveChatResponse(
            message: HiveChatMessage(
                id: "assistant-\(index)",
                role: .assistant,
                content: "run \(call.name)",
                toolCalls: [call]
            )
        )
    }
}

private final class ToolListRecordingModel: HiveModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [HiveChatRequest] = []

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        try await streamFinal(request)
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                self.lock.withLock {
                    self.requests.append(request)
                }

                continuation.yield(.final(HiveChatResponse(
                    message: HiveChatMessage(id: "assistant", role: .assistant, content: "done")
                )))
                continuation.finish()
            }
        }
    }

    func recordedRequests() -> [HiveChatRequest] {
        lock.withLock { requests }
    }
}

private actor RecordingGitBackend: ColonyGitBackend {
    private var statusRequests: [ColonyGitStatusRequest] = []
    private var diffRequests: [ColonyGitDiffRequest] = []
    private var commitRequests: [ColonyGitCommitRequest] = []
    private var branchRequests: [ColonyGitBranchRequest] = []
    private var pushRequests: [ColonyGitPushRequest] = []
    private var preparePRRequests: [ColonyGitPreparePullRequestRequest] = []

    func status(_ request: ColonyGitStatusRequest) async throws -> ColonyGitStatusResult {
        statusRequests.append(request)
        return ColonyGitStatusResult(
            currentBranch: "feature/task-d",
            upstreamBranch: "origin/feature/task-d",
            aheadBy: 2,
            behindBy: 1,
            entries: [
                ColonyGitStatusEntry(path: "Sources/App.swift", state: .modified),
                ColonyGitStatusEntry(path: "Tests/AppTests.swift", state: .added),
            ]
        )
    }

    func diff(_ request: ColonyGitDiffRequest) async throws -> ColonyGitDiffResult {
        diffRequests.append(request)
        return ColonyGitDiffResult(patch: "diff --git a/Sources/App.swift b/Sources/App.swift")
    }

    func commit(_ request: ColonyGitCommitRequest) async throws -> ColonyGitCommitResult {
        commitRequests.append(request)
        return ColonyGitCommitResult(commitHash: "abc1234", summary: request.message)
    }

    func branch(_ request: ColonyGitBranchRequest) async throws -> ColonyGitBranchResult {
        branchRequests.append(request)
        return ColonyGitBranchResult(
            currentBranch: "feature/task-d",
            branches: ["main", "feature/task-d"],
            detail: request.operation.rawValue
        )
    }

    func push(_ request: ColonyGitPushRequest) async throws -> ColonyGitPushResult {
        pushRequests.append(request)
        return ColonyGitPushResult(
            remote: request.remote,
            branch: request.branch ?? "feature/task-d",
            summary: "pushed"
        )
    }

    func preparePullRequest(_ request: ColonyGitPreparePullRequestRequest) async throws -> ColonyGitPreparePullRequestResult {
        preparePRRequests.append(request)
        return ColonyGitPreparePullRequestResult(
            baseBranch: request.baseBranch,
            headBranch: request.headBranch,
            title: request.title,
            body: request.body,
            draft: request.draft,
            summary: "ready"
        )
    }

    func recordedStatusRequests() -> [ColonyGitStatusRequest] { statusRequests }
    func recordedDiffRequests() -> [ColonyGitDiffRequest] { diffRequests }
    func recordedCommitRequests() -> [ColonyGitCommitRequest] { commitRequests }
    func recordedBranchRequests() -> [ColonyGitBranchRequest] { branchRequests }
    func recordedPushRequests() -> [ColonyGitPushRequest] { pushRequests }
    func recordedPreparePRRequests() -> [ColonyGitPreparePullRequestRequest] { preparePRRequests }
}

private actor RecordingLSPBackend: ColonyLSPBackend {
    private var symbolsRequests: [ColonyLSPSymbolsRequest] = []
    private var diagnosticsRequests: [ColonyLSPDiagnosticsRequest] = []
    private var referencesRequests: [ColonyLSPReferencesRequest] = []
    private var applyEditRequests: [ColonyLSPApplyEditRequest] = []

    func symbols(_ request: ColonyLSPSymbolsRequest) async throws -> [ColonyLSPSymbol] {
        symbolsRequests.append(request)
        return [
            ColonyLSPSymbol(
                name: "ColonyRuntime",
                kind: .class,
                path: try ColonyVirtualPath("/Sources/App.swift"),
                range: ColonyLSPRange(
                    start: ColonyLSPPosition(line: 10, character: 4),
                    end: ColonyLSPPosition(line: 10, character: 16)
                )
            ),
        ]
    }

    func diagnostics(_ request: ColonyLSPDiagnosticsRequest) async throws -> [ColonyLSPDiagnostic] {
        diagnosticsRequests.append(request)
        return [
            ColonyLSPDiagnostic(
                path: try ColonyVirtualPath("/Sources/App.swift"),
                range: ColonyLSPRange(
                    start: ColonyLSPPosition(line: 6, character: 8),
                    end: ColonyLSPPosition(line: 6, character: 20)
                ),
                severity: .warning,
                message: "Unused variable",
                code: "W001"
            ),
        ]
    }

    func references(_ request: ColonyLSPReferencesRequest) async throws -> [ColonyLSPReference] {
        referencesRequests.append(request)
        return [
            ColonyLSPReference(
                path: try ColonyVirtualPath("/Sources/App.swift"),
                range: ColonyLSPRange(
                    start: ColonyLSPPosition(line: 14, character: 7),
                    end: ColonyLSPPosition(line: 14, character: 19)
                ),
                preview: "runtime.sendUserMessage"
            ),
        ]
    }

    func applyEdit(_ request: ColonyLSPApplyEditRequest) async throws -> ColonyLSPApplyEditResult {
        applyEditRequests.append(request)
        return ColonyLSPApplyEditResult(appliedEditCount: request.edits.count, summary: "applied")
    }

    func recordedSymbolsRequests() -> [ColonyLSPSymbolsRequest] { symbolsRequests }
    func recordedDiagnosticsRequests() -> [ColonyLSPDiagnosticsRequest] { diagnosticsRequests }
    func recordedReferencesRequests() -> [ColonyLSPReferencesRequest] { referencesRequests }
    func recordedApplyEditRequests() -> [ColonyLSPApplyEditRequest] { applyEditRequests }
}

@Test("Git/LSP built-in tools dispatch to typed backends with decoded arguments")
func gitAndLspToolsDispatchToTypedBackends() async throws {
    let graph = try ColonyAgent.compile()
    let git = RecordingGitBackend()
    let lsp = RecordingLSPBackend()
    let repoPath = try ColonyVirtualPath("/repo")
    let sourcePath = try ColonyVirtualPath("/Sources/App.swift")

    let configuration = ColonyConfiguration(
        capabilities: [.git, .lsp],
        modelName: "test-model",
        toolApprovalPolicy: .never,
        mandatoryApprovalRiskLevels: []
    )
    let context = ColonyContext(
        configuration: configuration,
        filesystem: nil,
        git: git,
        lsp: lsp
    )

    let environment = HiveEnvironment<ColonySchema>(
        context: context,
        clock: GitLSPNoopClock(),
        logger: GitLSPNoopLogger(),
        model: AnyHiveModelClient(GitLSPToolChainModel())
    )

    let runtime = HiveRuntime(graph: graph, environment: environment)
    let handle = await runtime.run(
        threadID: HiveThreadID("thread-git-lsp-dispatch"),
        input: "Run all git/lsp tools",
        options: HiveRunOptions(maxSteps: 500, checkpointPolicy: .disabled)
    )
    let outcome = try await handle.outcome.value

    guard case let .finished(output, _) = outcome, case let .fullStore(store) = output else {
        #expect(Bool(false))
        return
    }

    #expect((try store.get(ColonySchema.Channels.finalAnswer)) == "done")

    let statusRequests = await git.recordedStatusRequests()
    #expect(statusRequests.count == 1)
    #expect(statusRequests.first?.repositoryPath == repoPath)
    #expect(statusRequests.first?.includeUntracked == false)

    let diffRequests = await git.recordedDiffRequests()
    #expect(diffRequests.count == 1)
    #expect(diffRequests.first?.baseRef == "origin/main")
    #expect(diffRequests.first?.headRef == "HEAD")
    #expect(diffRequests.first?.pathspec == "Sources/App.swift")
    #expect(diffRequests.first?.staged == true)

    let commitRequests = await git.recordedCommitRequests()
    #expect(commitRequests.count == 1)
    #expect(commitRequests.first?.message == "Ship backend wiring")
    #expect(commitRequests.first?.includeAll == false)
    #expect(commitRequests.first?.amend == true)
    #expect(commitRequests.first?.signoff == true)

    let branchRequests = await git.recordedBranchRequests()
    #expect(branchRequests.count == 1)
    #expect(branchRequests.first?.operation == .checkout)
    #expect(branchRequests.first?.name == "feature/task-d")
    #expect(branchRequests.first?.startPoint == "origin/feature/task-d")
    #expect(branchRequests.first?.force == true)

    let pushRequests = await git.recordedPushRequests()
    #expect(pushRequests.count == 1)
    #expect(pushRequests.first?.remote == "upstream")
    #expect(pushRequests.first?.branch == "feature/task-d")
    #expect(pushRequests.first?.setUpstream == true)
    #expect(pushRequests.first?.forceWithLease == true)

    let prRequests = await git.recordedPreparePRRequests()
    #expect(prRequests.count == 1)
    #expect(prRequests.first?.baseBranch == "main")
    #expect(prRequests.first?.headBranch == "feature/task-d")
    #expect(prRequests.first?.title == "Task D: Git/LSP backends")
    #expect(prRequests.first?.body == "Implements typed backends and tool wiring.")
    #expect(prRequests.first?.draft == true)

    let symbolsRequests = await lsp.recordedSymbolsRequests()
    #expect(symbolsRequests.count == 1)
    #expect(symbolsRequests.first?.path == sourcePath)
    #expect(symbolsRequests.first?.query == "Colony")

    let diagnosticsRequests = await lsp.recordedDiagnosticsRequests()
    #expect(diagnosticsRequests.count == 1)
    #expect(diagnosticsRequests.first?.path == sourcePath)

    let referencesRequests = await lsp.recordedReferencesRequests()
    #expect(referencesRequests.count == 1)
    #expect(referencesRequests.first?.path == sourcePath)
    #expect(referencesRequests.first?.position == ColonyLSPPosition(line: 14, character: 7))
    #expect(referencesRequests.first?.includeDeclaration == false)

    let applyEditRequests = await lsp.recordedApplyEditRequests()
    #expect(applyEditRequests.count == 1)
    #expect(applyEditRequests.first?.edits.count == 2)
    #expect(applyEditRequests.first?.edits.first?.path == sourcePath)
    #expect(applyEditRequests.first?.edits.first?.range.start == ColonyLSPPosition(line: 1, character: 0))
    #expect(applyEditRequests.first?.edits.first?.range.end == ColonyLSPPosition(line: 1, character: 5))
    #expect(applyEditRequests.first?.edits.first?.newText == "final")
}

@Test("Git/LSP tools are advertised only when capability and backend are both present")
func gitAndLspToolsAdvertisedWithBackendWiring() async throws {
    let graph = try ColonyAgent.compile()
    let model = ToolListRecordingModel()

    let context = ColonyContext(
        configuration: ColonyConfiguration(capabilities: [.git, .lsp], modelName: "test-model", toolApprovalPolicy: .never),
        filesystem: nil,
        git: RecordingGitBackend(),
        lsp: RecordingLSPBackend()
    )

    let environment = HiveEnvironment<ColonySchema>(
        context: context,
        clock: GitLSPNoopClock(),
        logger: GitLSPNoopLogger(),
        model: AnyHiveModelClient(model)
    )
    let runtime = HiveRuntime(graph: graph, environment: environment)

    let handle = await runtime.run(
        threadID: HiveThreadID("thread-git-lsp-advertised"),
        input: "hello",
        options: HiveRunOptions(checkpointPolicy: .disabled)
    )
    _ = try await handle.outcome.value

    let toolNames = Set(model.recordedRequests().first?.tools.map(\.name) ?? [])
    #expect(toolNames.contains("git_status"))
    #expect(toolNames.contains("git_diff"))
    #expect(toolNames.contains("git_commit"))
    #expect(toolNames.contains("git_branch"))
    #expect(toolNames.contains("git_push"))
    #expect(toolNames.contains("git_prepare_pr"))
    #expect(toolNames.contains("lsp_symbols"))
    #expect(toolNames.contains("lsp_diagnostics"))
    #expect(toolNames.contains("lsp_references"))
    #expect(toolNames.contains("lsp_apply_edit"))
}

@Test("Git/LSP tools are not advertised when backends are missing")
func gitAndLspToolsNotAdvertisedWithoutBackends() async throws {
    let graph = try ColonyAgent.compile()
    let model = ToolListRecordingModel()

    let context = ColonyContext(
        configuration: ColonyConfiguration(capabilities: [.git, .lsp], modelName: "test-model", toolApprovalPolicy: .never),
        filesystem: nil
    )

    let environment = HiveEnvironment<ColonySchema>(
        context: context,
        clock: GitLSPNoopClock(),
        logger: GitLSPNoopLogger(),
        model: AnyHiveModelClient(model)
    )
    let runtime = HiveRuntime(graph: graph, environment: environment)

    let handle = await runtime.run(
        threadID: HiveThreadID("thread-git-lsp-not-advertised"),
        input: "hello",
        options: HiveRunOptions(checkpointPolicy: .disabled)
    )
    _ = try await handle.outcome.value

    let toolNames = Set(model.recordedRequests().first?.tools.map(\.name) ?? [])
    #expect(toolNames.contains("git_status") == false)
    #expect(toolNames.contains("git_diff") == false)
    #expect(toolNames.contains("git_commit") == false)
    #expect(toolNames.contains("git_branch") == false)
    #expect(toolNames.contains("git_push") == false)
    #expect(toolNames.contains("git_prepare_pr") == false)
    #expect(toolNames.contains("lsp_symbols") == false)
    #expect(toolNames.contains("lsp_diagnostics") == false)
    #expect(toolNames.contains("lsp_references") == false)
    #expect(toolNames.contains("lsp_apply_edit") == false)
}
