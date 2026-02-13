import Foundation
import HiveCore

public enum ColonyOnDeviceModelRouterError: Error, Sendable, CustomStringConvertible {
    case onDeviceRequiredButUnavailable

    public var description: String {
        switch self {
        case .onDeviceRequiredButUnavailable:
            "On-device execution was required but no on-device model is available."
        }
    }
}

public struct ColonyOnDeviceModelRouter: HiveModelRouter, Sendable {
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

    public init(
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

    /// Convenience initializer that wires `ColonyFoundationModelsClient` as the on-device model.
    public init(
        fallback: AnyHiveModelClient,
        policy: Policy = Policy(),
        foundationModels: ColonyFoundationModelsClient = ColonyFoundationModelsClient()
    ) {
        self.init(
            onDevice: AnyHiveModelClient(foundationModels),
            fallback: fallback,
            policy: policy,
            isOnDeviceAvailable: { ColonyFoundationModelsClient.isAvailable }
        )
    }

    public func route(_ request: HiveChatRequest, hints: HiveInferenceHints?) -> AnyHiveModelClient {
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

    private let onDevice: AnyHiveModelClient?
    private let fallback: AnyHiveModelClient
    private let policy: Policy
    private let isOnDeviceAvailable: @Sendable () -> Bool
}

private struct ColonyFailingModelClient: HiveModelClient, Sendable {
    let error: ColonyOnDeviceModelRouterError

    func complete(_ request: HiveChatRequest) async throws -> HiveChatResponse {
        throw error
    }

    func stream(_ request: HiveChatRequest) -> AsyncThrowingStream<HiveChatStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }
}

