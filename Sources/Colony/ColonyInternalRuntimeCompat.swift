import Foundation
import ColonyCore

package typealias SwarmChatRole = ColonyMessageRole
package typealias SwarmChatMessage = ColonyMessage
package typealias SwarmToolCall = ColonyToolCall
package typealias SwarmToolDefinition = ColonyToolDefinition

package extension ColonyInferenceRequest {
    init(_ request: SwarmChatRequest) {
        self.init(
            messages: request.messages,
            tools: request.tools,
            modelName: request.model.isEmpty ? nil : request.model
        )
    }

    var swarmChatRequest: SwarmChatRequest {
        SwarmChatRequest(
            model: modelName ?? "",
            messages: messages,
            tools: tools
        )
    }
}

package extension ColonyInferenceResponse {
    init(_ response: SwarmChatResponse) {
        self.init(message: response.message)
    }

    var swarmChatResponse: SwarmChatResponse {
        SwarmChatResponse(message: message)
    }
}

package struct SwarmChatRequest: Sendable, Equatable {
    package let model: String
    package let messages: [SwarmChatMessage]
    package let tools: [SwarmToolDefinition]

    package init(
        model: String,
        messages: [SwarmChatMessage],
        tools: [SwarmToolDefinition] = []
    ) {
        self.model = model
        self.messages = messages
        self.tools = tools
    }
}

package struct SwarmChatResponse: Sendable, Equatable {
    package let message: SwarmChatMessage

    package init(message: SwarmChatMessage) {
        self.message = message
    }
}

package enum SwarmChatStreamChunk: Sendable, Equatable {
    case token(String)
    case final(SwarmChatResponse)
}

package struct SwarmToolResult: Sendable, Equatable {
    package let toolCallID: String
    package let content: String

    package init(toolCallID: String, content: String) {
        self.toolCallID = toolCallID
        self.content = content
    }
}

package protocol SwarmModelClient: Sendable {
    func complete(_ request: SwarmChatRequest) async throws -> SwarmChatResponse
    func stream(_ request: SwarmChatRequest) -> AsyncThrowingStream<SwarmChatStreamChunk, Error>
}

package struct SwarmAnyModelClient: Sendable {
    private let completeHandler: @Sendable (SwarmChatRequest) async throws -> SwarmChatResponse
    private let streamHandler: @Sendable (SwarmChatRequest) -> AsyncThrowingStream<SwarmChatStreamChunk, Error>

    package init(_ client: any SwarmModelClient) {
        completeHandler = { request in
            try await client.complete(request)
        }
        streamHandler = { request in
            client.stream(request)
        }
    }

    package func complete(_ request: SwarmChatRequest) async throws -> SwarmChatResponse {
        try await completeHandler(request)
    }

    package func stream(_ request: SwarmChatRequest) -> AsyncThrowingStream<SwarmChatStreamChunk, Error> {
        streamHandler(request)
    }
}

package extension SwarmModelClient {
    func streamFinal(_ request: SwarmChatRequest) async throws -> SwarmChatResponse {
        var finalResponse: SwarmChatResponse?
        for try await chunk in stream(request) {
            if case .final(let response) = chunk {
                finalResponse = response
            }
        }

        guard let finalResponse else {
            throw SwarmRuntimeError.modelStreamInvalid("Missing final response chunk.")
        }
        return finalResponse
    }
}

package protocol SwarmModelRouter: Sendable {
    func route(_ request: SwarmChatRequest, hints: SwarmInferenceHints?) -> SwarmAnyModelClient
}

package protocol SwarmToolRegistry: Sendable {
    func listTools() -> [SwarmToolDefinition]
    func invoke(_ call: SwarmToolCall) async throws -> SwarmToolResult
}

package struct SwarmAnyToolRegistry: Sendable {
    private let listToolsHandler: @Sendable () -> [SwarmToolDefinition]
    private let invokeHandler: @Sendable (SwarmToolCall) async throws -> SwarmToolResult

    package init(_ registry: any SwarmToolRegistry) {
        listToolsHandler = {
            registry.listTools()
        }
        invokeHandler = { call in
            try await registry.invoke(call)
        }
    }

    package func listTools() -> [SwarmToolDefinition] {
        listToolsHandler()
    }

    package func invoke(_ call: SwarmToolCall) async throws -> SwarmToolResult {
        try await invokeHandler(call)
    }
}

package protocol SwarmClock: Sendable {
    func nowNanoseconds() -> UInt64
    func sleep(nanoseconds: UInt64) async throws
}

package protocol SwarmLogger: Sendable {
    func debug(_ message: String, metadata: [String: String])
    func info(_ message: String, metadata: [String: String])
    func error(_ message: String, metadata: [String: String])
}

package struct SwarmInferenceHints: Sendable, Equatable {
    package enum LatencyTier: Sendable, Equatable {
        case interactive
        case background
    }

    package enum NetworkState: Sendable, Equatable {
        case offline
        case metered
        case online
    }

    package let privacyRequired: Bool
    package let networkState: NetworkState

    package init(
        privacyRequired: Bool = false,
        networkState: NetworkState = .online
    ) {
        self.privacyRequired = privacyRequired
        self.networkState = networkState
    }

    package init(
        latencyTier: LatencyTier,
        privacyRequired: Bool,
        tokenBudget: Int?,
        networkState: NetworkState
    ) {
        _ = latencyTier
        _ = tokenBudget
        self.init(
            privacyRequired: privacyRequired,
            networkState: networkState
        )
    }
}

package enum SwarmRuntimeError: Error, Sendable, Equatable {
    case modelClientMissing
    case modelStreamInvalid(String)
    case invalidMessagesUpdate
    case resumeInterruptMismatch(expected: ColonyInterruptID, found: ColonyInterruptID)
    case noInterruptToResume
}

package enum ColonySchema {
    package struct ChannelKey<Value: Sendable>: Sendable {
        package let id: ColonyChannelID

        package init(_ rawValue: String) {
            id = ColonyChannelID(rawValue)
        }
    }

    package enum Channels {
        package static let messages = ChannelKey<[SwarmChatMessage]>("messages")
        package static let llmInputMessages = ChannelKey<[SwarmChatMessage]?>("llmInputMessages")
        package static let pendingToolCalls = ChannelKey<[SwarmToolCall]>("pendingToolCalls")
        package static let finalAnswer = ChannelKey<String?>("finalAnswer")
        package static let todos = ChannelKey<[ColonyTodo]>("todos")
        package static let currentToolCall = ChannelKey<SwarmToolCall>("currentToolCall")
    }

    package static let removeAllMessagesID = "__remove_all__"
}
