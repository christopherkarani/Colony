import Foundation
import ColonyCore

// MARK: - ColonyBootstrap (Deprecated)

/// The single public entry point for bootstrapping a Colony runtime.
///
/// Use `ColonyBootstrap` to quickly create a configured `ColonyRuntime` with
/// sensible defaults. For advanced configuration, use `ColonyAgentFactory` directly.
///
/// Example:
/// ```swift
/// let runtime = try ColonyBootstrap.bootstrap(modelName: "llama3.2")
/// let handle = await runtime.sendUserMessage("Hello, Colony!")
/// ```
@available(*, deprecated, renamed: "Colony")
public enum ColonyBootstrap {
    /// Bootstraps a Colony runtime with the given model name.
    ///
    /// - Parameters:
    ///   - modelName: The name of the model to use (e.g., "llama3.2").
    ///   - profile: The profile to use for configuration. Defaults to `.device`.
    ///   - threadID: An optional thread ID for conversation continuity.
    ///
    /// - Returns: A configured `ColonyRuntime` ready to use.
    ///
    /// - Throws: An error if the runtime could not be created.
    @available(*, deprecated, renamed: "Colony.start")
    public static func bootstrap(
        modelName: String,
        profile: ColonyProfile = .device,
        threadID: ColonyThreadID? = nil
    ) throws -> ColonyRuntime {
        let factory = ColonyAgentFactory()
        return try factory.makeRuntime(
            profile: profile,
            threadID: threadID ?? ColonyThreadID("colony:" + UUID().uuidString),
            modelName: modelName
        )
    }
}
