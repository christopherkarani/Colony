import Foundation
@_spi(ColonyInternal) import Swarm
import ColonyCore

package struct ColonyModelClientBridge: HiveModelClient, Sendable {
    let client: any ColonyModelClient

    package func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        let response = try await client.generate(ColonyInferenceRequest(request))
        return response.hiveChatResponse
    }

    package func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        let stream = client.stream(ColonyInferenceRequest(request))
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await chunk in stream {
                        switch chunk {
                        case .token(let token):
                            continuation.yield(.token(token))
                        case .final(let response):
                            continuation.yield(.final(response.hiveChatResponse))
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
