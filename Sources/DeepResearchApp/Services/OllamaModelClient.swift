import Foundation
import Colony

struct OllamaModelClient: HiveModelClient, Sendable {
    let apiClient: OllamaAPIClient
    let modelName: String

    init(apiClient: OllamaAPIClient = OllamaAPIClient(), modelName: String) {
        self.apiClient = apiClient
        self.modelName = modelName
    }

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        try await streamFinal(request)
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        let ollamaMessages = request.messages.compactMap { convertMessage($0) }
        let ollamaTools: [OllamaToolDef]? = request.tools.isEmpty ? nil : request.tools.map { convertToolDefinition($0) }
        let model = request.model.isEmpty ? modelName : request.model

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var accumulatedContent = ""
                    var accumulatedToolCalls: [OllamaToolCallWrapper] = []

                    let stream = apiClient.chatStream(
                        model: model,
                        messages: ollamaMessages,
                        tools: ollamaTools
                    )

                    for try await chunk in stream {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }

                        let token = chunk.message.content
                        if !token.isEmpty {
                            accumulatedContent += token
                            continuation.yield(.token(token))
                        }

                        if let toolCalls = chunk.message.toolCalls {
                            accumulatedToolCalls.append(contentsOf: toolCalls)
                        }

                        if chunk.done {
                            let hiveToolCalls = accumulatedToolCalls.map { convertToolCall($0) }
                            let message = HiveChatMessage(
                                id: UUID().uuidString,
                                role: .assistant,
                                content: accumulatedContent,
                                toolCalls: hiveToolCalls
                            )
                            let response = HiveChatResponse(message: message)
                            continuation.yield(.final(response))
                            continuation.finish()
                            return
                        }
                    }

                    // If we exit the loop without a done chunk, emit final with what we have.
                    let message = HiveChatMessage(
                        id: UUID().uuidString,
                        role: .assistant,
                        content: accumulatedContent,
                        toolCalls: accumulatedToolCalls.map { convertToolCall($0) }
                    )
                    let response = HiveChatResponse(message: message)
                    continuation.yield(.final(response))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Conversion Helpers

    private func convertMessage(_ message: HiveChatMessage) -> OllamaChatMessage? {
        guard message.op == nil else { return nil }

        let role: String
        switch message.role {
        case .system:
            role = "system"
        case .user:
            role = "user"
        case .assistant:
            role = "assistant"
        case .tool:
            role = "tool"
        }

        var ollamaToolCalls: [OllamaToolCallWrapper]? = nil
        if !message.toolCalls.isEmpty {
            ollamaToolCalls = message.toolCalls.compactMap { call -> OllamaToolCallWrapper? in
                guard let argsData = call.argumentsJSON.data(using: .utf8),
                      let argsDict = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] else {
                    return nil
                }
                let convertedArgs = argsDict.mapValues { convertToOllamaJSONValue($0) }
                return OllamaToolCallWrapper(
                    function: OllamaToolCallFunction(
                        name: call.name,
                        arguments: convertedArgs
                    )
                )
            }
        }

        return OllamaChatMessage(
            role: role,
            content: message.content,
            toolCalls: ollamaToolCalls
        )
    }

    private func convertToolDefinition(_ tool: HiveToolDefinition) -> OllamaToolDef {
        OllamaToolDef(
            function: OllamaToolFunction(
                name: tool.name,
                description: tool.description,
                parameters: OllamaJSONValue.from(jsonString: tool.parametersJSONSchema)
            )
        )
    }

    private func convertToolCall(_ wrapper: OllamaToolCallWrapper) -> HiveToolCall {
        let argumentsJSON: String
        if let data = try? JSONSerialization.data(
            withJSONObject: wrapper.function.arguments.mapValues { encodeJSONValue($0) },
            options: [.sortedKeys]
        ) {
            argumentsJSON = String(data: data, encoding: .utf8) ?? "{}"
        } else {
            argumentsJSON = "{}"
        }

        return HiveToolCall(
            id: UUID().uuidString,
            name: wrapper.function.name,
            argumentsJSON: argumentsJSON
        )
    }

    private func convertToOllamaJSONValue(_ value: Any) -> OllamaJSONValue {
        switch value {
        case let string as String:
            return .string(string)
        case let int as Int:
            return .int(int)
        case let double as Double:
            return .double(double)
        case let bool as Bool:
            return .bool(bool)
        default:
            return .string(String(describing: value))
        }
    }

    private func encodeJSONValue(_ value: OllamaJSONValue) -> Any {
        switch value {
        case .string(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .bool(let v): return v
        case .null: return NSNull()
        case .array(let v): return v.map { encodeJSONValue($0) }
        case .object(let v): return v.mapValues { encodeJSONValue($0) }
        }
    }
}
