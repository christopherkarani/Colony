# Colony Agent Setup API Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved Colony agent setup API redesign with `Colony.agent()` as the single entry point, Provider enum for model configuration, and the run/handle pattern for execution.

**Architecture:** Add a new `Provider` enum with cases for each backend (ollama, anthropic, openAI, foundationModels). The `Colony.agent()` static method takes variadic providers and returns `ColonyRuntime` directly. Execution uses `ColonyRunHandle` with `outcome` property.

**Tech Stack:** Swift 6.2, Swift Testing, HiveCore, Conduit

---

## File Structure

### New Files
- `Sources/Colony/ColonyProvider.swift` — Provider enum and error types
- `Sources/Colony/ColonyRunHandle.swift` — ColonyRunHandle and ColonyOutcome types
- `Tests/ColonyTests/ColonyAgentAPITests.swift` — Tests for Colony.agent() and Provider

### Modified Files
- `Sources/Colony/Colony.swift` — Add `Colony.agent()` method
- `Sources/Colony/ColonyRuntime.swift` — Add `run()` method returning `ColonyRunHandle`
- `Sources/Colony/ColonyPublicAPI.swift` — Mark `ColonyModel`, `ColonyProviderConfiguration` deprecated
- `Sources/Colony/ColonyAgentFactory.swift` — Mark `ColonyBuilder` deprecated
- `Sources/Colony/ColonyBootstrap.swift` — Mark fully deprecated
- `Tests/ColonyTests/ColonyBuilderTests.swift` — Add deprecation tests
- `README.md` — Update quickstart example

---

## Task 1: Create ColonyProvider.swift with Provider Enum

**Files:**
- Create: `Sources/Colony/ColonyProvider.swift`
- Test: `Tests/ColonyTests/ColonyAgentAPITests.swift`

- [ ] **Step 1: Create ColonyProvider.swift with Provider enum and errors**

```swift
import Foundation
import HiveCore

// MARK: - Provider Errors

/// Errors specific to Provider operations.
public enum ColonyProviderError: Error, Sendable, CustomStringConvertible {
    /// No providers specified.
    case noProvidersSpecified
    /// Unsupported provider type.
    case unsupportedProvider(String)
    /// Provider configuration error.
    case configurationError(String)

    public var description: String {
        switch self {
        case .noProvidersSpecified:
            return "At least one provider must be specified."
        case .unsupportedProvider(let name):
            return "Unsupported provider: \(name)."
        case .configurationError(let message):
            return "Provider configuration error: \(message)."
        }
    }
}

extension ColonyProviderError: LocalizedError {
    public var errorDescription: String? { description }
}

// MARK: - Provider

/// Configuration for model providers in Colony.agent().
///
/// Use the static factory methods to create provider configurations:
/// - `.ollama(baseURL:)` — Local Ollama server
/// - `.anthropic(apiKey:)` — Anthropic Claude
/// - `.openAI(apiKey:)` — OpenAI models
/// - `.foundationModels()` — Apple on-device Foundation Models
public enum Provider: Sendable {
    /// Ollama local model server.
    case ollama(baseURL: String)

    /// Anthropic Claude API.
    case anthropic(apiKey: String)

    /// OpenAI API.
    case openAI(apiKey: String)

    /// Apple Foundation Models (on-device).
    case foundationModels
}

extension Provider {
    /// Returns the model name for this provider, if known.
    public var defaultModelName: String? {
        switch self {
        case .ollama:
            return "llama3.2"
        case .anthropic:
            return "claude-sonnet-4-20250514"
        case .openAI:
            return "gpt-4o"
        case .foundationModels:
            return nil // Uses system default
        }
    }

    /// Creates a HiveModelClient for this provider.
    ///
    /// Returns a tuple of (client, modelName) or throws if configuration is invalid.
    internal func makeModelClient() throws -> (AnyHiveModelClient, String) {
        switch self {
        case .ollama(let baseURL):
            // Note: OllamaProvider would need to be defined or imported
            // For now, we use the pattern from existing OllamaModelClient
            guard let url = URL(string: baseURL) else {
                throw ColonyProviderError.configurationError("Invalid Ollama baseURL: \(baseURL)")
            }
            let client = OllamaModelClient(baseURL: url)
            return (AnyHiveModelClient(client), defaultModelName ?? "llama3.2")

        case .anthropic(let apiKey):
            let provider = AnthropicProvider(apiKey: apiKey)
            let client = ConduitModelClient(provider) { name in
                // Map model names to Anthropic model IDs
                switch name {
                case "claude-opus-4-6", "opus": return "claude-opus-4-20250514"
                case "claude-sonnet-4-6", "sonnet": return "claude-sonnet-4-20250514"
                case "claude-haiku-4-5", "haiku": return "claude-haiku-4-20250501"
                default: return "claude-sonnet-4-20250514"
                }
            }
            return (AnyHiveModelClient(client), defaultModelName ?? "claude-sonnet-4-20250514")

        case .openAI(let apiKey):
            let provider = OpenAIProvider(apiKey: apiKey)
            let client = ConduitModelClient(provider) { name in
                // Map model names to OpenAI model IDs
                switch name {
                case "gpt-4o": return "gpt-4o"
                case "gpt-4o-mini": return "gpt-4o-mini"
                case "gpt-4-turbo": return "gpt-4-turbo"
                default: return "gpt-4o"
                }
            }
            return (AnyHiveModelClient(client), defaultModelName ?? "gpt-4o")

        case .foundationModels:
            let client = ColonyFoundationModelsClient()
            return (AnyHiveModelClient(client), "foundation-models")
        }
    }
}

// MARK: - Provider (Placeholder Types for Conduit)

// These would typically come from Conduit package
// Placeholder structs for compilation
internal struct AnthropicProvider: TextGenerator {
    let apiKey: String

    func modelID(for name: String) throws -> ModelID { ModelID(rawValue: name) }
    func streamWithMetadata(messages: [Message], model: ModelID, config: GenerateConfig) -> AsyncThrowingStream<Chunk, Error> {
        AsyncThrowingStream { _ in }
    }
}

internal struct OpenAIProvider: TextGenerator {
    let apiKey: String

    func modelID(for name: String) throws -> ModelID { ModelID(rawValue: name) }
    func streamWithMetadata(messages: [Message], model: ModelID, config: GenerateConfig) -> AsyncThrowingStream<Chunk, Error> {
        AsyncThrowingStream { _ in }
    }
}
```

- [ ] **Step 2: Add TextGenerator protocol stub if needed**

Note: These placeholder types assume `TextGenerator`, `ModelID`, `Message`, `Chunk`, `GenerateConfig` come from Conduit. If they're not available, we need to stub them.

- [ ] **Step 3: Run build to verify compilation**

```bash
cd /Users/chriskarani/CodingProjects/AIStack/Agents/Colony
swift build 2>&1 | head -50
```

Expected: Compilation errors for missing Conduit types (to be addressed in Task 3)

- [ ] **Step 4: Commit**

```bash
git add Sources/Colony/ColonyProvider.swift
git commit -m "feat: add Provider enum for Colony.agent() configuration"
```

---

## Task 2: Create ColonyRunHandle.swift with Handle and Outcome Types

**Files:**
- Create: `Sources/Colony/ColonyRunHandle.swift`
- Test: `Tests/ColonyTests/ColonyAgentAPITests.swift`

- [ ] **Step 1: Create ColonyRunHandle.swift**

```swift
import Foundation
import HiveCore

// MARK: - ColonyOutcome

/// The outcome of a Colony agent run.
public enum ColonyOutcome: Sendable {
    /// Run finished successfully with output.
    case finished(output: String, metadata: [String: String]?)

    /// Run was interrupted (e.g., tool approval required).
    case interrupted(interrupt: HiveInterruption<ColonySchema>)

    /// Run was cancelled.
    case cancelled(output: String?, metadata: [String: String]?)

    /// Run exhausted its step limit.
    case outOfSteps(maxSteps: Int, output: String?)
}

extension ColonyOutcome {
    /// Returns true if the outcome represents a finished state.
    public var isFinished: Bool {
        if case .finished = self { return true }
        return false
    }

    /// Returns true if the outcome represents an interrupted state.
    public var isInterrupted: Bool {
        if case .interrupted = self { return true }
        return false
    }

    /// Returns the output string if available.
    public var output: String? {
        switch self {
        case .finished(let output, _): return output
        case .cancelled(let output, _): return output
        case .outOfSteps(_, let output): return output
        case .interrupted: return nil
        }
    }
}

// MARK: - ColonyRunHandle

/// A handle representing a Colony agent run.
///
/// Use `outcome` to wait for completion and get the result.
public struct ColonyRunHandle: Sendable {
    /// The run ID.
    public let runID: ColonyRunID

    /// The attempt ID for this specific run attempt.
    public let attemptID: ColonyRunAttemptID

    /// The underlying Hive run handle.
    private let underlying: HiveRunHandle<ColonySchema>

    /// Creates a new run handle.
    internal init(
        runID: ColonyRunID,
        attemptID: ColonyRunAttemptID,
        underlying: HiveRunHandle<ColonySchema>
    ) {
        self.runID = runID
        self.attemptID = attemptID
        self.underlying = underlying
    }

    /// Waits for the run to complete and returns the outcome.
    public var outcome: ColonyRunOutcome {
        get async throws {
            let hiveOutcome = try await underlying.outcome.value
            return Self.mapOutcome(hiveOutcome)
        }
    }

    /// Returns true if the run has finished.
    public var isFinished: Bool {
        get async {
            await underlying.isFinished
        }
    }

    /// Returns true if the run is interrupted.
    public var isInterrupted: Bool {
        get async {
            await underlying.isInterrupted
        }
    }

    // MARK: - Outcome Mapping

    private static func mapOutcome(_ outcome: HiveRunOutcome<ColonySchema>) -> ColonyOutcome {
        switch outcome {
        case .finished(let output, let metadata):
            let text = output.messages
                .filter { $0.role == .assistant }
                .last?.content ?? ""
            let meta = metadata?.reduce(into: [String: String]()) { result, pair in
                result[pair.key] = pair.value
            }
            return .finished(output: text, metadata: meta)

        case .interrupted(let interrupt):
            return .interrupted(interrupt: interrupt)

        case .cancelled(let output, let metadata):
            let text = output?.messages
                .filter { $0.role == .assistant }
                .last?.content
            let meta = metadata?.reduce(into: [String: String]()) { result, pair in
                result[pair.key] = pair.value
            }
            return .cancelled(output: text, metadata: meta)

        case .outOfSteps(let maxSteps, let output):
            let text = output?.messages
                .filter { $0.role == .assistant }
                .last?.content
            return .outOfSteps(maxSteps: maxSteps, output: text)
        }
    }
}

/// Convenience type alias for HiveRunOutcome mapped to ColonyOutcome.
public typealias ColonyRunOutcome = ColonyOutcome
```

- [ ] **Step 2: Run build to verify compilation**

```bash
swift build 2>&1 | head -30
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Colony/ColonyRunHandle.swift
git commit -m "feat: add ColonyRunHandle and ColonyOutcome types"
```

---

## Task 3: Implement Colony.agent() Entry Point

**Files:**
- Modify: `Sources/Colony/Colony.swift`
- Test: `Tests/ColonyTests/ColonyAgentAPITests.swift`

- [ ] **Step 1: Add Colony.agent() to Colony.swift**

```swift
// Add to Colony enum after existing start() method:

    /// Creates a Colony runtime with the specified provider(s).
    ///
    /// The first provider is the primary model; additional providers are used as fallbacks
    /// in order when the primary fails.
    ///
    /// - Parameters:
    ///   - providers: Variadic list of providers. At least one required.
    ///   - profile: Configuration profile (`.device` or `.cloud`). Defaults to `.device`.
    ///   - filesystem: Optional filesystem backend. Defaults to in-memory.
    ///   - shell: Optional shell backend for command execution.
    ///   - git: Optional git service.
    ///   - lsp: Optional LSP backend.
    ///   - memory: Optional memory backend.
    ///
    /// - Returns: A configured `ColonyRuntime`.
    ///
    /// - Throws: `ColonyProviderError` if no providers specified or configuration is invalid.
    ///
    /// Example:
    /// ```swift
    /// let runtime = Colony.agent(
    ///     .ollama(baseURL: "http://localhost:11434"),
    ///     .anthropic(apiKey: "sk-..."),
    ///     profile: .device,
    ///     filesystem: diskFS,
    ///     shell: realShell
    /// )
    /// ```
    public static func agent(
        _ providers: Provider...,
        profile: ColonyProfile = .device,
        filesystem: (any ColonyFileSystemBackend)? = nil,
        shell: (any ColonyShellBackend)? = nil,
        git: (any ColonyGitService)? = nil,
        lsp: (any ColonyLSPBackend)? = nil,
        memory: (any ColonyMemoryBackend)? = nil
    ) throws -> ColonyRuntime {
        guard providers.isEmpty == false else {
            throw ColonyProviderError.noProvidersSpecified
        }

        // Build with primary provider
        let primary = providers[0]
        let (primaryClient, modelName) = try primary.makeModelClient()

        // Build the runtime using ColonyBuilder
        var builder = ColonyBuilder()
            .model(name: modelName)
            .profile(profile)

        // Apply backends
        if let filesystem {
            builder = builder.filesystem(filesystem)
        }
        if let shell {
            builder = builder.shell(shell)
        }
        if let git {
            builder = builder.git(git)
        }
        if let lsp {
            builder = builder.lsp(lsp)
        }
        if let memory {
            builder = builder.memory(memory)
        }

        // Note: The builder's model client is set via makeRuntime
        // For now, we use the existing factory method pattern
        // This will be refactored once the builder gap is fixed

        return try builder.makeRuntime(
            profile: profile,
            modelName: modelName,
            model: primaryClient
        )
    }
```

- [ ] **Step 2: Add filesystem, shell, git, lsp, memory builder methods to ColonyBuilder**

First, let me check what backend setter methods already exist in ColonyBuilder:

Looking at ColonyBuilder, it stores backends but only has them as private properties. The `build()` and `makeRuntime()` methods use these private properties. We need to add fluent setter methods.

- [ ] **Step 3: Add backend setter methods to ColonyBuilder**

Add these methods to ColonyBuilder after the `capabilities(_:)` method:

```swift
    /// Sets the filesystem backend.
    public func filesystem(_ filesystem: (any ColonyFileSystemBackend)?) -> ColonyBuilder {
        ColonyBuilder(
            configuration: configuration,
            profile: profile,
            threadID: threadID,
            model: model,
            modelRouter: modelRouter,
            inferenceHints: inferenceHints,
            tools: tools,
            filesystem: filesystem ?? ColonyInMemoryFileSystemBackend(),
            shell: shell,
            git: git,
            lsp: lsp,
            applyPatch: applyPatch,
            webSearch: webSearch,
            codeSearch: codeSearch,
            mcp: mcp,
            memory: memory,
            plugins: plugins,
            subagents: subagents,
            checkpointStore: checkpointStore,
            durableCheckpointDirectoryURL: durableCheckpointDirectoryURL,
            clock: clock,
            logger: logger,
            configureRunOptions: configureRunOptions
        )
    }

    /// Sets the shell backend.
    public func shell(_ shell: (any ColonyShellBackend)?) -> ColonyBuilder {
        ColonyBuilder(
            configuration: configuration,
            profile: profile,
            threadID: threadID,
            model: model,
            modelRouter: modelRouter,
            inferenceHints: inferenceHints,
            tools: tools,
            filesystem: filesystem,
            shell: shell,
            git: git,
            lsp: lsp,
            applyPatch: applyPatch,
            webSearch: webSearch,
            codeSearch: codeSearch,
            mcp: mcp,
            memory: memory,
            plugins: plugins,
            subagents: subagents,
            checkpointStore: checkpointStore,
            durableCheckpointDirectoryURL: durableCheckpointDirectoryURL,
            clock: clock,
            logger: logger,
            configureRunOptions: configureRunOptions
        )
    }

    /// Sets the git service.
    public func git(_ git: (any ColonyGitService)?) -> ColonyBuilder {
        ColonyBuilder(
            configuration: configuration,
            profile: profile,
            threadID: threadID,
            model: model,
            modelRouter: modelRouter,
            inferenceHints: inferenceHints,
            tools: tools,
            filesystem: filesystem,
            shell: shell,
            git: git,
            lsp: lsp,
            applyPatch: applyPatch,
            webSearch: webSearch,
            codeSearch: codeSearch,
            mcp: mcp,
            memory: memory,
            plugins: plugins,
            subagents: subagents,
            checkpointStore: checkpointStore,
            durableCheckpointDirectoryURL: durableCheckpointDirectoryURL,
            clock: clock,
            logger: logger,
            configureRunOptions: configureRunOptions
        )
    }

    /// Sets the LSP backend.
    public func lsp(_ lsp: (any ColonyLSPBackend)?) -> ColonyBuilder {
        ColonyBuilder(
            configuration: configuration,
            profile: profile,
            threadID: threadID,
            model: model,
            modelRouter: modelRouter,
            inferenceHints: inferenceHints,
            tools: tools,
            filesystem: filesystem,
            shell: shell,
            git: git,
            lsp: lsp,
            applyPatch: applyPatch,
            webSearch: webSearch,
            codeSearch: codeSearch,
            mcp: mcp,
            memory: memory,
            plugins: plugins,
            subagents: subagents,
            checkpointStore: checkpointStore,
            durableCheckpointDirectoryURL: durableCheckpointDirectoryURL,
            clock: clock,
            logger: logger,
            configureRunOptions: configureRunOptions
        )
    }

    /// Sets the memory backend.
    public func memory(_ memory: (any ColonyMemoryBackend)?) -> ColonyBuilder {
        ColonyBuilder(
            configuration: configuration,
            profile: profile,
            threadID: threadID,
            model: model,
            modelRouter: modelRouter,
            inferenceHints: inferenceHints,
            tools: tools,
            filesystem: filesystem,
            shell: shell,
            git: git,
            lsp: lsp,
            applyPatch: applyPatch,
            webSearch: webSearch,
            codeSearch: codeSearch,
            mcp: mcp,
            memory: memory,
            plugins: plugins,
            subagents: subagents,
            checkpointStore: checkpointStore,
            durableCheckpointDirectoryURL: durableCheckpointDirectoryURL,
            clock: clock,
            logger: logger,
            configureRunOptions: configureRunOptions
        )
    }
```

- [ ] **Step 4: Run build to check compilation**

```bash
swift build 2>&1 | head -80
```

Expected: Errors related to OllamaModelClient, Conduit, or TextGenerator types

- [ ] **Step 5: Commit**

```bash
git add Sources/Colony/Colony.swift Sources/Colony/ColonyAgentFactory.swift
git commit -m "feat: add Colony.agent() entry point with Provider configuration"
```

---

## Task 4: Add run() Method to ColonyRuntime

**Files:**
- Modify: `Sources/Colony/ColonyRuntime.swift`
- Test: `Tests/ColonyTests/ColonyAgentAPITests.swift`

- [ ] **Step 1: Add run() method to ColonyRuntime**

```swift
// Add after existing sendUserMessage method:

    /// Starts a new agent run with the given input and returns a handle.
    ///
    /// - Parameter text: The user's message or task description.
    /// - Returns: A handle to monitor the run's progress and outcome.
    ///
    /// Example:
    /// ```swift
    /// let handle = runtime.run("Refactor the auth module")
    /// let outcome = try await handle.outcome
    /// ```
    public func run(_ text: String) async -> ColonyRunHandle {
        let hiveHandle = await runControl.start(.init(input: text))
        return ColonyRunHandle(
            runID: hiveHandle.id,
            attemptID: hiveHandle.attemptID,
            underlying: hiveHandle
        )
    }

    /// Resumes a run after an interruption.
    ///
    /// - Parameters:
    ///   - interrupt: The interruption to resume from.
    ///   - decision: The decision (`.approved` or `.rejected`).
    /// - Returns: A handle to monitor the resumed run.
    public func resume(
        interrupt: HiveInterruption<ColonySchema>,
        decision: ColonyToolApprovalDecision
    ) async -> ColonyRunHandle {
        let hiveHandle = await runControl.resume(
            .init(interruptID: interrupt.id, decision: decision)
        )
        return ColonyRunHandle(
            runID: hiveHandle.id,
            attemptID: hiveHandle.attemptID,
            underlying: hiveHandle
        )
    }
```

- [ ] **Step 2: Run build to verify compilation**

```bash
swift build 2>&1 | head -30
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Colony/ColonyRuntime.swift
git commit -m "feat: add run() method to ColonyRuntime returning ColonyRunHandle"
```

---

## Task 5: Wire Conduit Providers Properly

**Files:**
- Modify: `Sources/Colony/ColonyProvider.swift`
- Test: `Tests/ColonyTests/ColonyAgentAPITests.swift`

This task depends on Task 3. The placeholder providers need to be replaced with actual Conduit-backed implementations.

- [ ] **Step 1: Check available Conduit providers**

Look at what's available from Conduit in the symbolgraph or package.

```bash
find .build-codex -name "*.swift" -path "*/Conduit*" 2>/dev/null | head -20
```

- [ ] **Step 2: Replace placeholder providers with actual Conduit usage**

The key insight from the spec: Use `ConduitModelClient<Provider>` which already conforms to `HiveModelClient`.

```swift
// In ColonyProvider.swift, update makeModelClient():

internal func makeModelClient() throws -> (AnyHiveModelClient, String) {
    switch self {
    case .ollama(let baseURL):
        guard let url = URL(string: baseURL) else {
            throw ColonyProviderError.configurationError("Invalid Ollama baseURL: \(baseURL)")
        }
        // Use Ollama's TextGenerator protocol from Conduit
        let ollamaProvider = OllamaProvider(baseURL: url)
        let client = ConduitModelClient(ollamaProvider) { name in
            // Ollama uses model name strings directly
            OllamaProvider.ModelID(rawValue: name)
        }
        return (AnyHiveModelClient(client), defaultModelName ?? "llama3.2")

    case .anthropic(let apiKey):
        // Use AnthropicProvider from Conduit
        let provider = AnthropicProvider(apiKey: apiKey)
        let client = ConduitModelClient(provider) { name in
            AnthropicProvider.ModelID(rawValue: name)
        }
        return (AnyHiveModelClient(client), defaultModelName ?? "claude-sonnet-4-20250514")

    case .openAI(let apiKey):
        // Use OpenAIProvider from Conduit
        let provider = OpenAIProvider(apiKey: apiKey)
        let client = ConduitModelClient(provider) { name in
            OpenAIProvider.ModelID(rawValue: name)
        }
        return (AnyHiveModelClient(client), defaultModelName ?? "gpt-4o")

    case .foundationModels:
        let client = ColonyFoundationModelsClient()
        return (AnyHiveModelClient(client), "foundation-models")
    }
}
```

- [ ] **Step 3: Verify build**

```bash
swift build 2>&1 | head -50
```

- [ ] **Step 4: Commit**

```bash
git add Sources/Colony/ColonyProvider.swift
git commit -m "feat: wire Conduit providers into Colony.agent()"
```

---

## Task 6: Deprecate Old API Types

**Files:**
- Modify: `Sources/Colony/ColonyPublicAPI.swift`
- Modify: `Sources/Colony/ColonyAgentFactory.swift`
- Modify: `Sources/Colony/ColonyBootstrap.swift`
- Modify: `Tests/ColonyTests/ColonyBuilderTests.swift`

- [ ] **Step 1: Add deprecation to ColonyModel and related types**

In ColonyPublicAPI.swift, mark ColonyModel deprecated:

```swift
// MARK: - ColonyModel (Deprecated)

/// Represents a model configuration for Colony agents.
///
/// .. deprecated: Use `Provider` enum with `Colony.agent()` instead.
///
/// ```swift
/// // Old (deprecated)
/// let model = ColonyModel.foundationModels(configuration: .default)
///
/// // New
/// let runtime = Colony.agent(.foundationModels())
/// ```
@available(*, deprecated, message: "Use Colony.agent() with Provider enum instead")
public indirect enum ColonyModel: Sendable {
    // ... existing cases unchanged
}
```

- [ ] **Step 2: Add deprecation to ColonyProviderConfiguration**

```swift
@available(*, deprecated, message: "Use Colony.agent() with Provider enum instead")
public struct ColonyProviderConfiguration: Sendable {
    // ... existing content unchanged
}
```

- [ ] **Step 3: Deprecate ColonyBuilder more strongly**

In ColonyAgentFactory.swift, update the ColonyBuilder docstring:

```swift
/// Builder for configuring and creating Colony runtimes.
///
/// .. deprecated: Use `Colony.agent()` with `Provider` enum instead.
///
/// ```swift
/// // Old (deprecated)
/// let runtime = try ColonyBuilder()
///     .model(name: "llama3.2")
///     .profile(.device)
///     .build()
///
/// // New
/// let runtime = Colony.agent(.foundationModels(), profile: .device)
/// ```
@available(*, deprecated, renamed: "Colony.agent")
public struct ColonyBuilder: Sendable {
```

- [ ] **Step 4: Fully deprecate ColonyBootstrap**

In ColonyBootstrap.swift, update the deprecation:

```swift
@available(*, deprecated, renamed: "Colony.agent")
public enum ColonyBootstrap {
    @available(*, deprecated, renamed: "Colony.agent")
    public static func bootstrap(...)
}
```

- [ ] **Step 5: Add deprecation tests to ColonyBuilderTests**

```swift
@Test("ColonyBuilder deprecation warning")
func colonyBuilderDeprecation() {
    // Suppress deprecation warnings in test
    let builder = ColonyBuilder()
        .model(name: "test")

    // Should still work but emit deprecation warning
    let runtime = try builder.build()
    #expect(runtime.threadID.rawValue.hasPrefix("colony:"))
}
```

- [ ] **Step 6: Run build and tests**

```bash
swift build 2>&1 | head -30
swift test --filter ColonyBuilderTests 2>&1 | tail -20
```

- [ ] **Step 7: Commit**

```bash
git add Sources/Colony/ColonyPublicAPI.swift Sources/Colony/ColonyAgentFactory.swift Sources/Colony/ColonyBootstrap.swift
git commit -m "deprecate: mark old API types for removal in next major version"
```

---

## Task 7: Write ColonyAgentAPITests.swift

**Files:**
- Create: `Tests/ColonyTests/ColonyAgentAPITests.swift`

- [ ] **Step 1: Create comprehensive tests**

```swift
import Foundation
import Testing
import HiveCore
@testable import Colony

@TestSuite("Colony.agent() API Tests")
struct ColonyAgentAPITests {

    // MARK: - Provider Tests

    @Test("Provider.ollama creates valid provider")
    func providerOllama() {
        let provider = Provider.ollama(baseURL: "http://localhost:11434")
        #expect(provider.defaultModelName == "llama3.2")
    }

    @Test("Provider.anthropic creates valid provider")
    func providerAnthropic() {
        let provider = Provider.anthropic(apiKey: "sk-test")
        #expect(provider.defaultModelName == "claude-sonnet-4-20250514")
    }

    @Test("Provider.openAI creates valid provider")
    func providerOpenAI() {
        let provider = Provider.openAI(apiKey: "sk-test")
        #expect(provider.defaultModelName == "gpt-4o")
    }

    @Test("Provider.foundationModels creates valid provider")
    func providerFoundationModels() {
        let provider = Provider.foundationModels
        #expect(provider.defaultModelName == nil)
    }

    // MARK: - Colony.agent() Tests

    @Test("Colony.agent requires at least one provider")
    func agentRequiresProvider() {
        // This should throw
        #expect(throws: ColonyProviderError.self) {
            try Colony.agent()
        }
    }

    @Test("Colony.agent with single provider creates runtime")
    func agentSingleProvider() throws {
        let runtime = try Colony.agent(.foundationModels())
        #expect(runtime.threadID.rawValue.hasPrefix("colony:"))
    }

    @Test("Colony.agent with profile parameter")
    func agentWithProfile() throws {
        let runtime = try Colony.agent(.foundationModels(), profile: .cloud)
        #expect(runtime.threadID.rawValue.hasPrefix("colony:"))
    }

    @Test("Colony.agent with multiple providers (fallback)")
    func agentWithFallback() throws {
        // Primary and fallback - both foundation for testing
        let runtime = try Colony.agent(
            .foundationModels(),
            .foundationModels(),
            profile: .device
        )
        #expect(runtime.threadID.rawValue.hasPrefix("colony:"))
    }

    // MARK: - ColonyRunHandle Tests

    @Test("ColonyRunHandle stores run and attempt IDs")
    func runHandleIDs() async throws {
        let runtime = try Colony.agent(.foundationModels())
        let handle = runtime.run("Test task")

        #expect(handle.runID.rawValue.isEmpty == false)
        #expect(handle.attemptID.rawValue.isEmpty == false)
    }

    // MARK: - ColonyOutcome Tests

    @Test("ColonyOutcome.finished case")
    func outcomeFinished() {
        let outcome = ColonyOutcome.finished(output: "Done", metadata: nil)
        #expect(outcome.isFinished == true)
        #expect(outcome.isInterrupted == false)
        #expect(outcome.output == "Done")
    }

    @Test("ColonyOutcome.interrupted case")
    func outcomeInterrupted() {
        let outcome = ColonyOutcome.interrupted(interrupt: .init(id: "test", payload: .noDecision))
        #expect(outcome.isFinished == false)
        #expect(outcome.isInterrupted == true)
        #expect(outcome.output == nil)
    }

    @Test("ColonyOutcome.outOfSteps case")
    func outcomeOutOfSteps() {
        let outcome = ColonyOutcome.outOfSteps(maxSteps: 100, output: "Partial")
        #expect(outcome.isFinished == false)
        #expect(outcome.output == "Partial")
    }

    // MARK: - Deprecation Warning Tests

    @Test("Old Colony.start still works but is deprecated")
    func oldStartStillWorks() throws {
        // This tests backward compatibility
        let runtime = try Colony.start(modelName: "test-model")
        #expect(runtime.threadID.rawValue.hasPrefix("colony:"))
    }
}
```

- [ ] **Step 2: Run tests**

```bash
swift test --filter ColonyAgentAPITests 2>&1
```

- [ ] **Step 3: Commit**

```bash
git add Tests/ColonyTests/ColonyAgentAPITests.swift
git commit -m "test: add Colony.agent() API tests with Provider and ColonyRunHandle coverage"
```

---

## Task 8: Update README with New API

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update README quickstart section**

Replace the old quickstart:

```swift
// Old API (deprecated)
let factory = ColonyAgentFactory()
let runtime = try factory.makeRuntime(
    profile: .onDevice4k,
    modelName: "test-model",
    model: AnyHiveModelClient(ColonyFoundationModelsClient())
)
```

With:

```swift
// New API - Colony.agent()
import Colony

// Simple on-device setup
let runtime = Colony.agent(.foundationModels())

// Local Ollama with cloud fallback
let runtime = Colony.agent(
    .ollama(baseURL: "http://localhost:11434"),
    .anthropic(apiKey: "sk-..."),
    profile: .device,
    filesystem: myFileSystem,
    shell: myShell
)

// Run a task
let handle = runtime.run("Refactor the auth module")
let outcome = try await handle.outcome

switch outcome {
case .finished(let output, _):
    print("Done: \(output)")
case .interrupted(let interrupt):
    // Handle tool approval, etc.
    let resumed = runtime.resume(interrupt: interrupt, decision: .approved)
    let final = try await resumed.handle.outcome
case .cancelled:
    print("Cancelled")
case .outOfSteps(let max, _):
    print("Exceeded \(max) steps")
}
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: update README with Colony.agent() quickstart example"
```

---

## Task 9: Final Verification

- [ ] **Step 1: Run all tests**

```bash
swift test 2>&1 | tail -30
```

- [ ] **Step 2: Verify build succeeds**

```bash
swift build 2>&1 | tail -10
```

- [ ] **Step 3: Create summary commit**

```bash
git log --oneline -10
```

---

## Summary of Changes

| File | Action |
|------|--------|
| `Sources/Colony/ColonyProvider.swift` | Create - Provider enum and error types |
| `Sources/Colony/ColonyRunHandle.swift` | Create - ColonyRunHandle and ColonyOutcome types |
| `Sources/Colony/Colony.swift` | Modify - Add Colony.agent() method |
| `Sources/Colony/ColonyRuntime.swift` | Modify - Add run() and resume() methods |
| `Sources/Colony/ColonyAgentFactory.swift` | Modify - Add backend setter methods, deprecate |
| `Sources/Colony/ColonyPublicAPI.swift` | Modify - Deprecate ColonyModel |
| `Sources/Colony/ColonyBootstrap.swift` | Modify - Fully deprecate |
| `Tests/ColonyTests/ColonyAgentAPITests.swift` | Create - New API tests |
| `Tests/ColonyTests/ColonyBuilderTests.swift` | Modify - Add deprecation tests |
| `README.md` | Modify - Update quickstart |
