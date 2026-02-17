import Foundation
import HiveCore
import ColonyCore

public enum ColonyGatewayRuntimeError: Error, Sendable, Equatable {
    case sessionNotFound(ColonyRuntimeSessionID)
    case noPendingInterrupt(runID: UUID)
    case parentRunNotFound(UUID)
}

public enum ColonyGatewayRunResult: Sendable, Equatable {
    case completed(finalAnswer: String?)
    case interrupted(reason: ColonyInterruptionReason, interruptID: HiveInterruptID?)
    case cancelled(reason: ColonyInterruptionReason)
    case failed(message: String)
    case reused(existingRunID: UUID)
}

public struct ColonyGatewayBackends: Sendable {
    public var filesystem: (any ColonyFileSystemBackend)?
    public var shell: (any ColonyShellBackend)?
    public var git: (any ColonyGitBackend)?
    public var lsp: (any ColonyLSPBackend)?
    public var applyPatch: (any ColonyApplyPatchBackend)?
    public var webSearch: (any ColonyWebSearchBackend)?
    public var codeSearch: (any ColonyCodeSearchBackend)?
    public var mcp: (any ColonyMCPBackend)?
    public var memory: (any ColonyMemoryBackend)?
    public var plugins: (any ColonyPluginToolRegistry)?
    public var subagents: (any ColonySubagentRegistry)?

    public init(
        filesystem: (any ColonyFileSystemBackend)? = nil,
        shell: (any ColonyShellBackend)? = nil,
        git: (any ColonyGitBackend)? = nil,
        lsp: (any ColonyLSPBackend)? = nil,
        applyPatch: (any ColonyApplyPatchBackend)? = nil,
        webSearch: (any ColonyWebSearchBackend)? = nil,
        codeSearch: (any ColonyCodeSearchBackend)? = nil,
        mcp: (any ColonyMCPBackend)? = nil,
        memory: (any ColonyMemoryBackend)? = nil,
        plugins: (any ColonyPluginToolRegistry)? = nil,
        subagents: (any ColonySubagentRegistry)? = nil
    ) {
        self.filesystem = filesystem
        self.shell = shell
        self.git = git
        self.lsp = lsp
        self.applyPatch = applyPatch
        self.webSearch = webSearch
        self.codeSearch = codeSearch
        self.mcp = mcp
        self.memory = memory
        self.plugins = plugins
        self.subagents = subagents
    }
}

public struct ColonyGatewayRuntimeConfiguration: Sendable {
    public var profile: ColonyProfile
    public var lane: ColonyLane?
    public var agentID: String
    public var providers: ColonyProviderRoutingConfiguration
    public var defaultExecutionPolicy: ColonyExecutionPolicy
    public var providerRegistry: any ColonyProviderRegistry
    public var sessionStore: any ColonyRuntimeSessionStore
    public var checkpointStore: (any ColonyRuntimeCheckpointStore)?
    public var toolRegistry: ColonyRuntimeToolRegistry?
    public var messageSink: (any ColonyMessageSink)?
    public var runOptionsOverride: HiveRunOptions?

    public init(
        profile: ColonyProfile = .onDevice4k,
        lane: ColonyLane? = nil,
        agentID: String = "colony-agent",
        providers: ColonyProviderRoutingConfiguration,
        defaultExecutionPolicy: ColonyExecutionPolicy = ColonyExecutionPolicy(),
        providerRegistry: any ColonyProviderRegistry,
        sessionStore: any ColonyRuntimeSessionStore,
        checkpointStore: (any ColonyRuntimeCheckpointStore)? = nil,
        toolRegistry: ColonyRuntimeToolRegistry? = nil,
        messageSink: (any ColonyMessageSink)? = nil,
        runOptionsOverride: HiveRunOptions? = nil
    ) {
        self.profile = profile
        self.lane = lane
        self.agentID = agentID
        self.providers = providers
        self.defaultExecutionPolicy = defaultExecutionPolicy
        self.providerRegistry = providerRegistry
        self.sessionStore = sessionStore
        self.checkpointStore = checkpointStore
        self.toolRegistry = toolRegistry
        self.messageSink = messageSink
        self.runOptionsOverride = runOptionsOverride
    }
}

public struct ColonyGatewayRunRequest: Sendable {
    public var sessionID: ColonyRuntimeSessionID?
    public var input: String
    public var providerOverride: ColonyProviderSelection?
    public var executionPolicyOverride: ColonyExecutionPolicy?
    public var idempotencyKey: String?
    public var metadata: [String: String]

    public init(
        sessionID: ColonyRuntimeSessionID? = nil,
        input: String,
        providerOverride: ColonyProviderSelection? = nil,
        executionPolicyOverride: ColonyExecutionPolicy? = nil,
        idempotencyKey: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.sessionID = sessionID
        self.input = input
        self.providerOverride = providerOverride
        self.executionPolicyOverride = executionPolicyOverride
        self.idempotencyKey = idempotencyKey
        self.metadata = metadata
    }
}

public struct ColonyGatewayRunHandle: Sendable {
    public let runID: UUID
    public let sessionID: ColonyRuntimeSessionID

    private let run: ColonyGatewayManagedRun
    private let eventBus: ColonyRuntimeEventBus

    fileprivate init(
        runID: UUID,
        sessionID: ColonyRuntimeSessionID,
        run: ColonyGatewayManagedRun,
        eventBus: ColonyRuntimeEventBus
    ) {
        self.runID = runID
        self.sessionID = sessionID
        self.run = run
        self.eventBus = eventBus
    }

    public func awaitResult() async -> ColonyGatewayRunResult {
        await run.awaitResult()
    }

    public func cancel(reason: ColonyInterruptionReason = .userRequestedStop) async -> Bool {
        await run.cancel(reason: reason)
    }

    public func pendingInterruptID() async -> HiveInterruptID? {
        await run.pendingInterruptID()
    }

    public func resumeToolApproval(_ decision: ColonyToolApprovalDecision) async throws {
        try await run.resumeToolApproval(decision)
    }

    public func events(bufferingLimit: Int = 256) async -> AsyncStream<ColonyRuntimeEvent> {
        let source = await eventBus.subscribe(bufferingLimit: bufferingLimit)
        let runID = self.runID
        return AsyncStream(bufferingPolicy: .bufferingNewest(max(1, bufferingLimit))) { continuation in
            let task = Task {
                for await event in source {
                    if event.runID == runID || event.correlationChain.contains(runID.uuidString.lowercased()) {
                        continuation.yield(event)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

public actor ColonyGatewayRuntime {
    private struct RunMetadata: Sendable {
        var sessionID: ColonyRuntimeSessionID
        var providerSelection: ColonyProviderSelection?
        var executionPolicy: ColonyExecutionPolicy
    }

    private let configuration: ColonyGatewayRuntimeConfiguration
    private let backends: ColonyGatewayBackends
    private let eventBus: ColonyRuntimeEventBus

    private var activeRuns: [UUID: ColonyGatewayManagedRun] = [:]
    private var runMetadata: [UUID: RunMetadata] = [:]
    private var subagentObserverTasks: [String: Task<Void, Never>] = [:]

    public init(
        configuration: ColonyGatewayRuntimeConfiguration,
        backends: ColonyGatewayBackends = ColonyGatewayBackends(),
        eventBus: ColonyRuntimeEventBus = ColonyRuntimeEventBus()
    ) {
        self.configuration = configuration
        self.backends = backends
        self.eventBus = eventBus
    }

    public func events(bufferingLimit: Int = 256) async -> AsyncStream<ColonyRuntimeEvent> {
        await eventBus.subscribe(bufferingLimit: bufferingLimit)
    }

    public func recentEvents(limit: Int = 200) async -> [ColonyRuntimeEvent] {
        await eventBus.recent(limit: limit)
    }

    public func resumeSession(
        sessionID: ColonyRuntimeSessionID,
        input: String,
        providerOverride: ColonyProviderSelection? = nil,
        executionPolicyOverride: ColonyExecutionPolicy? = nil,
        idempotencyKey: String? = nil
    ) async throws -> ColonyGatewayRunHandle {
        try await startRun(
            ColonyGatewayRunRequest(
                sessionID: sessionID,
                input: input,
                providerOverride: providerOverride,
                executionPolicyOverride: executionPolicyOverride,
                idempotencyKey: idempotencyKey
            )
        )
    }

    @discardableResult
    public func cancelRun(
        runID: UUID,
        reason: ColonyInterruptionReason = .userRequestedStop
    ) async -> Bool {
        guard let run = activeRuns[runID] else {
            return false
        }
        return await run.cancel(reason: reason)
    }

    public func resumeInterruptedRun(
        runID: UUID,
        decision: ColonyToolApprovalDecision
    ) async throws {
        guard let run = activeRuns[runID] else {
            throw ColonyGatewayRuntimeError.noPendingInterrupt(runID: runID)
        }
        try await run.resumeToolApproval(decision)
    }

    public func startRun(_ request: ColonyGatewayRunRequest) async throws -> ColonyGatewayRunHandle {
        let session = try await upsertSession(for: request.sessionID, metadata: request.metadata)

        if let idempotencyKey = request.idempotencyKey,
           let existingRunID = try await configuration.sessionStore.runID(forIdempotencyKey: idempotencyKey, sessionID: session.sessionID)
        {
            if let active = activeRuns[existingRunID] {
                return ColonyGatewayRunHandle(
                    runID: existingRunID,
                    sessionID: session.sessionID,
                    run: active,
                    eventBus: eventBus
                )
            }

            let reused = ColonyGatewayManagedRun(
                runID: existingRunID,
                sessionID: session.sessionID,
                agentID: configuration.agentID,
                runtime: nil,
                executionPolicy: request.executionPolicyOverride ?? configuration.defaultExecutionPolicy,
                eventBus: eventBus,
                sessionStore: configuration.sessionStore,
                messageSink: configuration.messageSink,
                toolRegistry: nil,
                onTerminal: { _ in }
            )
            await reused.setImmediateResult(.reused(existingRunID: existingRunID))

            return ColonyGatewayRunHandle(
                runID: existingRunID,
                sessionID: session.sessionID,
                run: reused,
                eventBus: eventBus
            )
        }

        let executionPolicy = request.executionPolicyOverride ?? configuration.defaultExecutionPolicy
        let runtimeArtifacts = try await makeRuntime(
            session: session,
            executionPolicy: executionPolicy,
            providerOverride: request.providerOverride
        )

        try await configuration.sessionStore.appendMessage(
            ColonyRuntimeMessage(role: .user, content: request.input),
            sessionID: session.sessionID
        )

        let hiveHandle = await runtimeArtifacts.runtime.sendUserMessage(request.input)
        let runID = hiveHandle.runID.rawValue

        runtimeArtifacts.toolRegistry?.updateContextProvider {
            ColonyToolExecutionContext(
                runID: runID,
                sessionID: session.sessionID,
                agentID: self.configuration.agentID,
                executionPolicy: executionPolicy,
                correlationChain: [
                    session.sessionID.rawValue,
                    runID.uuidString.lowercased(),
                ]
            )
        }

        let managed = ColonyGatewayManagedRun(
            runID: runID,
            sessionID: session.sessionID,
            agentID: configuration.agentID,
            runtime: runtimeArtifacts.runtime,
            executionPolicy: executionPolicy,
            eventBus: eventBus,
            sessionStore: configuration.sessionStore,
            messageSink: configuration.messageSink,
            toolRegistry: runtimeArtifacts.toolRegistry,
            onTerminal: { [runtime = self] finishedRunID in
                await runtime.handleTerminalRun(finishedRunID)
            }
        )

        activeRuns[runID] = managed
        runMetadata[runID] = RunMetadata(
            sessionID: session.sessionID,
            providerSelection: request.providerOverride,
            executionPolicy: executionPolicy
        )

        if let idempotencyKey = request.idempotencyKey {
            try await configuration.sessionStore.recordRunID(
                runID,
                forIdempotencyKey: idempotencyKey,
                sessionID: session.sessionID
            )
        }

        await managed.start(with: hiveHandle)

        return ColonyGatewayRunHandle(
            runID: runID,
            sessionID: session.sessionID,
            run: managed,
            eventBus: eventBus
        )
    }

    public func spawnSubagent(_ request: ColonySpawnRequest) async throws -> ColonySpawnResult {
        guard let parentMetadata = runMetadata[request.parentRunID] else {
            throw ColonyGatewayRuntimeError.parentRunNotFound(request.parentRunID)
        }

        let subagentID = request.subagentID ?? ("subagent:" + UUID().uuidString.lowercased())
        let childSessionID: ColonyRuntimeSessionID = request.isolateContext
            ? ColonyRuntimeSessionID(rawValue: "session:subagent:" + UUID().uuidString.lowercased())
            : request.parentSessionID

        let childRequest = ColonyGatewayRunRequest(
            sessionID: childSessionID,
            input: request.prompt,
            providerOverride: request.providerOverride ?? parentMetadata.providerSelection,
            executionPolicyOverride: request.executionPolicyOverride ?? parentMetadata.executionPolicy,
            idempotencyKey: nil
        )
        let childRun = try await startRun(childRequest)

        let parentCorrelation = [
            request.parentRunID.uuidString.lowercased(),
            subagentID,
            childRun.runID.uuidString.lowercased(),
        ]

        _ = await eventBus.emit(
            kind: .subagentStarted,
            runID: request.parentRunID,
            sessionID: request.parentSessionID,
            agentID: configuration.agentID,
            subagentID: subagentID,
            correlationChain: parentCorrelation,
            payload: .subagent(
                ColonyRuntimeSubagentPayload(
                    subagentID: subagentID,
                    childRunID: childRun.runID,
                    state: .started
                )
            )
        )

        if let sink = configuration.messageSink {
            await sink.publish(
                ColonyRoutedMessage(
                    target: .parentContext,
                    content: "Subagent \(subagentID) started.",
                    runID: request.parentRunID,
                    sessionID: request.parentSessionID,
                    agentID: configuration.agentID,
                    subagentID: subagentID
                )
            )
        }

        let handle = ColonySubagentHandle(
            subagentID: subagentID,
            runID: childRun.runID,
            sessionID: childRun.sessionID,
            awaitResult: {
                await childRun.awaitResult()
            },
            cancel: {
                await childRun.cancel(reason: .userRequestedStop)
            }
        )

        subagentObserverTasks[subagentID] = Task { [weak self] in
            let outcome = await childRun.awaitResult()
            guard let self else { return }

            let state: ColonySubagentLifecycleState
            switch outcome {
            case .completed:
                state = .completed
            case .interrupted:
                state = .interrupted
            case .cancelled, .failed:
                state = .failed
            case .reused:
                state = .completed
            }

            await handle.setState(state)

            _ = await self.eventBus.emit(
                kind: .subagentCompleted,
                runID: request.parentRunID,
                sessionID: request.parentSessionID,
                agentID: self.configuration.agentID,
                subagentID: subagentID,
                correlationChain: parentCorrelation,
                payload: .subagent(
                    ColonyRuntimeSubagentPayload(
                        subagentID: subagentID,
                        childRunID: childRun.runID,
                        state: state
                    )
                )
            )

            if let sink = self.configuration.messageSink {
                await sink.publish(
                    ColonyRoutedMessage(
                        target: .parentContext,
                        content: "Subagent \(subagentID) \(state.rawValue).",
                        runID: request.parentRunID,
                        sessionID: request.parentSessionID,
                        agentID: self.configuration.agentID,
                        subagentID: subagentID
                    )
                )
            }

            await self.removeSubagentObserver(subagentID)
        }

        return ColonySpawnResult(
            subagentID: subagentID,
            childRunID: childRun.runID,
            childSessionID: childRun.sessionID,
            handle: handle
        )
    }

    private func makeRuntime(
        session: ColonyRuntimeSessionRecord,
        executionPolicy: ColonyExecutionPolicy,
        providerOverride: ColonyProviderSelection?
    ) async throws -> (runtime: ColonyRuntime, toolRegistry: ColonyRuntimeToolRegistry?) {
        let agentID = configuration.agentID
        let runOptionsOverride = configuration.runOptionsOverride

        let resolvedProviders = try await configuration.providerRegistry.resolve(
            defaultProviderName: configuration.providers.defaultProviderName,
            defaultFallbackProviderNames: configuration.providers.fallbackProviderNames,
            selection: providerOverride
        )

        let modelName = resolvedProviders.first?.profile.model
            ?? configuration.providers.defaultProviderName

        let routerProviders = resolvedProviders.enumerated().map { index, provider in
            ColonyProviderRouter.Provider(
                id: provider.profile.name,
                client: provider.client,
                priority: index
            )
        }
        let router = ColonyProviderRouter(
            providers: routerProviders,
            policy: configuration.providers.policy
        )

        let filesystem = backends.filesystem.map {
            ColonyPolicyAwareFileSystemBackend(base: $0, policy: executionPolicy)
        }
        let shell = backends.shell.map {
            ColonyPolicyAwareShellBackend(base: $0, policy: executionPolicy)
        }

        let toolRegistry = configuration.toolRegistry?.clone(
            contextProvider: {
                ColonyToolExecutionContext(
                    runID: UUID(),
                    sessionID: session.sessionID,
                    agentID: agentID,
                    executionPolicy: executionPolicy,
                    correlationChain: [session.sessionID.rawValue]
                )
            }
        )
        let externalTools = toolRegistry.map { registry in
            AnyHiveToolRegistry(registry)
        }

        let checkpointStoreBridge: AnyHiveCheckpointStore<ColonySchema>? = configuration.checkpointStore.map { store in
            AnyHiveCheckpointStore(ColonyRuntimeCheckpointStoreBridge(store: store))
        }

        let runtime = try ColonyAgentFactory().makeRuntime(
            profile: configuration.profile,
            threadID: HiveThreadID(session.threadID),
            modelName: modelName,
            lane: configuration.lane,
            model: nil,
            modelRouter: router,
            inferenceHints: nil,
            tools: externalTools,
            filesystem: filesystem,
            shell: shell,
            git: backends.git,
            lsp: backends.lsp,
            applyPatch: backends.applyPatch,
            webSearch: backends.webSearch,
            codeSearch: backends.codeSearch,
            mcp: backends.mcp,
            memory: backends.memory,
            plugins: backends.plugins,
            subagents: backends.subagents,
            checkpointStore: checkpointStoreBridge,
            durableCheckpointDirectoryURL: nil,
            configure: { _ in },
            configureRunOptions: { options in
                if let override = runOptionsOverride {
                    options = override
                }
            }
        )
        return (runtime: runtime, toolRegistry: toolRegistry)
    }

    private func upsertSession(
        for maybeSessionID: ColonyRuntimeSessionID?,
        metadata: [String: String]
    ) async throws -> ColonyRuntimeSessionRecord {
        let sessionID = maybeSessionID ?? ColonyRuntimeSessionID(
            rawValue: "session:" + UUID().uuidString.lowercased()
        )

        if let existing = try await configuration.sessionStore.getSession(id: sessionID) {
            return existing
        }

        let now = Date()
        let threadID = "colony:\(sessionID.rawValue)"
        let session = ColonyRuntimeSessionRecord(
            sessionID: sessionID,
            threadID: threadID,
            createdAt: now,
            updatedAt: now,
            metadata: metadata
        )
        try await configuration.sessionStore.createSession(session)
        return session
    }

    /// Gracefully tears down the runtime, cancelling all active subagent observers.
    public func shutdown() {
        for (_, task) in subagentObserverTasks {
            task.cancel()
        }
        subagentObserverTasks.removeAll()
    }

    private func removeSubagentObserver(_ subagentID: String) {
        subagentObserverTasks.removeValue(forKey: subagentID)
    }

    private func handleTerminalRun(_ runID: UUID) {
        activeRuns.removeValue(forKey: runID)
    }
}

private actor ColonyGatewayManagedRun {
    private let runID: UUID
    private let sessionID: ColonyRuntimeSessionID
    private let agentID: String
    private let runtime: ColonyRuntime?
    private let executionPolicy: ColonyExecutionPolicy
    private let eventBus: ColonyRuntimeEventBus
    private let sessionStore: any ColonyRuntimeSessionStore
    private let messageSink: (any ColonyMessageSink)?
    private let toolRegistry: ColonyRuntimeToolRegistry?
    private let onTerminal: @Sendable (UUID) async -> Void

    private var currentHandle: HiveRunHandle<ColonySchema>?
    private var eventTask: Task<Void, Never>?
    private var outcomeTask: Task<Void, Never>?
    private var pendingInterrupt: HiveInterruptID?
    private var finalResult: ColonyGatewayRunResult?
    private var waiters: [CheckedContinuation<ColonyGatewayRunResult, Never>] = []
    private var assistantBuffer: String = ""
    private var cancelRequested: Bool = false
    private var terminalTransitionInFlight: Bool = false

    init(
        runID: UUID,
        sessionID: ColonyRuntimeSessionID,
        agentID: String,
        runtime: ColonyRuntime?,
        executionPolicy: ColonyExecutionPolicy,
        eventBus: ColonyRuntimeEventBus,
        sessionStore: any ColonyRuntimeSessionStore,
        messageSink: (any ColonyMessageSink)?,
        toolRegistry: ColonyRuntimeToolRegistry?,
        onTerminal: @escaping @Sendable (UUID) async -> Void
    ) {
        self.runID = runID
        self.sessionID = sessionID
        self.agentID = agentID
        self.runtime = runtime
        self.executionPolicy = executionPolicy
        self.eventBus = eventBus
        self.sessionStore = sessionStore
        self.messageSink = messageSink
        self.toolRegistry = toolRegistry
        self.onTerminal = onTerminal
    }

    func setImmediateResult(_ result: ColonyGatewayRunResult) {
        finalResult = result
        terminalTransitionInFlight = false
    }

    func start(with handle: HiveRunHandle<ColonySchema>) async {
        currentHandle = handle
        cancelRequested = false
        pendingInterrupt = nil
        finalResult = nil
        terminalTransitionInFlight = false
        assistantBuffer = ""

        _ = await eventBus.emit(
            kind: .runStarted,
            runID: runID,
            sessionID: sessionID,
            agentID: agentID,
            correlationChain: [sessionID.rawValue, runID.uuidString.lowercased()]
        )

        eventTask?.cancel()
        outcomeTask?.cancel()

        eventTask = Task {
            do {
                for try await event in handle.events {
                    await self.process(event: event)
                }
            } catch {
                await self.finishWithError(error)
            }
        }

        outcomeTask = Task {
            do {
                let outcome = try await handle.outcome.value
                await self.process(outcome: outcome)
            } catch is CancellationError {
                await self.processCancellation(reason: .userRequestedStop)
            } catch {
                await self.finishWithError(error)
            }
        }
    }

    func awaitResult() async -> ColonyGatewayRunResult {
        if let finalResult {
            return finalResult
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func pendingInterruptID() -> HiveInterruptID? {
        pendingInterrupt
    }

    func resumeToolApproval(_ decision: ColonyToolApprovalDecision) async throws {
        guard let runtime else {
            throw ColonyGatewayRuntimeError.noPendingInterrupt(runID: runID)
        }
        guard let pendingInterrupt else {
            throw ColonyGatewayRuntimeError.noPendingInterrupt(runID: runID)
        }

        self.pendingInterrupt = nil
        finalResult = nil
        terminalTransitionInFlight = false
        assistantBuffer = ""

        let resumed = await runtime.resumeToolApproval(
            interruptID: pendingInterrupt,
            decision: decision
        )

        await startAttemptFromResume(resumed)
    }

    func cancel(reason: ColonyInterruptionReason) async -> Bool {
        if cancelRequested {
            return false
        }
        if let finalResult, Self.isTerminal(finalResult) {
            return false
        }

        cancelRequested = true
        eventTask?.cancel()
        outcomeTask?.cancel()
        currentHandle?.outcome.cancel()

        await processCancellation(reason: reason)
        return true
    }

    private func startAttemptFromResume(_ handle: HiveRunHandle<ColonySchema>) async {
        currentHandle = handle
        cancelRequested = false
        terminalTransitionInFlight = false

        eventTask?.cancel()
        outcomeTask?.cancel()

        eventTask = Task {
            do {
                for try await event in handle.events {
                    await self.process(event: event)
                }
            } catch {
                await self.finishWithError(error)
            }
        }

        outcomeTask = Task {
            do {
                let outcome = try await handle.outcome.value
                await self.process(outcome: outcome)
            } catch is CancellationError {
                await self.processCancellation(reason: .userRequestedStop)
            } catch {
                await self.finishWithError(error)
            }
        }
    }

    private func process(event: HiveEvent) async {
        switch event.kind {
        case .modelToken(let token):
            assistantBuffer.append(token)
            if let sink = messageSink {
                await sink.publish(
                    ColonyRoutedMessage(
                        target: .userChannelOutput,
                        content: token,
                        runID: runID,
                        sessionID: sessionID,
                        agentID: agentID
                    )
                )
            }

        case .toolInvocationStarted(let toolName):
            let toolCallID = event.metadata["toolCallID"] ?? ""
            _ = await eventBus.emit(
                kind: .toolDispatched,
                runID: runID,
                sessionID: sessionID,
                agentID: agentID,
                correlationChain: [sessionID.rawValue, runID.uuidString.lowercased(), toolCallID],
                payload: .toolDispatched(
                    ColonyRuntimeToolDispatchedPayload(
                        toolCallID: toolCallID,
                        toolName: toolName
                    )
                )
            )

            if let sink = messageSink {
                await sink.publish(
                    ColonyRoutedMessage(
                        target: .backgroundLog,
                        content: "Tool dispatched: \(toolName) (\(toolCallID))",
                        runID: runID,
                        sessionID: sessionID,
                        agentID: agentID
                    )
                )
            }

        case .toolInvocationFinished(let toolName, let success):
            let toolCallID = event.metadata["toolCallID"] ?? ""
            let fallbackEnvelope = ColonyToolResultEnvelope(
                success: success,
                payload: success ? "OK" : "Error",
                errorCode: success ? nil : "tool_failed",
                errorType: success ? nil : "tool_failure",
                artifacts: [],
                attemptCount: 1,
                durationMilliseconds: 0,
                requestID: toolCallID.isEmpty ? UUID().uuidString.lowercased() : toolCallID
            )
            let envelope = toolRegistry?.resultEnvelope(forToolCallID: toolCallID) ?? fallbackEnvelope

            _ = await eventBus.emit(
                kind: .toolResult,
                runID: runID,
                sessionID: sessionID,
                agentID: agentID,
                correlationChain: [sessionID.rawValue, runID.uuidString.lowercased(), toolCallID],
                payload: .toolResult(
                    ColonyRuntimeToolResultPayload(
                        toolCallID: toolCallID,
                        toolName: toolName,
                        result: envelope
                    )
                )
            )

            if let sink = messageSink {
                await sink.publish(
                    ColonyRoutedMessage(
                        target: .backgroundLog,
                        content: "Tool result: \(toolName) (\(toolCallID)) success=\(envelope.success)",
                        runID: runID,
                        sessionID: sessionID,
                        agentID: agentID
                    )
                )
            }

        default:
            break
        }
    }

    private func process(outcome: HiveRunOutcome<ColonySchema>) async {
        guard hasTerminalResult == false, terminalTransitionInFlight == false else {
            return
        }

        switch outcome {
        case .finished(let output, _):
            guard beginTerminalTransition() else {
                return
            }
            let finalAnswer: String? = {
                if case let .fullStore(store) = output {
                    return try? store.get(ColonySchema.Channels.finalAnswer)
                }
                return nil
            }() ?? (assistantBuffer.isEmpty ? nil : assistantBuffer)
            if let finalAnswer {
                // Best-effort persistence: the run already completed successfully, so a
                // session store write failure should not retroactively fail the run result.
                // Callers observe the final answer via the returned ColonyGatewayRunResult.
                try? await sessionStore.appendMessage(
                    ColonyRuntimeMessage(role: .assistant, content: finalAnswer),
                    sessionID: sessionID
                )
            }
            _ = await eventBus.emit(
                kind: .runCompleted,
                runID: runID,
                sessionID: sessionID,
                agentID: agentID,
                correlationChain: [sessionID.rawValue, runID.uuidString.lowercased()],
                payload: .completion(
                    ColonyRuntimeCompletionPayload(
                        status: "completed",
                        finalAnswer: finalAnswer
                    )
                )
            )
            finalize(.completed(finalAnswer: finalAnswer), cleanup: true)

        case .outOfSteps(_, _, _):
            guard beginTerminalTransition() else {
                return
            }
            let reason: ColonyInterruptionReason = .timeout
            _ = await eventBus.emit(
                kind: .runInterrupted,
                runID: runID,
                sessionID: sessionID,
                agentID: agentID,
                correlationChain: [sessionID.rawValue, runID.uuidString.lowercased()],
                payload: .interruption(
                    ColonyRuntimeInterruptionPayload(
                        reason: reason,
                        classification: reason.classification,
                        interruptID: nil
                    )
                )
            )
            _ = await eventBus.emit(
                kind: .runCompleted,
                runID: runID,
                sessionID: sessionID,
                agentID: agentID,
                correlationChain: [sessionID.rawValue, runID.uuidString.lowercased()],
                payload: .completion(ColonyRuntimeCompletionPayload(status: "timed_out"))
            )
            finalize(.interrupted(reason: reason, interruptID: nil), cleanup: true)

        case .cancelled(_, _):
            await processCancellation(reason: .userRequestedStop)

        case .interrupted(let interruption):
            let interruptID = interruption.interrupt.id
            pendingInterrupt = interruptID

            // Currently tool approval is the only interrupt source, so .safetyBlock is always
            // correct. If Hive adds new interrupt types (budget limits, external signals, etc.),
            // derive the reason from interruption.interrupt.payload instead of hardcoding.
            let reason: ColonyInterruptionReason = .safetyBlock
            _ = await eventBus.emit(
                kind: .runInterrupted,
                runID: runID,
                sessionID: sessionID,
                agentID: agentID,
                correlationChain: [sessionID.rawValue, runID.uuidString.lowercased()],
                payload: .interruption(
                    ColonyRuntimeInterruptionPayload(
                        reason: reason,
                        classification: reason.classification,
                        interruptID: interruptID.rawValue
                    )
                )
            )
            finalize(.interrupted(reason: reason, interruptID: interruptID), cleanup: false)
        }
    }

    private func processCancellation(reason: ColonyInterruptionReason) async {
        guard beginTerminalTransition() else {
            return
        }

        _ = await eventBus.emit(
            kind: .runInterrupted,
            runID: runID,
            sessionID: sessionID,
            agentID: agentID,
            correlationChain: [sessionID.rawValue, runID.uuidString.lowercased()],
            payload: .interruption(
                ColonyRuntimeInterruptionPayload(
                    reason: reason,
                    classification: reason.classification,
                    interruptID: nil
                )
            )
        )
        _ = await eventBus.emit(
            kind: .runCompleted,
            runID: runID,
            sessionID: sessionID,
            agentID: agentID,
            correlationChain: [sessionID.rawValue, runID.uuidString.lowercased()],
            payload: .completion(ColonyRuntimeCompletionPayload(status: "cancelled"))
        )
        finalize(.cancelled(reason: reason), cleanup: true)
    }

    private func finishWithError(_ error: Error) async {
        guard beginTerminalTransition() else {
            return
        }

        let reason: ColonyInterruptionReason = .dependencyFailure
        _ = await eventBus.emit(
            kind: .runInterrupted,
            runID: runID,
            sessionID: sessionID,
            agentID: agentID,
            correlationChain: [sessionID.rawValue, runID.uuidString.lowercased()],
            payload: .interruption(
                ColonyRuntimeInterruptionPayload(
                    reason: reason,
                    classification: reason.classification,
                    interruptID: nil
                )
            )
        )
        _ = await eventBus.emit(
            kind: .runCompleted,
            runID: runID,
            sessionID: sessionID,
            agentID: agentID,
            correlationChain: [sessionID.rawValue, runID.uuidString.lowercased()],
            payload: .completion(
                ColonyRuntimeCompletionPayload(
                    status: "failed",
                    finalAnswer: nil
                )
            )
        )
        finalize(.failed(message: error.localizedDescription), cleanup: true)
    }

    private func finalize(_ result: ColonyGatewayRunResult, cleanup: Bool) {
        if hasTerminalResult {
            return
        }
        if Self.isTerminal(result) {
            terminalTransitionInFlight = false
        }

        finalResult = result
        let continuations = waiters
        waiters.removeAll(keepingCapacity: false)
        for continuation in continuations {
            continuation.resume(returning: result)
        }

        if cleanup {
            Task { await onTerminal(runID) }
        }
    }

    private static func isTerminal(_ result: ColonyGatewayRunResult) -> Bool {
        switch result {
        case .completed, .cancelled, .failed, .reused:
            return true
        case .interrupted:
            return false
        }
    }

    private var hasTerminalResult: Bool {
        guard let finalResult else {
            return false
        }
        return Self.isTerminal(finalResult)
    }

    private func beginTerminalTransition() -> Bool {
        guard hasTerminalResult == false, terminalTransitionInFlight == false else {
            return false
        }
        terminalTransitionInFlight = true
        return true
    }
}

private actor ColonyRuntimeCheckpointStoreBridge: HiveCheckpointStore {
    private let store: any ColonyRuntimeCheckpointStore

    init(store: any ColonyRuntimeCheckpointStore) {
        self.store = store
    }

    func save(_ checkpoint: HiveCheckpoint<ColonySchema>) async throws {
        try await store.save(checkpoint)
    }

    func loadLatest(threadID: HiveThreadID) async throws -> HiveCheckpoint<ColonySchema>? {
        try await store.loadLatest(threadID: threadID)
    }
}
