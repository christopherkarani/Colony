import Foundation
@testable import Colony

protocol SwarmGraphSchema {}

extension ColonySchema: SwarmGraphSchema {}

typealias SwarmGraphRunOptions = ColonyRun.Options
typealias SwarmCheckpointID = ColonyCheckpointID
typealias SwarmCheckpoint<Schema> = ColonyCheckpointSnapshot

protocol SwarmCheckpointStore: Sendable {
    associatedtype Schema: SwarmGraphSchema

    func save(_ checkpoint: SwarmCheckpoint<Schema>) async throws
    func loadLatest(threadID: SwarmThreadID) async throws -> SwarmCheckpoint<Schema>?
}

struct SwarmAnyCheckpointStore<Schema: SwarmGraphSchema>: Sendable {
    private let saveHandler: @Sendable (SwarmCheckpoint<Schema>) async throws -> Void
    private let loadLatestHandler: @Sendable (SwarmThreadID) async throws -> SwarmCheckpoint<Schema>?

    init<Store: SwarmCheckpointStore>(_ store: Store) where Store.Schema == Schema {
        saveHandler = { checkpoint in
            try await store.save(checkpoint)
        }
        loadLatestHandler = { threadID in
            try await store.loadLatest(threadID: threadID)
        }
    }

    func save(_ checkpoint: SwarmCheckpoint<Schema>) async throws {
        try await saveHandler(checkpoint)
    }

    func loadLatest(threadID: SwarmThreadID) async throws -> SwarmCheckpoint<Schema>? {
        try await loadLatestHandler(threadID)
    }
}

struct SwarmCompiledGraph<Schema: SwarmGraphSchema>: Sendable {
    fileprivate init() {}
}

extension ColonyAgent {
    static func compile() throws -> SwarmCompiledGraph<ColonySchema> {
        SwarmCompiledGraph()
    }
}

struct SwarmGraphEnvironment<Schema: SwarmGraphSchema>: Sendable {
    let context: ColonyContext
    let clock: any SwarmClock
    let logger: any SwarmLogger
    let model: SwarmAnyModelClient?
    let modelRouter: (any SwarmModelRouter)?
    let inferenceHints: SwarmInferenceHints?
    let tools: SwarmAnyToolRegistry?
    let checkpointStore: SwarmAnyCheckpointStore<Schema>?

    init(
        context: ColonyContext,
        clock: any SwarmClock,
        logger: any SwarmLogger,
        model: SwarmAnyModelClient? = nil,
        modelRouter: (any SwarmModelRouter)? = nil,
        inferenceHints: SwarmInferenceHints? = nil,
        tools: SwarmAnyToolRegistry? = nil,
        checkpointStore: SwarmAnyCheckpointStore<Schema>? = nil
    ) {
        self.context = context
        self.clock = clock
        self.logger = logger
        self.model = model
        self.modelRouter = modelRouter
        self.inferenceHints = inferenceHints
        self.tools = tools
        self.checkpointStore = checkpointStore
    }
}

struct SwarmGraphRuntime<Schema: SwarmGraphSchema>: Sendable {
    private let coordinator: LegacyRuntimeCoordinator<Schema>

    init(graph: SwarmCompiledGraph<Schema>, environment: SwarmGraphEnvironment<Schema>) throws {
        _ = graph
        coordinator = LegacyRuntimeCoordinator(environment: environment)
    }

    func run(
        threadID: SwarmThreadID,
        input: String,
        options: SwarmGraphRunOptions = .init()
    ) async -> ColonyRun.Handle {
        await coordinator.run(threadID: threadID, input: input, options: options)
    }

    func resume(
        threadID: SwarmThreadID,
        interruptID: SwarmInterruptID,
        payload: ColonyResumePayload,
        options: SwarmGraphRunOptions = .init()
    ) async -> ColonyRun.Handle {
        await coordinator.resume(
            threadID: threadID,
            interruptID: interruptID,
            payload: payload,
            options: options
        )
    }
}

private actor LegacyRuntimeCoordinator<Schema: SwarmGraphSchema> {
    private let environment: SwarmGraphEnvironment<Schema>
    private let checkpointStore: any ColonyCheckpointStore
    private var controls: [String: ColonyRunControl] = [:]

    init(environment: SwarmGraphEnvironment<Schema>) {
        self.environment = environment
        if let checkpointStore = environment.checkpointStore {
            self.checkpointStore = LegacyCheckpointStoreAdapter(store: checkpointStore)
        } else {
            self.checkpointStore = ColonyInMemoryCheckpointStore()
        }
    }

    func run(
        threadID: SwarmThreadID,
        input: String,
        options: SwarmGraphRunOptions
    ) async -> ColonyRun.Handle {
        let control = makeControl(threadID: threadID)
        return await control.start(
            ColonyRunStartRequest(
                input: input,
                optionsOverride: options
            )
        )
    }

    func resume(
        threadID: SwarmThreadID,
        interruptID: SwarmInterruptID,
        payload: ColonyResumePayload,
        options: SwarmGraphRunOptions
    ) async -> ColonyRun.Handle {
        let control = makeControl(threadID: threadID)
        let decision: ColonyToolApprovalDecision
        switch payload {
        case .toolApproval(let toolDecision):
            decision = toolDecision
        }

        return await control.resume(
            ColonyRunResumeRequest(
                interruptID: ColonyInterruptID(interruptID.rawValue),
                decision: decision,
                optionsOverride: options
            )
        )
    }

    private func makeControl(threadID: SwarmThreadID) -> ColonyRunControl {
        if let existing = controls[threadID.rawValue] {
            return existing
        }

        let executionEnvironment = SwarmExecutionEnvironment(
            clock: environment.clock,
            logger: environment.logger,
            model: environment.model,
            modelRouter: environment.modelRouter,
            inferenceHints: environment.inferenceHints,
            tools: environment.tools
        )
        let colonyThreadID = ColonyThreadID(threadID.rawValue)
        let engine = ColonyRuntimeEngine(
            threadID: colonyThreadID,
            context: environment.context,
            environment: executionEnvironment,
            checkpointStore: checkpointStore
        )
        let control = ColonyRunControl(
            threadID: colonyThreadID,
            engine: engine,
            options: .init()
        )
        controls[threadID.rawValue] = control
        return control
    }
}

private actor LegacyCheckpointStoreAdapter<Schema: SwarmGraphSchema>: ColonyCheckpointStore {
    private let store: SwarmAnyCheckpointStore<Schema>
    private var mirroredCheckpoints: [ColonyCheckpointSnapshot] = []

    init(store: SwarmAnyCheckpointStore<Schema>) {
        self.store = store
    }

    func save(_ checkpoint: ColonyCheckpointSnapshot) async throws {
        mirroredCheckpoints.append(checkpoint)
        try await store.save(checkpoint)
    }

    func loadLatest(threadID: ColonyThreadID) async throws -> ColonyCheckpointSnapshot? {
        let local = mirroredCheckpoints
            .filter { $0.threadID == threadID }
            .max {
                if $0.stepIndex == $1.stepIndex {
                    return $0.createdAt < $1.createdAt
                }
                return $0.stepIndex < $1.stepIndex
            }
        if let local {
            return local
        }

        return try await store.loadLatest(threadID: SwarmThreadID(threadID.rawValue))
    }

    func loadCheckpoint(threadID: ColonyThreadID, id: ColonyCheckpointID) async throws -> ColonyCheckpointSnapshot? {
        mirroredCheckpoints.last { $0.threadID == threadID && $0.id == id }
    }

    func loadByInterruptID(threadID: ColonyThreadID, interruptID: ColonyInterruptID) async throws -> ColonyCheckpointSnapshot? {
        mirroredCheckpoints.last { $0.threadID == threadID && $0.interruptID == interruptID }
    }
}

extension ColonyCheckpointSnapshot {
    init(
        id: SwarmCheckpointID,
        threadID: SwarmThreadID,
        runID: SwarmRunID,
        stepIndex: Int,
        schemaVersion: String,
        graphVersion: String,
        globalDataByChannelID: [String: String],
        frontier: [String],
        joinBarrierSeenByJoinID: [String: Bool],
        interruption: String?
    ) {
        _ = schemaVersion
        _ = graphVersion
        _ = globalDataByChannelID
        _ = frontier
        _ = joinBarrierSeenByJoinID
        _ = interruption
        self.init(
            id: id,
            threadID: ColonyThreadID(threadID.rawValue),
            runID: ColonyRunID(rawValue: runID.rawValue.uuidString),
            attemptID: .generate(),
            stepIndex: stepIndex,
            store: ColonyStoreSnapshot()
        )
    }
}

struct LegacyInterruptEnvelope<Payload: Sendable>: Sendable {
    let id: SwarmInterruptID
    let payload: Payload
}

extension ColonyRun.Interruption {
    var interrupt: LegacyInterruptEnvelope<ColonyInterruptPayload> {
        LegacyInterruptEnvelope(
            id: SwarmInterruptID(interruptID.rawValue),
            payload: payload
        )
    }
}

func == (lhs: ColonyThreadID, rhs: SwarmThreadID) -> Bool {
    lhs.rawValue == rhs.rawValue
}

func == (lhs: SwarmThreadID, rhs: ColonyThreadID) -> Bool {
    lhs.rawValue == rhs.rawValue
}

func == (lhs: ColonyInterruptID, rhs: SwarmInterruptID) -> Bool {
    lhs.rawValue == rhs.rawValue
}

func == (lhs: SwarmInterruptID, rhs: ColonyInterruptID) -> Bool {
    lhs.rawValue == rhs.rawValue
}

extension ColonyRunID {
    var hiveRunID: SwarmRunID {
        SwarmRunID(UUID(uuidString: rawValue) ?? UUID())
    }
}

extension ColonyInterruptID {
    var hiveInterruptID: SwarmInterruptID {
        SwarmInterruptID(rawValue)
    }
}

extension ColonyInferenceRequest {
    var hiveChatRequest: SwarmChatRequest {
        SwarmChatRequest(
            model: modelName ?? "",
            messages: messages,
            tools: tools
        )
    }
}

extension ColonyInferenceResponse {
    init(_ response: SwarmChatResponse) {
        self.init(message: response.message)
    }
}
