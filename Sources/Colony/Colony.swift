@_exported import ColonyCore

// MARK: - Colony Namespace

/// The primary entry point for creating and configuring Colony runtimes.
///
/// Use the `Colony` enum to quickly create a configured `ColonyRuntime` with
/// sensible defaults. For advanced configuration, use `ColonyBuilder` directly.
///
/// Example:
/// ```swift
/// let runtime = try Colony.start(modelName: "llama3.2")
/// let handle = await runtime.sendUserMessage("Hello, Colony!")
/// ```
public enum Colony {
    /// Starts a new Colony runtime with the given model name.
    ///
    /// - Parameters:
    ///   - modelName: The name of the model to use (e.g., "llama3.2").
    ///   - profile: The profile to use for configuration. Defaults to `.device`.
    ///   - configure: An optional closure to customize the configuration.
    ///
    /// - Returns: A configured `ColonyRuntime` ready to use.
    ///
    /// - Throws: An error if the runtime could not be created.
    public static func start(
        modelName: String,
        profile: ColonyProfile = .device,
        configure: @Sendable (inout ColonyConfiguration) -> Void = { _ in }
    ) throws -> ColonyRuntime {
        try ColonyBuilder()
            .model(name: modelName)
            .profile(profile)
            .configure(configure)
            .build()
    }
}

// MARK: - Version

/// Namespace for the Colony module version.
public enum ColonyVersion {
    /// Semantic version string for Colony.
    public static let string = "1.0.0-rc.1"
}
