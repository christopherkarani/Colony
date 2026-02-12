import Foundation
import HiveCore

public enum ColonyModelRegistryRouterError: Error, Sendable, CustomStringConvertible, Equatable {
    case noProvidersConfigured
    case unknownProvider(String)
    case malformedModelIdentifier(String)
    case noDefaultProviderConfigured(String)

    public var description: String {
        switch self {
        case .noProvidersConfigured:
            return "No providers configured."
        case .unknownProvider(let provider):
            return "Unknown provider: \(provider)"
        case .malformedModelIdentifier(let model):
            return "Malformed model identifier '\(model)'. Expected 'provider/model'."
        case .noDefaultProviderConfigured(let model):
            return "No default provider configured for unqualified model '\(model)'."
        }
    }
}

/// Routes requests using normalized model identifiers in the form `provider/model`.
///
/// This keeps Swarm/Colony orchestration provider-agnostic while allowing multiple
/// backend clients to be selected deterministically.
public struct ColonyModelRegistryRouter: HiveModelRouter, Sendable {
    public struct Provider: Sendable {
        public let id: String
        public let client: AnyHiveModelClient

        public init(id: String, client: AnyHiveModelClient) {
            self.id = id
            self.client = client
        }
    }

    public init(
        providers: [Provider],
        defaultProviderID: String? = nil
    ) {
        self.providersByID = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0.client) })
        self.defaultProviderID = defaultProviderID
    }

    public func route(_ request: HiveChatRequest, hints: HiveInferenceHints?) -> AnyHiveModelClient {
        AnyHiveModelClient(
            ColonyRoutedModelClient(
                providersByID: providersByID,
                defaultProviderID: defaultProviderID,
                request: request,
                hints: hints
            )
        )
    }

    private let providersByID: [String: AnyHiveModelClient]
    private let defaultProviderID: String?
}

private struct ColonyRoutedModelClient: HiveModelClient, Sendable {
    let providersByID: [String: AnyHiveModelClient]
    let defaultProviderID: String?
    let request: HiveChatRequest
    let hints: HiveInferenceHints?

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        let resolved = try resolve(request: request)
        _ = hints
        return try await resolved.client.complete(resolved.request)
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let resolved = try resolve(request: request)
                    for try await chunk in resolved.client.stream(resolved.request) {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func resolve(request: HiveChatRequest) throws -> (client: AnyHiveModelClient, request: HiveChatRequest) {
        guard providersByID.isEmpty == false else {
            throw ColonyModelRegistryRouterError.noProvidersConfigured
        }

        if let separatorIndex = request.model.firstIndex(of: "/") {
            let providerID = String(request.model[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let modelName = String(request.model[request.model.index(after: separatorIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard providerID.isEmpty == false, modelName.isEmpty == false else {
                throw ColonyModelRegistryRouterError.malformedModelIdentifier(request.model)
            }
            guard let client = providersByID[providerID] else {
                throw ColonyModelRegistryRouterError.unknownProvider(providerID)
            }

            let rewritten = HiveChatRequest(
                model: modelName,
                messages: request.messages,
                tools: request.tools
            )
            return (client, rewritten)
        }

        guard let defaultProviderID,
              let defaultClient = providersByID[defaultProviderID]
        else {
            throw ColonyModelRegistryRouterError.noDefaultProviderConfigured(request.model)
        }
        return (defaultClient, request)
    }
}
