import Foundation
import Testing
@_spi(ColonyInternal) import Swarm
@testable import Colony

@Suite("ColonyBuilder Tests")
struct ColonyBuilderTests {
    @Test("original builder is unchanged after modifications")
    func originalBuilderUnchanged() throws {
        let original = ColonyBuilder()
        let modified = original
            .model(name: "modified-model")
            .model(AnyHiveModelClient(FixedResponseModel(content: "done")))

        #expect(throws: ColonyBuilderError.self) {
            try original.build()
        }

        let runtime = try modified.build()
        #expect(runtime.threadID.rawValue.hasPrefix("colony:"))
    }

    @Test("build fails without inference source")
    func buildRequiresInferenceSource() throws {
        let builder = ColonyBuilder()
            .model(name: "test-model")

        #expect(throws: ColonyBuilderError.self) {
            try builder.build()
        }
    }

    @Test("builder preserves runtime configuration through execution")
    func builderPreservesConfiguration() async throws {
        let runtime = try ColonyBuilder()
            .model(name: "test-model")
            .model(AnyHiveModelClient(ToolCallingModel()))
            .configure { configuration in
                configuration.toolApprovalPolicy = .never
                configuration.mandatoryApprovalRiskLevels = []
            }
            .build()

        let handle = await runtime.sendUserMessage("write a note")
        let outcome = try await handle.outcome.value
        guard case let .finished(output, _) = outcome,
              case let .fullStore(store) = output else {
            Issue.record("Expected finished full-store outcome.")
            return
        }

        #expect((try store.get(ColonySchema.Channels.finalAnswer)) == "done")
    }

    @Test("builder can route inference through a routing policy")
    func builderRoutingPolicyExecutesInference() async throws {
        let runtime = try ColonyBuilder()
            .model(name: "test-model")
            .routingPolicy(
                ColonyRoutingPolicy(
                    strategy: .single(FixedResponseModel(content: "done-via-router")),
                    retryPolicy: .default
                )
            )
            .build()

        let handle = await runtime.sendUserMessage("hello")
        let outcome = try await handle.outcome.value
        guard case let .finished(output, _) = outcome,
              case let .fullStore(store) = output else {
            Issue.record("Expected finished full-store outcome.")
            return
        }

        #expect((try store.get(ColonySchema.Channels.finalAnswer)) == "done-via-router")
    }

    @Test("profile configuration survives unrelated builder overrides")
    func profileConfigurationSurvivesBuilderOverrides() async throws {
        let runtime = try ColonyBuilder()
            .profile(.cloud)
            .model(name: "test-model")
            .model(AnyHiveModelClient(ToolCallingModel()))
            .configure { configuration in
                configuration.additionalSystemPrompt = "cloud-profile"
                configuration.mandatoryApprovalRiskLevels = []
            }
            .build()

        let handle = await runtime.sendUserMessage("write a note")
        let outcome = try await handle.outcome.value
        guard case let .finished(output, _) = outcome,
              case let .fullStore(store) = output else {
            Issue.record("Expected finished full-store outcome.")
            return
        }

        #expect((try store.get(ColonySchema.Channels.finalAnswer)) == "done")
    }

    @Test("Colony.start forwards configure closure into builder")
    func colonyStartForwardsConfigure() throws {
        #expect(throws: ColonyBuilderError.self) {
            _ = try Colony.start(
                modelName: "test-model",
                configure: { configuration in
                    configuration.additionalSystemPrompt = "forwarded"
                }
            )
        }
    }
}

private final class FixedResponseModel: HiveModelClient, ColonyModelClient, @unchecked Sendable {
    private let content: String

    init(content: String) {
        self.content = content
    }

    func generate(_ request: ColonyInferenceRequest) async throws -> ColonyInferenceResponse {
        ColonyInferenceResponse(
            message: ColonyMessage(
                id: UUID().uuidString,
                role: .assistant,
                content: content
            )
        )
    }

    func stream(_ request: ColonyInferenceRequest) -> AsyncThrowingStream<ColonyInferenceStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(
                .final(
                    ColonyInferenceResponse(
                        message: ColonyMessage(
                            id: UUID().uuidString,
                            role: .assistant,
                            content: self.content
                        )
                    )
                )
            )
            continuation.finish()
        }
    }

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        return try await streamFinal(request)
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        return AsyncThrowingStream { continuation in
            continuation.yield(
                .final(
                    HiveChatResponse(
                        message: HiveChatMessage(
                            id: UUID().uuidString,
                            role: .assistant,
                            content: self.content
                        )
                    )
                )
            )
            continuation.finish()
        }
    }
}

private final class ToolCallingModel: HiveModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount: Int = 0

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        try await streamFinal(request)
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let response: HiveChatResponse = {
                self.lock.lock()
                defer { self.lock.unlock() }
                self.callCount += 1
                if self.callCount == 1 {
                    let call = HiveToolCall(
                        id: "call-1",
                        name: "write_file",
                        argumentsJSON: #"{"path":"/note.md","content":"hello"}"#
                    )
                    return HiveChatResponse(
                        message: HiveChatMessage(
                            id: "assistant-1",
                            role: .assistant,
                            content: "writing",
                            toolCalls: [call]
                        )
                    )
                }

                return HiveChatResponse(
                    message: HiveChatMessage(id: "assistant-2", role: .assistant, content: "done")
                )
            }()
            continuation.yield(.final(response))
            continuation.finish()
        }
    }
}
