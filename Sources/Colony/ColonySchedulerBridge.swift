import Foundation

public struct ColonyScheduledRunTrigger: Sendable, Codable, Equatable {
    public var id: String
    public var sessionID: ColonyRuntimeSessionID
    public var input: String
    public var earliestFireAt: Date
    public var idempotencyKey: String?
    public var metadata: [String: String]

    public init(
        id: String = "trigger:" + UUID().uuidString.lowercased(),
        sessionID: ColonyRuntimeSessionID,
        input: String,
        earliestFireAt: Date,
        idempotencyKey: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.sessionID = sessionID
        self.input = input
        self.earliestFireAt = earliestFireAt
        self.idempotencyKey = idempotencyKey
        self.metadata = metadata
    }
}

public protocol ColonySchedulerQueue: Sendable {
    func enqueue(_ trigger: ColonyScheduledRunTrigger) async
    func dueTriggers(now: Date) async -> [ColonyScheduledRunTrigger]
}

public actor ColonyInMemorySchedulerQueue: ColonySchedulerQueue {
    private var triggers: [ColonyScheduledRunTrigger] = []

    public init() {}

    public func enqueue(_ trigger: ColonyScheduledRunTrigger) async {
        triggers.append(trigger)
        triggers.sort { lhs, rhs in
            if lhs.earliestFireAt == rhs.earliestFireAt {
                return lhs.id < rhs.id
            }
            return lhs.earliestFireAt < rhs.earliestFireAt
        }
    }

    public func dueTriggers(now: Date) async -> [ColonyScheduledRunTrigger] {
        let due = triggers.filter { $0.earliestFireAt <= now }
        let dueIDs = Set(due.map(\.id))
        triggers.removeAll { dueIDs.contains($0.id) }
        return due
    }
}

public actor ColonySchedulerBridge {
    private let runtime: ColonyGatewayRuntime
    private let queue: any ColonySchedulerQueue
    private let logger: any HiveLogger

    public init(
        runtime: ColonyGatewayRuntime,
        queue: any ColonySchedulerQueue = ColonyInMemorySchedulerQueue(),
        logger: any HiveLogger = ColonyNoopLogger()
    ) {
        self.runtime = runtime
        self.queue = queue
        self.logger = logger
    }

    public func enqueue(_ trigger: ColonyScheduledRunTrigger) async {
        await queue.enqueue(trigger)
    }

    @discardableResult
    public func tick(now: Date = Date()) async -> [UUID] {
        let due = await queue.dueTriggers(now: now)
        var runIDs: [UUID] = []
        runIDs.reserveCapacity(due.count)

        for trigger in due {
            let request = ColonyGatewayRunRequest(
                sessionID: trigger.sessionID,
                input: trigger.input,
                providerOverride: nil,
                executionPolicyOverride: nil,
                idempotencyKey: trigger.idempotencyKey,
                metadata: trigger.metadata
            )
            do {
                let handle = try await runtime.startRun(request)
                runIDs.append(handle.runID)
            } catch {
                logger.error(
                    "Scheduled trigger \(trigger.id) failed to start: \(error)",
                    metadata: [
                        "triggerID": trigger.id,
                        "sessionID": trigger.sessionID.rawValue,
                    ]
                )
                // Re-enqueue so the trigger is not permanently lost.
                await queue.enqueue(trigger)
            }
        }
        return runIDs
    }
}
