import Foundation
import ConduitAdvanced
import HiveCore
import ColonyCore

package struct ColonyDefaultConduitModelClient: HiveModelClient, ColonyCapabilityReportingHiveModelClient, Sendable {
    package let modelName: String

    package var colonyModelCapabilities: ColonyModelCapabilities {
        []
    }

    private let provider: FoundationModelsProvider
    private let generateConfig: GenerateConfig

    package init(
        modelName: String,
        providerConfiguration: FMConfiguration = .default,
        generateConfig: GenerateConfig = .default
    ) {
        self.modelName = modelName
        self.provider = FoundationModelsProvider(configuration: providerConfiguration)
        self.generateConfig = generateConfig
    }

    package func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        let result = try await provider.generate(
            messages: makeMessages(from: request.messages),
            model: .foundationModels,
            config: generateConfig
        )
        return HiveChatResponse(
            message: HiveChatMessage(
                id: UUID().uuidString,
                role: .assistant,
                content: result.text
            )
        )
    }

    package func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let stream = provider.streamWithMetadata(
                messages: makeMessages(from: request.messages),
                model: .foundationModels,
                config: generateConfig
            )

            Task {
                do {
                    var accumulatedText = ""
                    for try await chunk in stream {
                        if chunk.text.isEmpty == false {
                            accumulatedText.append(chunk.text)
                            continuation.yield(.token(chunk.text))
                        }

                        if chunk.isComplete {
                            continuation.yield(
                                .final(
                                    HiveChatResponse(
                                        message: HiveChatMessage(
                                            id: UUID().uuidString,
                                            role: .assistant,
                                            content: accumulatedText
                                        )
                                    )
                                )
                            )
                            continuation.finish()
                            return
                        }
                    }

                    continuation.finish(
                        throwing: HiveRuntimeError.modelStreamInvalid("Missing final completion chunk.")
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func makeMessages(from messages: [HiveChatMessage]) -> [Message] {
        messages.compactMap { message in
            guard message.op == nil else { return nil }

            switch message.role {
            case .system:
                return .system(message.content)
            case .user:
                return .user(message.content)
            case .assistant:
                return .assistant(message.content)
            case .tool:
                let toolName = message.name ?? "tool"
                let toolCallID = message.toolCallID ?? UUID().uuidString
                let output = Transcript.ToolOutput(
                    id: toolCallID,
                    toolName: toolName,
                    segments: [.text(.init(content: message.content))]
                )
                return .toolOutput(output)
            }
        }
    }
}
