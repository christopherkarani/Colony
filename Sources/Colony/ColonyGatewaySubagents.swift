import Foundation
import HiveCore

public enum ColonyInterruptionReason: String, Codable, Sendable, Equatable {
    case userRequestedStop = "user_requested_stop"
    case timeout
    case safetyBlock = "safety_block"
    case dependencyFailure = "dependency_failure"
    case toolFailure = "tool_failure"
    case childRunCrash = "child_run_crash"
}

public enum ColonyFailureClassification: String, Codable, Sendable, Equatable {
    case hardFail = "hard_fail"
    case softRetry = "soft_retry"
}

public extension ColonyInterruptionReason {
    var classification: ColonyFailureClassification {
        switch self {
        case .userRequestedStop:
            return .hardFail
        case .timeout:
            return .softRetry
        case .safetyBlock:
            return .softRetry
        case .dependencyFailure:
            return .hardFail
        case .toolFailure:
            return .softRetry
        case .childRunCrash:
            return .hardFail
        }
    }
}

public enum ColonySubagentLifecycleState: String, Codable, Sendable, Equatable {
    case started
    case completed
    case failed
    case interrupted
}

public enum ColonyMessageRouteTarget: String, Codable, Sendable, Equatable {
    case parentContext = "parent_context"
    case userChannelOutput = "user_channel_output"
    case backgroundLog = "background_log"
}

public struct ColonyRoutedMessage: Codable, Sendable, Equatable {
    public var target: ColonyMessageRouteTarget
    public var content: String
    public var runID: UUID
    public var sessionID: ColonyRuntimeSessionID
    public var agentID: String
    public var subagentID: String?
    public var timestamp: Date

    public init(
        target: ColonyMessageRouteTarget,
        content: String,
        runID: UUID,
        sessionID: ColonyRuntimeSessionID,
        agentID: String,
        subagentID: String? = nil,
        timestamp: Date = Date()
    ) {
        self.target = target
        self.content = content
        self.runID = runID
        self.sessionID = sessionID
        self.agentID = agentID
        self.subagentID = subagentID
        self.timestamp = timestamp
    }
}

public protocol ColonyMessageSink: Sendable {
    func publish(_ message: ColonyRoutedMessage) async
}

public actor ColonyInMemoryMessageSink: ColonyMessageSink {
    private var storage: [ColonyRoutedMessage] = []

    public init() {}

    public func publish(_ message: ColonyRoutedMessage) async {
        storage.append(message)
    }

    public func messages() -> [ColonyRoutedMessage] {
        storage
    }
}

public struct ColonySpawnRequest: Sendable {
    public var parentRunID: UUID
    public var parentSessionID: ColonyRuntimeSessionID
    public var prompt: String
    public var subagentID: String?
    public var providerOverride: ColonyProviderSelection?
    public var executionPolicyOverride: ColonyExecutionPolicy?
    public var isolateContext: Bool

    public init(
        parentRunID: UUID,
        parentSessionID: ColonyRuntimeSessionID,
        prompt: String,
        subagentID: String? = nil,
        providerOverride: ColonyProviderSelection? = nil,
        executionPolicyOverride: ColonyExecutionPolicy? = nil,
        isolateContext: Bool = true
    ) {
        self.parentRunID = parentRunID
        self.parentSessionID = parentSessionID
        self.prompt = prompt
        self.subagentID = subagentID
        self.providerOverride = providerOverride
        self.executionPolicyOverride = executionPolicyOverride
        self.isolateContext = isolateContext
    }
}

public struct ColonySpawnResult: Sendable {
    public var subagentID: String
    public var childRunID: UUID
    public var childSessionID: ColonyRuntimeSessionID
    public var handle: ColonySubagentHandle

    public init(
        subagentID: String,
        childRunID: UUID,
        childSessionID: ColonyRuntimeSessionID,
        handle: ColonySubagentHandle
    ) {
        self.subagentID = subagentID
        self.childRunID = childRunID
        self.childSessionID = childSessionID
        self.handle = handle
    }
}

public actor ColonySubagentHandle {
    public let subagentID: String
    public let runID: UUID
    public let sessionID: ColonyRuntimeSessionID

    private var stateStorage: ColonySubagentLifecycleState = .started
    private let awaitResultImpl: @Sendable () async -> ColonyGatewayRunResult
    private let cancelImpl: @Sendable () async -> Bool

    public init(
        subagentID: String,
        runID: UUID,
        sessionID: ColonyRuntimeSessionID,
        awaitResult: @escaping @Sendable () async -> ColonyGatewayRunResult,
        cancel: @escaping @Sendable () async -> Bool
    ) {
        self.subagentID = subagentID
        self.runID = runID
        self.sessionID = sessionID
        self.awaitResultImpl = awaitResult
        self.cancelImpl = cancel
    }

    public var state: ColonySubagentLifecycleState {
        stateStorage
    }

    public func awaitOutcome() async -> ColonyGatewayRunResult {
        await awaitResultImpl()
    }

    public func cancel() async -> Bool {
        await cancelImpl()
    }

    func setState(_ state: ColonySubagentLifecycleState) {
        stateStorage = state
    }
}
