import Foundation
import HiveCore
import ColonyCore

public enum ColonyToolAsyncCapability: String, Codable, Sendable {
    case synchronous
    case asynchronous
}

public enum ColonyToolCategory: String, Codable, Sendable {
    case filesystem
    case shell
    case webSearch
    case messaging
    case cron
    case stateMemory
    case custom
}

public struct ColonyToolDefinition: Sendable, Codable, Equatable {
    public var name: String
    public var description: String
    public var inputJSONSchema: String
    public var outputJSONSchema: String?
    public var riskLevel: ColonyToolRiskLevel
    public var timeoutMilliseconds: Int?
    public var asyncCapability: ColonyToolAsyncCapability
    public var category: ColonyToolCategory
    public var metadata: [String: String]

    public init(
        name: String,
        description: String,
        inputJSONSchema: String,
        outputJSONSchema: String? = nil,
        riskLevel: ColonyToolRiskLevel = .readOnly,
        timeoutMilliseconds: Int? = nil,
        asyncCapability: ColonyToolAsyncCapability = .synchronous,
        category: ColonyToolCategory = .custom,
        metadata: [String: String] = [:]
    ) {
        self.name = name
        self.description = description
        self.inputJSONSchema = inputJSONSchema
        self.outputJSONSchema = outputJSONSchema
        self.riskLevel = riskLevel
        self.timeoutMilliseconds = timeoutMilliseconds
        self.asyncCapability = asyncCapability
        self.category = category
        self.metadata = metadata
    }

    public func toHiveDefinition() -> HiveToolDefinition {
        HiveToolDefinition(
            name: name,
            description: description,
            parametersJSONSchema: inputJSONSchema
        )
    }
}

public struct ColonyToolArtifact: Sendable, Codable, Equatable {
    public var name: String
    public var mimeType: String
    public var location: String
    public var sizeBytes: Int?

    public init(
        name: String,
        mimeType: String,
        location: String,
        sizeBytes: Int? = nil
    ) {
        self.name = name
        self.mimeType = mimeType
        self.location = location
        self.sizeBytes = sizeBytes
    }
}

public struct ColonyToolResultEnvelope: Sendable, Codable, Equatable {
    public var success: Bool
    public var payload: String
    public var errorCode: String?
    public var errorType: String?
    public var artifacts: [ColonyToolArtifact]
    public var attemptCount: Int
    public var durationMilliseconds: Int
    public var requestID: String

    public init(
        success: Bool,
        payload: String,
        errorCode: String? = nil,
        errorType: String? = nil,
        artifacts: [ColonyToolArtifact] = [],
        attemptCount: Int = 1,
        durationMilliseconds: Int = 0,
        requestID: String = UUID().uuidString.lowercased()
    ) {
        self.success = success
        self.payload = payload
        self.errorCode = errorCode
        self.errorType = errorType
        self.artifacts = artifacts
        self.attemptCount = max(1, attemptCount)
        self.durationMilliseconds = max(0, durationMilliseconds)
        self.requestID = requestID
    }
}

public struct ColonyToolExecutionContext: Sendable {
    public var runID: UUID
    public var sessionID: ColonyRuntimeSessionID
    public var agentID: String
    public var executionPolicy: ColonyExecutionPolicy
    public var correlationChain: [String]

    public init(
        runID: UUID,
        sessionID: ColonyRuntimeSessionID,
        agentID: String,
        executionPolicy: ColonyExecutionPolicy,
        correlationChain: [String] = []
    ) {
        self.runID = runID
        self.sessionID = sessionID
        self.agentID = agentID
        self.executionPolicy = executionPolicy
        self.correlationChain = correlationChain
    }
}

public typealias ColonyToolHandler = @Sendable (_ argumentsJSON: String, _ context: ColonyToolExecutionContext) async throws -> ColonyToolResultEnvelope

public enum ColonyRuntimeToolRegistryError: Error, Sendable, Equatable {
    case unknownTool(String)
}

public final class ColonyRuntimeToolRegistry: HiveToolRegistry, @unchecked Sendable {
    private let lock = NSLock()
    private var definitionsByName: [String: ColonyToolDefinition] = [:]
    private var handlersByName: [String: ColonyToolHandler] = [:]
    private var resultEnvelopesByToolCallID: [String: ColonyToolResultEnvelope] = [:]
    private var contextProvider: @Sendable () -> ColonyToolExecutionContext

    public init(
        contextProvider: @escaping @Sendable () -> ColonyToolExecutionContext = {
            ColonyToolExecutionContext(
                runID: UUID(),
                sessionID: ColonyRuntimeSessionID(rawValue: "session:unknown"),
                agentID: "agent:unknown",
                executionPolicy: ColonyExecutionPolicy()
            )
        }
    ) {
        self.contextProvider = contextProvider
    }

    public func updateContextProvider(_ provider: @escaping @Sendable () -> ColonyToolExecutionContext) {
        withLock {
            contextProvider = provider
        }
    }

    public func register(
        _ definition: ColonyToolDefinition,
        handler: @escaping ColonyToolHandler
    ) {
        withLock {
            definitionsByName[definition.name] = definition
            handlersByName[definition.name] = handler
        }
    }

    public func listTools() -> [HiveToolDefinition] {
        let definitions: [ColonyToolDefinition] = withLock {
            Array(definitionsByName.values)
        }

        return definitions
            .sorted { $0.name.utf8.lexicographicallyPrecedes($1.name.utf8) }
            .map { $0.toHiveDefinition() }
    }

    public func invoke(_ call: HiveToolCall) async throws -> HiveToolResult {
        let snapshot = withLock {
            (
                definitionAndHandler: definitionsByName[call.name].flatMap { definition in
                    handlersByName[call.name].map { handler in
                        (definition, handler)
                    }
                },
                contextProvider: self.contextProvider
            )
        }
        let definitionAndHandler = snapshot.definitionAndHandler
        let contextProvider = snapshot.contextProvider

        guard let (_, handler) = definitionAndHandler else {
            let envelope = ColonyToolResultEnvelope(
                success: false,
                payload: "Error: Unknown tool '\(call.name)'.",
                errorCode: "unknown_tool",
                errorType: String(reflecting: ColonyRuntimeToolRegistryError.unknownTool(call.name)),
                artifacts: [],
                attemptCount: 1,
                durationMilliseconds: 0,
                requestID: call.id
            )
            store(envelope: envelope, toolCallID: call.id)
            return HiveToolResult(toolCallID: call.id, content: envelope.payload)
        }

        let context = contextProvider()
        let clock = ContinuousClock()
        let start = clock.now

        do {
            var envelope = try await handler(call.argumentsJSON, context)
            let elapsed = start.duration(to: clock.now)
            let millis = max(0, Int(elapsed.components.seconds) * 1_000 + Int(elapsed.components.attoseconds / 1_000_000_000_000_000))

            envelope.durationMilliseconds = envelope.durationMilliseconds == 0 ? millis : envelope.durationMilliseconds
            if envelope.requestID.isEmpty {
                envelope.requestID = call.id
            }

            store(envelope: envelope, toolCallID: call.id)
            return HiveToolResult(toolCallID: call.id, content: envelope.payload)
        } catch {
            let elapsed = start.duration(to: clock.now)
            let millis = max(0, Int(elapsed.components.seconds) * 1_000 + Int(elapsed.components.attoseconds / 1_000_000_000_000_000))
            let envelope = ColonyToolResultEnvelope(
                success: false,
                payload: "Error: \(error.localizedDescription)",
                errorCode: "tool_error",
                errorType: String(reflecting: type(of: error)),
                artifacts: [],
                attemptCount: 1,
                durationMilliseconds: millis,
                requestID: call.id
            )
            store(envelope: envelope, toolCallID: call.id)
            return HiveToolResult(toolCallID: call.id, content: envelope.payload)
        }
    }

    public func resultEnvelope(forToolCallID toolCallID: String) -> ColonyToolResultEnvelope? {
        withLock {
            resultEnvelopesByToolCallID[toolCallID]
        }
    }

    public func registeredDefinitions() -> [ColonyToolDefinition] {
        withLock {
            definitionsByName.values
                .sorted { $0.name.utf8.lexicographicallyPrecedes($1.name.utf8) }
        }
    }

    public func clone(
        contextProvider: @escaping @Sendable () -> ColonyToolExecutionContext
    ) -> ColonyRuntimeToolRegistry {
        let cloned = ColonyRuntimeToolRegistry(contextProvider: contextProvider)

        let snapshot = withLock {
            (definitionsByName, handlersByName)
        }
        let definitions = snapshot.0
        let handlers = snapshot.1

        for definition in definitions.values {
            if let handler = handlers[definition.name] {
                cloned.register(definition, handler: handler)
            }
        }
        return cloned
    }

    private func store(envelope: ColonyToolResultEnvelope, toolCallID: String) {
        withLock {
            resultEnvelopesByToolCallID[toolCallID] = envelope
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

public enum ColonyStandardToolCatalog {
    public static let filesystem: [ColonyToolDefinition] = [
        ColonyToolDefinition(
            name: ColonyBuiltInToolDefinitions.readFile.name,
            description: "Read files from a policy-scoped workspace.",
            inputJSONSchema: ColonyBuiltInToolDefinitions.readFile.parametersJSONSchema,
            outputJSONSchema: #"{"type":"string"}"#,
            riskLevel: .readOnly,
            category: .filesystem
        ),
        ColonyToolDefinition(
            name: ColonyBuiltInToolDefinitions.writeFile.name,
            description: "Write files in a policy-scoped workspace.",
            inputJSONSchema: ColonyBuiltInToolDefinitions.writeFile.parametersJSONSchema,
            outputJSONSchema: #"{"type":"string"}"#,
            riskLevel: .mutation,
            category: .filesystem
        ),
    ]

    public static let shell: [ColonyToolDefinition] = [
        ColonyToolDefinition(
            name: ColonyBuiltInToolDefinitions.execute.name,
            description: "Execute shell commands through policy-aware validators.",
            inputJSONSchema: ColonyBuiltInToolDefinitions.execute.parametersJSONSchema,
            outputJSONSchema: #"{"type":"string"}"#,
            riskLevel: .execution,
            category: .shell
        ),
    ]

    public static let webSearch: [ColonyToolDefinition] = [
        ColonyToolDefinition(
            name: ColonyBuiltInToolDefinitions.webSearch.name,
            description: "Search web sources through configured backend.",
            inputJSONSchema: ColonyBuiltInToolDefinitions.webSearch.parametersJSONSchema,
            outputJSONSchema: #"{"type":"string"}"#,
            riskLevel: .network,
            category: .webSearch
        ),
    ]

    public static let messaging: [ColonyToolDefinition] = [
        ColonyToolDefinition(
            name: "send_message",
            description: "Send a message to a named channel target.",
            inputJSONSchema: #"{"type":"object","properties":{"target":{"type":"string"},"content":{"type":"string"}},"required":["target","content"]}"#,
            outputJSONSchema: #"{"type":"object","properties":{"status":{"type":"string"}},"required":["status"]}"#,
            riskLevel: .network,
            category: .messaging
        ),
    ]

    public static let cron: [ColonyToolDefinition] = [
        ColonyToolDefinition(
            name: "cron_control",
            description: "Create, pause, or remove a scheduled trigger.",
            inputJSONSchema: #"{"type":"object","properties":{"operation":{"type":"string","enum":["create","pause","resume","delete"]},"id":{"type":"string"},"schedule":{"type":"string"},"payload":{"type":"string"}},"required":["operation","id"]}"#,
            outputJSONSchema: #"{"type":"object","properties":{"status":{"type":"string"}},"required":["status"]}"#,
            riskLevel: .stateMutation,
            category: .cron
        ),
    ]

    public static let stateMemory: [ColonyToolDefinition] = [
        ColonyToolDefinition(
            name: ColonyBuiltInToolDefinitions.memoryRecall.name,
            description: "Recall persisted state/memory entries.",
            inputJSONSchema: ColonyBuiltInToolDefinitions.memoryRecall.parametersJSONSchema,
            outputJSONSchema: #"{"type":"string"}"#,
            riskLevel: .readOnly,
            category: .stateMemory
        ),
        ColonyToolDefinition(
            name: ColonyBuiltInToolDefinitions.memoryRemember.name,
            description: "Store state/memory entries.",
            inputJSONSchema: ColonyBuiltInToolDefinitions.memoryRemember.parametersJSONSchema,
            outputJSONSchema: #"{"type":"string"}"#,
            riskLevel: .stateMutation,
            category: .stateMemory
        ),
    ]
}
