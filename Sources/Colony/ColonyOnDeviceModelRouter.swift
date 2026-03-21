import Foundation
import HiveCore
import ColonyCore

package enum ColonyOnDeviceModelRouterError: Error, Sendable, CustomStringConvertible {
    case onDeviceRequiredButUnavailable

    public var description: String {
        switch self {
        case .onDeviceRequiredButUnavailable:
            "On-device execution was required but no on-device model is available."
        }
    }
}

package struct ColonyOnDeviceModelRouter: HiveModelRouter, ColonyCapabilityReportingHiveModelRouter, Sendable {
    package enum PrivacyBehavior: Sendable {
        /// Prefer on-device, but allow fallback when unavailable.
        case preferOnDevice
        /// Require on-device; when unavailable, the routed model client fails deterministically.
        case requireOnDevice
    }

    package enum NetworkBehavior: Sendable {
        case alwaysFallback
        case preferOnDeviceWhenOffline
        case preferOnDeviceWhenMetered
        case preferOnDeviceWhenOfflineOrMetered
    }

    package struct Policy: Sendable {
        package var privacyBehavior: PrivacyBehavior
        package var networkBehavior: NetworkBehavior

        package init(
            privacyBehavior: PrivacyBehavior = .preferOnDevice,
            networkBehavior: NetworkBehavior = .preferOnDeviceWhenOfflineOrMetered
        ) {
            self.privacyBehavior = privacyBehavior
            self.networkBehavior = networkBehavior
        }
    }

    package init(
        onDevice: AnyHiveModelClient?,
        fallback: AnyHiveModelClient,
        onDeviceCapabilities: ColonyModelCapabilities = [],
        fallbackCapabilities: ColonyModelCapabilities = [],
        policy: Policy = Policy(),
        isOnDeviceAvailable: @escaping @Sendable () -> Bool = { true }
    ) {
        self.onDevice = onDevice
        self.fallback = fallback
        self.onDeviceCapabilities = onDeviceCapabilities
        self.fallbackCapabilities = fallbackCapabilities
        self.policy = policy
        self.isOnDeviceAvailable = isOnDeviceAvailable
    }

    /// Convenience initializer that wires `ColonyFoundationModelsClient` as the on-device model.
    package init(
        fallback: AnyHiveModelClient,
        policy: Policy = Policy(),
        foundationModels: ColonyFoundationModelsClient = ColonyFoundationModelsClient()
    ) {
        self.init(
            onDevice: AnyHiveModelClient(
                ColonyHiveModelClientAdapter(base: foundationModels)
            ),
            fallback: fallback,
            onDeviceCapabilities: foundationModels.colonyModelCapabilities,
            policy: policy,
            isOnDeviceAvailable: { ColonyFoundationModelsClient.isAvailable }
        )
    }

    package func route(_ request: HiveChatRequest, hints: HiveInferenceHints?) -> AnyHiveModelClient {
        guard let hints else { return fallback }

        let wantsOnDevice = Self.wantsOnDevice(hints: hints, policy: policy)

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

    package func colonyModelCapabilities(hints: HiveInferenceHints?) -> ColonyModelCapabilities {
        guard let hints else { return fallbackCapabilities }

        let wantsOnDevice = Self.wantsOnDevice(hints: hints, policy: policy)

        guard wantsOnDevice else {
            return fallbackCapabilities
        }

        if onDevice != nil, isOnDeviceAvailable() {
            return onDeviceCapabilities
        }

        return fallbackCapabilities
    }

    // MARK: - Private

    private static func wantsOnDevice(hints: HiveInferenceHints, policy: Policy) -> Bool {
        if hints.privacyRequired {
            return true
        }

        switch (hints.networkState, policy.networkBehavior) {
        case (.offline, .preferOnDeviceWhenOffline),
             (.offline, .preferOnDeviceWhenOfflineOrMetered),
             (.metered, .preferOnDeviceWhenMetered),
             (.metered, .preferOnDeviceWhenOfflineOrMetered):
            return true
        case (_, .alwaysFallback):
            return false
        default:
            return false
        }
    }

    private let onDevice: AnyHiveModelClient?
    private let fallback: AnyHiveModelClient
    private let policy: Policy
    private let isOnDeviceAvailable: @Sendable () -> Bool
    private let onDeviceCapabilities: ColonyModelCapabilities
    private let fallbackCapabilities: ColonyModelCapabilities
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
