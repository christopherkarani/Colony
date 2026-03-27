import Foundation
import ColonyCore

package struct SwarmNodeID: Sendable, Hashable, Equatable {
    package let rawValue: String

    package init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

package struct SwarmTaskID: Sendable, Hashable, Equatable {
    package let rawValue: String

    package init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

package struct SwarmRunID: Sendable, Hashable, Equatable {
    package let rawValue: UUID

    package init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

package struct SwarmThreadID: Sendable, Hashable, Equatable, Codable {
    package let rawValue: String

    package init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

package struct SwarmInterruptID: Sendable, Hashable, Equatable, Codable {
    package let rawValue: String

    package init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

package struct SwarmRunResume<Payload: Sendable>: Sendable {
    package let interruptID: SwarmInterruptID
    package let payload: Payload

    package init(interruptID: SwarmInterruptID, payload: Payload) {
        self.interruptID = interruptID
        self.payload = payload
    }
}

package struct SwarmInputContext: Sendable {
    package let runID: SwarmRunID
    package let stepIndex: Int
}

package struct SwarmAnyWrite<Schema>: Sendable {
    package let channelID: ColonyChannelID
    private let valueProvider: @Sendable () -> any Sendable

    package init<Value: Sendable>(_ key: ColonySchema.ChannelKey<Value>, _ value: Value) {
        channelID = key.id
        valueProvider = { value }
    }

    package func value() -> any Sendable {
        valueProvider()
    }
}

package struct SwarmTaskLocalStore<Schema>: Sendable {
    package static var empty: SwarmTaskLocalStore<Schema> {
        SwarmTaskLocalStore(storage: [:])
    }

    private var storage: [ColonyChannelID: any Sendable]

    package init(storage: [ColonyChannelID: any Sendable]) {
        self.storage = storage
    }

    package mutating func set<Value: Sendable>(_ key: ColonySchema.ChannelKey<Value>, _ value: Value) throws {
        storage[key.id] = value
    }

    package func get<Value: Sendable>(_ key: ColonySchema.ChannelKey<Value>) throws -> Value {
        guard let value = storage[key.id] else {
            throw ColonyStoreError.missingChannel(key.id)
        }
        guard let typed = value as? Value else {
            throw ColonyStoreError.typeMismatch(channelID: key.id)
        }
        return typed
    }
}

package struct SwarmStoreView<Schema>: Sendable {
    private let snapshot: ColonyStoreSnapshot
    private let local: SwarmTaskLocalStore<Schema>?

    package init(snapshot: ColonyStoreSnapshot, local: SwarmTaskLocalStore<Schema>? = nil) {
        self.snapshot = snapshot
        self.local = local
    }

    package func get<Value: Sendable>(_ key: ColonySchema.ChannelKey<Value>) throws -> Value {
        if key.id == ColonySchema.Channels.currentToolCall.id,
           let local
        {
            return try local.get(key)
        }

        return try ColonyRun.Store(snapshot).get(key)
    }
}

package struct SwarmTaskSeed<Schema>: Sendable {
    package let nodeID: SwarmNodeID
    package let local: SwarmTaskLocalStore<Schema>

    package init(nodeID: SwarmNodeID, local: SwarmTaskLocalStore<Schema>) {
        self.nodeID = nodeID
        self.local = local
    }
}

package enum SwarmGraphNext: Sendable, Equatable {
    case end
    case to([SwarmNodeID])
}

package struct SwarmInterruptRequest<Payload: Sendable>: Sendable {
    package let payload: Payload

    package init(payload: Payload) {
        self.payload = payload
    }
}

package struct SwarmExecutionEnvironment: Sendable {
    package let clock: any SwarmClock
    package let logger: any SwarmLogger
    package let model: SwarmAnyModelClient?
    package let modelRouter: (any SwarmModelRouter)?
    package let inferenceHints: SwarmInferenceHints?
    package let tools: SwarmAnyToolRegistry?

    package init(
        clock: any SwarmClock,
        logger: any SwarmLogger,
        model: SwarmAnyModelClient?,
        modelRouter: (any SwarmModelRouter)?,
        inferenceHints: SwarmInferenceHints?,
        tools: SwarmAnyToolRegistry?
    ) {
        self.clock = clock
        self.logger = logger
        self.model = model
        self.modelRouter = modelRouter
        self.inferenceHints = inferenceHints
        self.tools = tools
    }
}

package struct SwarmExecutionRun<ResumePayload: Sendable>: Sendable {
    package let runID: SwarmRunID
    package let attemptID: ColonyRunAttemptID
    package let threadID: SwarmThreadID
    package let taskID: SwarmTaskID
    package let stepIndex: Int
    package let resume: SwarmRunResume<ResumePayload>?
}

package struct SwarmGraphInput<Schema>: Sendable {
    package let store: SwarmStoreView<Schema>
    package let context: ColonyContext
    package let run: SwarmExecutionRun<ColonyResumePayload>
    package let environment: SwarmExecutionEnvironment
    private let streamEmitter: @Sendable (ColonyRun.EventKind, [String: String]) -> Void

    package init(
        store: SwarmStoreView<Schema>,
        context: ColonyContext,
        run: SwarmExecutionRun<ColonyResumePayload>,
        environment: SwarmExecutionEnvironment,
        streamEmitter: @escaping @Sendable (ColonyRun.EventKind, [String: String]) -> Void
    ) {
        self.store = store
        self.context = context
        self.run = run
        self.environment = environment
        self.streamEmitter = streamEmitter
    }

    package func emitStream(_ kind: ColonyRun.EventKind, _ metadata: [String: String] = [:]) {
        streamEmitter(kind, metadata)
    }
}

package struct SwarmGraphOutput<Schema>: Sendable {
    package let writes: [SwarmAnyWrite<Schema>]
    package let next: SwarmGraphNext
    package let interrupt: SwarmInterruptRequest<ColonyInterruptPayload>?
    package let spawn: [SwarmTaskSeed<Schema>]

    package init(
        writes: [SwarmAnyWrite<Schema>] = [],
        next: SwarmGraphNext = .end,
        interrupt: SwarmInterruptRequest<ColonyInterruptPayload>? = nil,
        spawn: [SwarmTaskSeed<Schema>] = []
    ) {
        self.writes = writes
        self.next = next
        self.interrupt = interrupt
        self.spawn = spawn
    }
}
