import Foundation
import HiveCore
import ColonyCore

extension ColonyID where Domain == ColonyIDDomain.Thread {
    package init(_ hive: HiveThreadID) {
        self.init(hive.rawValue)
    }

    package var hive: HiveThreadID {
        HiveThreadID(rawValue)
    }
}

extension ColonyID where Domain == ColonyIDDomain.Interrupt {
    package init(_ hive: HiveInterruptID) {
        self.init(hive.rawValue)
    }

    package var hive: HiveInterruptID {
        HiveInterruptID(rawValue)
    }
}

extension ColonyChatRole {
    package init(_ hive: HiveChatRole) {
        switch hive {
        case .system:
            self = .system
        case .user:
            self = .user
        case .assistant:
            self = .assistant
        case .tool:
            self = .tool
        }
    }

    package var hive: HiveChatRole {
        switch self {
        case .system:
            return .system
        case .user:
            return .user
        case .assistant:
            return .assistant
        case .tool:
            return .tool
        }
    }
}

extension ColonyChatMessageOperation {
    package init(_ hive: HiveChatMessageOp) {
        switch hive {
        case .remove:
            self = .remove
        case .removeAll:
            self = .removeAll
        }
    }

    package var hive: HiveChatMessageOp {
        switch self {
        case .remove:
            return .remove
        case .removeAll:
            return .removeAll
        }
    }
}

extension ColonyTool.Definition {
    package init(_ hive: HiveToolDefinition) {
        self.init(
            name: ColonyTool.Name(rawValue: hive.name),
            description: hive.description,
            parametersJSONSchema: hive.parametersJSONSchema
        )
    }

    package var hive: HiveToolDefinition {
        HiveToolDefinition(
            name: name.rawValue,
            description: description,
            parametersJSONSchema: parametersJSONSchema
        )
    }
}

extension ColonyTool.Call {
    package init(_ hive: HiveToolCall) {
        self.init(
            id: ColonyToolCallID(hive.id),
            name: ColonyTool.Name(rawValue: hive.name),
            argumentsJSON: hive.argumentsJSON
        )
    }

    package var hive: HiveToolCall {
        HiveToolCall(
            id: id.rawValue,
            name: name.rawValue,
            argumentsJSON: argumentsJSON
        )
    }
}

extension ColonyTool.Result {
    package init(_ hive: HiveToolResult) {
        self.init(
            toolCallID: ColonyToolCallID(hive.toolCallID),
            content: hive.content
        )
    }

    package var hive: HiveToolResult {
        HiveToolResult(toolCallID: toolCallID.rawValue, content: content)
    }
}

extension ColonyStructuredOutput {
    package init(_ hive: HiveStructuredOutputFormat) {
        switch hive {
        case .jsonObject:
            self = .jsonObject
        case let .jsonSchema(name, schemaJSON):
            self = .jsonSchema(name: name, schemaJSON: schemaJSON)
        }
    }

    package var hive: HiveStructuredOutputFormat {
        switch self {
        case .jsonObject:
            return .jsonObject
        case let .jsonSchema(name, schemaJSON):
            return .jsonSchema(name: name, schemaJSON: schemaJSON)
        }
    }
}

extension ColonyStructuredOutputPayload {
    package init(_ hive: HiveStructuredOutput) {
        self.init(format: ColonyStructuredOutput(hive.format), json: hive.json)
    }

    package var hive: HiveStructuredOutput {
        HiveStructuredOutput(format: format.hive, json: json)
    }
}

extension ColonyChatMessage {
    package init(_ hive: HiveChatMessage) {
        self.init(
            id: ColonyMessageID(hive.id),
            role: ColonyChatRole(hive.role),
            content: hive.content,
            name: hive.name.map { ColonyTool.Name(rawValue: $0) },
            toolCallID: hive.toolCallID.map { ColonyToolCallID($0) },
            toolCalls: hive.toolCalls.map(ColonyTool.Call.init),
            structuredOutput: hive.structuredOutput.map(ColonyStructuredOutputPayload.init),
            operation: hive.op.map(ColonyChatMessageOperation.init)
        )
    }

    package var hive: HiveChatMessage {
        HiveChatMessage(
            id: id.rawValue,
            role: role.hive,
            content: content,
            name: name?.rawValue,
            toolCallID: toolCallID?.rawValue,
            toolCalls: toolCalls.map(\.hive),
            structuredOutput: structuredOutput?.hive,
            op: operation?.hive
        )
    }
}

extension ColonyModelRequest {
    package init(_ hive: HiveChatRequest) {
        self.init(
            model: ColonyModelName(rawValue: hive.model),
            messages: hive.messages.map(ColonyChatMessage.init),
            tools: hive.tools.map(ColonyTool.Definition.init),
            structuredOutput: hive.structuredOutput.map(ColonyStructuredOutput.init)
        )
    }

    package var hive: HiveChatRequest {
        HiveChatRequest(
            model: model.rawValue,
            messages: messages.map(\.hive),
            tools: tools.map(\.hive),
            structuredOutput: structuredOutput?.hive
        )
    }
}

extension ColonyModelResponse {
    package init(_ hive: HiveChatResponse) {
        self.init(message: ColonyChatMessage(hive.message))
    }

    package var hive: HiveChatResponse {
        HiveChatResponse(message: message.hive)
    }
}

extension ColonyModelStreamChunk {
    package init(_ hive: HiveChatStreamChunk) {
        switch hive {
        case .token(let text):
            self = .token(text)
        case .final(let response):
            self = .final(ColonyModelResponse(response))
        }
    }

    package var hive: HiveChatStreamChunk {
        switch self {
        case .token(let text):
            return .token(text)
        case .final(let response):
            return .final(response.hive)
        }
    }
}

extension ColonyLatencyTier {
    package init(_ hive: HiveLatencyTier) {
        switch hive {
        case .interactive:
            self = .interactive
        case .background:
            self = .background
        }
    }

    package var hive: HiveLatencyTier {
        switch self {
        case .interactive:
            return .interactive
        case .background:
            return .background
        }
    }
}

extension ColonyNetworkState {
    package init(_ hive: HiveNetworkState) {
        switch hive {
        case .offline:
            self = .offline
        case .online:
            self = .online
        case .metered:
            self = .metered
        }
    }

    package var hive: HiveNetworkState {
        switch self {
        case .offline:
            return .offline
        case .online:
            return .online
        case .metered:
            return .metered
        }
    }
}

extension ColonyInferenceHints {
    package init(_ hive: HiveInferenceHints) {
        self.init(
            latencyTier: ColonyLatencyTier(hive.latencyTier),
            privacyRequired: hive.privacyRequired,
            tokenBudget: hive.tokenBudget.map { ColonyTokenCount($0) },
            networkState: ColonyNetworkState(hive.networkState)
        )
    }

    package var hive: HiveInferenceHints {
        HiveInferenceHints(
            latencyTier: latencyTier.hive,
            privacyRequired: privacyRequired,
            tokenBudget: tokenBudget?.rawValue,
            networkState: networkState.hive
        )
    }
}

extension ColonyRun.CheckpointPolicy {
    package init(_ hive: HiveCheckpointPolicy) {
        switch hive {
        case .disabled:
            self = .disabled
        case .everyStep:
            self = .everyStep
        case .every(let steps):
            self = .every(steps: steps)
        case .onInterrupt:
            self = .onInterrupt
        }
    }

    package var hive: HiveCheckpointPolicy {
        switch self {
        case .disabled:
            return .disabled
        case .everyStep:
            return .everyStep
        case .every(let steps):
            return .every(steps: steps)
        case .onInterrupt:
            return .onInterrupt
        }
    }
}

extension ColonyRun.StreamingMode {
    package init(_ hive: HiveStreamingMode) {
        switch hive {
        case .events:
            self = .events
        case .values:
            self = .values
        case .updates:
            self = .updates
        case .combined:
            self = .combined
        }
    }

    package var hive: HiveStreamingMode {
        switch self {
        case .events:
            return .events
        case .values:
            return .values
        case .updates:
            return .updates
        case .combined:
            return .combined
        }
    }
}

extension ColonyRun.Options {
    package init(_ hive: HiveRunOptions) {
        self.init(
            maxSteps: hive.maxSteps,
            maxConcurrentTasks: hive.maxConcurrentTasks,
            checkpointPolicy: ColonyRun.CheckpointPolicy(hive.checkpointPolicy),
            debugPayloads: hive.debugPayloads,
            deterministicTokenStreaming: hive.deterministicTokenStreaming,
            eventBufferCapacity: hive.eventBufferCapacity,
            streamingMode: ColonyRun.StreamingMode(hive.streamingMode)
        )
    }

    package var hive: HiveRunOptions {
        HiveRunOptions(
            maxSteps: maxSteps,
            maxConcurrentTasks: maxConcurrentTasks,
            checkpointPolicy: checkpointPolicy.hive,
            debugPayloads: debugPayloads,
            deterministicTokenStreaming: deterministicTokenStreaming,
            eventBufferCapacity: eventBufferCapacity,
            streamingMode: streamingMode.hive
        )
    }
}

package struct ColonyHiveModelClientAdapter: HiveModelClient, Sendable {
    let base: any ColonyModelClient

    package func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        try await base.complete(ColonyModelRequest(request)).hive
    }

    package func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        let stream = base.stream(ColonyModelRequest(request))
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await chunk in stream {
                        continuation.yield(chunk.hive)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

package struct ColonyHiveModelRouterAdapter: HiveModelRouter, Sendable {
    let base: any ColonyModelRouter

    package func route(_ request: HiveChatRequest, hints: HiveInferenceHints?) -> AnyHiveModelClient {
        let client = base.route(ColonyModelRequest(request), hints: hints.map(ColonyInferenceHints.init))
        return AnyHiveModelClient(ColonyHiveModelClientAdapter(base: client))
    }
}

package struct ColonyHiveToolRegistryAdapter: HiveToolRegistry, Sendable {
    let base: any ColonyToolRegistry

    package func listTools() -> [HiveToolDefinition] {
        base.listTools().map(\.hive)
    }

    package func invoke(_ call: HiveToolCall) async throws -> HiveToolResult {
        try await base.invoke(ColonyTool.Call(call)).hive
    }
}
