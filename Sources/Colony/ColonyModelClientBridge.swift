import Foundation
import ColonyCore

package struct ColonyModelClientBridge: SwarmModelClient, Sendable {
    let client: any ColonyModelClient

    package func complete(_ request: SwarmChatRequest) async throws -> SwarmChatResponse {
        let response = try await client.generate(ColonyInferenceRequest(request))
        return response.swarmChatResponse
    }

    package func stream(_ request: SwarmChatRequest) -> AsyncThrowingStream<SwarmChatStreamChunk, Error> {
        let stream = client.stream(ColonyInferenceRequest(request))
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await chunk in stream {
                        switch chunk {
                        case .token(let token):
                            continuation.yield(.token(token))
                        case .final(let response):
                            continuation.yield(.final(response.swarmChatResponse))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
