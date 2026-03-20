import Foundation
import ColonyCore

/// Progressive disclosure entry points for Colony.
///
/// ```swift
/// // Tier 1: Zero-config
/// let agent = try await Colony.agent(model: .foundationModels())
/// let handle = await agent.send("Hello")
///
/// // Tier 2: With services
/// let agent = try await Colony.agent(
///     model: .foundationModels(),
///     capabilities: [.filesystem, .shell, .git]
/// ) {
///     .filesystem(myFS)
///     .memory(waxMemory)
/// }
/// ```
extension Colony {
    /// Create an agent with zero configuration. Uses default in-memory services.
    ///
    /// - Parameter model: The model configuration (e.g. `.foundationModels()`, `.onDevice(...)`)
    /// - Returns: A ready-to-use `ColonyRuntime`
    public static func agent(
        model: ColonyModel
    ) async throws -> ColonyRuntime {
        try await ColonyBootstrap().makeRuntime(
            options: ColonyRuntimeCreationOptions(
                modelName: "default",
                model: model
            )
        )
    }

    /// Create an agent with custom capabilities and services.
    ///
    /// - Parameters:
    ///   - model: The model configuration
    ///   - capabilities: Agent capabilities (defaults to `.default`)
    ///   - threadID: Unique thread identifier (auto-generated if omitted)
    ///   - services: A `@ColonyServiceBuilder` closure declaring backend services
    /// - Returns: A ready-to-use `ColonyRuntime`
    public static func agent(
        model: ColonyModel,
        capabilities: ColonyRuntimeCapabilities = .default,
        threadID: ColonyThreadID = ColonyThreadID("colony:" + UUID().uuidString),
        @ColonyServiceBuilder services: () -> [ColonyService]
    ) async throws -> ColonyRuntime {
        let runtimeServices = ColonyRuntimeServices(services)
        return try await ColonyBootstrap().makeRuntime(
            options: ColonyRuntimeCreationOptions(
                threadID: threadID,
                modelName: "default",
                model: model,
                services: runtimeServices,
                configure: { config in
                    config.model.capabilities = capabilities
                }
            )
        )
    }

    /// Create an agent with full control over profile, lane, and services.
    ///
    /// This is the advanced entry point for power users who need control over
    /// the runtime profile, lane routing, checkpointing, and run options.
    public static func agent(
        model: ColonyModel,
        profile: ColonyProfile = .onDevice4k,
        lane: ColonyLane? = nil,
        capabilities: ColonyRuntimeCapabilities = .default,
        threadID: ColonyThreadID = ColonyThreadID("colony:" + UUID().uuidString),
        checkpointing: ColonyCheckpointConfiguration = .inMemory,
        @ColonyServiceBuilder services: () -> [ColonyService] = { [] },
        configure: @escaping @Sendable (inout ColonyConfiguration) -> Void = { _ in },
        configureRunOptions: @escaping @Sendable (inout ColonyRunOptions) -> Void = { _ in }
    ) async throws -> ColonyRuntime {
        let runtimeServices = ColonyRuntimeServices(services)
        return try await ColonyBootstrap().makeRuntime(
            options: ColonyRuntimeCreationOptions(
                profile: profile,
                threadID: threadID,
                modelName: "default",
                lane: lane,
                model: model,
                services: runtimeServices,
                checkpointing: checkpointing,
                configure: { config in
                    config.model.capabilities = capabilities
                    configure(&config)
                },
                configureRunOptions: configureRunOptions
            )
        )
    }
}

// MARK: - ColonyRuntime Convenience

extension ColonyRuntime {
    /// Send a message to the agent. Shorthand for `sendUserMessage(_:)`.
    ///
    /// ```swift
    /// let handle = await agent.send("Explain this code")
    /// let outcome = try await handle.outcome.value
    /// ```
    public func send(
        _ text: String,
        optionsOverride: ColonyRunOptions? = nil
    ) async -> ColonyRunHandle {
        await sendUserMessage(text, optionsOverride: optionsOverride)
    }
}
