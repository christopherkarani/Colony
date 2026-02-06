import Foundation
import Colony

enum ResearchAssistantModelSelection: Sendable, Equatable {
    case foundation
    case mock
}

enum ResearchAssistantModelSelectionError: Error, Sendable, Equatable, CustomStringConvertible {
    case foundationModeRequiresAvailableModel

    var description: String {
        switch self {
        case .foundationModeRequiresAvailableModel:
            return "Foundation mode requires an available on-device Foundation Model."
        }
    }
}

struct ResearchAssistantResolvedModel: Sendable {
    var selection: ResearchAssistantModelSelection
    var client: AnyHiveModelClient
}

struct ResearchAssistantModelResolver: Sendable {
    var isFoundationAvailable: @Sendable () -> Bool

    init(isFoundationAvailable: @escaping @Sendable () -> Bool = { ColonyFoundationModelsClient.isAvailable }) {
        self.isFoundationAvailable = isFoundationAvailable
    }

    func resolve(mode: ResearchAssistantModelMode) throws -> ResearchAssistantResolvedModel {
        switch mode {
        case .auto:
            if isFoundationAvailable() {
                return ResearchAssistantResolvedModel(
                    selection: .foundation,
                    client: AnyHiveModelClient(ColonyFoundationModelsClient())
                )
            }
            return ResearchAssistantResolvedModel(
                selection: .mock,
                client: AnyHiveModelClient(MockResearchModel())
            )
        case .foundation:
            if isFoundationAvailable() {
                return ResearchAssistantResolvedModel(
                    selection: .foundation,
                    client: AnyHiveModelClient(ColonyFoundationModelsClient())
                )
            }
            throw ResearchAssistantModelSelectionError.foundationModeRequiresAvailableModel
        case .mock:
            return ResearchAssistantResolvedModel(
                selection: .mock,
                client: AnyHiveModelClient(MockResearchModel())
            )
        }
    }
}

final class MockResearchModel: HiveModelClient, @unchecked Sendable {
    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        try await streamFinal(request)
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        let response = HiveChatResponse(
            message: HiveChatMessage(
                id: UUID().uuidString,
                role: .assistant,
                content: "MOCK_RESEARCH_SUMMARY: placeholder",
                toolCalls: []
            )
        )
        _ = request
        return AsyncThrowingStream { continuation in
            continuation.yield(.final(response))
            continuation.finish()
        }
    }
}
