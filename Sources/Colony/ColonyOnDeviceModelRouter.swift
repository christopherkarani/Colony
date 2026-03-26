import Foundation
@_spi(ColonyInternal) import Swarm

/// Errors that can occur during on-device routing.
public enum OnDeviceRoutingError: Error, Sendable, CustomStringConvertible {
    case onDeviceRequiredButUnavailable

    public var description: String {
        switch self {
        case .onDeviceRequiredButUnavailable:
            "On-device execution was required but no on-device model is available."
        }
    }
}

public typealias ColonyOnDeviceModelRouterError = OnDeviceRoutingError

public struct ColonyOnDeviceModelRouter: ColonyModelClient, Sendable {
    public enum PrivacyBehavior: Sendable {
        /// Prefer on-device, but allow fallback when unavailable.
        case preferOnDevice
        /// Require on-device; when unavailable, the routed model client fails deterministically.
        case requireOnDevice
    }

    public struct Policy: Sendable {
        public var privacyBehavior: PrivacyBehavior
        public var preferOnDeviceWhenOffline: Bool
        public var preferOnDeviceWhenMetered: Bool

        public init(
            privacyBehavior: PrivacyBehavior = .preferOnDevice,
            preferOnDeviceWhenOffline: Bool = true,
            preferOnDeviceWhenMetered: Bool = true
        ) {
            self.privacyBehavior = privacyBehavior
            self.preferOnDeviceWhenOffline = preferOnDeviceWhenOffline
            self.preferOnDeviceWhenMetered = preferOnDeviceWhenMetered
        }
    }

    /// Creates a new on-device model router.
    ///
    /// - Parameters:
    ///   - onDevice: Optional on-device model client.
    ///   - fallback: Fallback model client (typically cloud).
    ///   - policy: Routing policy.
    ///   - isOnDeviceAvailable: Closure to check on-device availability.
    public init(
        onDevice: (any ColonyModelClient)?,
        fallback: any ColonyModelClient,
        policy: Policy = Policy(),
        isOnDeviceAvailable: @escaping @Sendable () -> Bool = { true }
    ) {
        self.onDevice = onDevice.map { AnyHiveModelClient(ColonyModelClientBridge(client: $0)) }
        self.fallback = AnyHiveModelClient(ColonyModelClientBridge(client: fallback))
        self.policy = policy
        self.isOnDeviceAvailable = isOnDeviceAvailable
    }

    /// Convenience initializer that wires `ColonyFoundationModelsClient` as the on-device model.
    ///
    /// - Parameters:
    ///   - fallback: Fallback model client.
    ///   - policy: Routing policy.
    ///   - foundationModels: Foundation models client to use for on-device.
    public init(
        fallback: any ColonyModelClient,
        policy: Policy = Policy(),
        foundationModels: ColonyFoundationModelsClient = ColonyFoundationModelsClient()
    ) {
        self.init(
            onDevice: foundationModels,
            fallback: fallback,
            policy: policy,
            isOnDeviceAvailable: { ColonyFoundationModelsClient.isAvailable }
        )
    }

    /// Routes a request to either on-device or fallback client.
    ///
    /// - Parameters:
    ///   - request: The chat request.
    ///   - hints: Inference hints for routing decisions.
    /// - Returns: Appropriate model client.
    public func generate(_ request: ColonyInferenceRequest) async throws -> ColonyInferenceResponse {
        let response = try await selectedClient(for: request).complete(request.hiveChatRequest)
        return ColonyInferenceResponse(response)
    }

    public func stream(_ request: ColonyInferenceRequest) -> AsyncThrowingStream<ColonyInferenceStreamChunk, Error> {
        let stream = selectedClient(for: request).stream(request.hiveChatRequest)
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await chunk in stream {
                        switch chunk {
                        case .token(let token):
                            continuation.yield(.token(token))
                        case .final(let response):
                            continuation.yield(.final(ColonyInferenceResponse(response)))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    package init(
        onDevice: AnyHiveModelClient?,
        fallback: AnyHiveModelClient,
        policy: Policy = Policy(),
        isOnDeviceAvailable: @escaping @Sendable () -> Bool = { true }
    ) {
        self.onDevice = onDevice
        self.fallback = fallback
        self.policy = policy
        self.isOnDeviceAvailable = isOnDeviceAvailable
    }

    package func route(_ request: HiveChatRequest, hints: HiveInferenceHints?) -> AnyHiveModelClient {
        guard let hints else { return fallback }

        let wantsOnDevice: Bool = {
            if hints.privacyRequired {
                return true
            }

            switch hints.networkState {
            case .offline:
                return policy.preferOnDeviceWhenOffline
            case .metered:
                return policy.preferOnDeviceWhenMetered
            case .online:
                return false
            }
        }()

        guard wantsOnDevice else {
            return fallback
        }

        if let onDevice, isOnDeviceAvailable() {
            return onDevice
        }

        if hints.privacyRequired, policy.privacyBehavior == .requireOnDevice {
            return AnyHiveModelClient(ColonyFailingModelClient(error: .onDeviceRequiredButUnavailable))
        }

        return fallback
    }

    // MARK: - Private

    private func selectedClient(for request: ColonyInferenceRequest) -> AnyHiveModelClient {
        if let onDevice, isOnDeviceAvailable(), request.complexity != .complex {
            return onDevice
        }
        if policy.privacyBehavior == .requireOnDevice, onDevice == nil || isOnDeviceAvailable() == false {
            return AnyHiveModelClient(ColonyFailingModelClient(error: .onDeviceRequiredButUnavailable))
        }
        return fallback
    }

    private let onDevice: AnyHiveModelClient?
    private let fallback: AnyHiveModelClient
    private let policy: Policy
    private let isOnDeviceAvailable: @Sendable () -> Bool
}

/// A model client that always fails with a specific error.
private struct ColonyFailingModelClient: HiveModelClient, Sendable {
    let error: OnDeviceRoutingError

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        throw error
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }
}
