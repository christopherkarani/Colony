# Colony Agent Setup API Redesign

**Date:** 2026-03-24
**Status:** Approved
**Author:** Claude

## Overview

Simplify the Colony agent setup API so coding agents can onboard in one intuitive call. Hide implementation types (`ColonyFoundationModelsClient`, `ConduitModelClient`, `HiveModelClient`), eliminate the deprecated fluent builder, and provide clean provider syntax with automatic fallback support.

---

## 1. Unified Entry Point

### Before (Problematic)

```swift
// Old API — confusing, gaps
let factory = ColonyAgentFactory()
let runtime = try factory.makeRuntime(
    profile: .onDevice4k,
    modelName: "test-model",
    model: AnyHiveModelClient(ColonyFoundationModelsClient())
)
```

Issues:
- `ColonyBuilder` (formerly `ColonyAgentFactory`) has `model(name: String)` but no way to set a client via fluent API
- Must use deprecated `makeRuntime()` to pass a `HiveModelClient`
- Implementation types leaked: `ColonyFoundationModelsClient`, `ConduitModelClient`, `HiveModelClient`
- Multiple entry points: `Colony.start()`, `ColonyBuilder`, `ColonyBootstrap`

### After (Clean)

```swift
let runtime: ColonyRuntime = Colony.agent(
    .ollama(baseURL: "http://localhost:11434"),
    .anthropic(apiKey: "sk-..."),
    profile: .device,
    filesystem: diskFS,
    shell: realShell
)
```

Benefits:
- Single entry point: `Colony.agent()`
- Variadic providers — first = primary, rest = fallbacks in order
- No implementation types exposed
- Labeled `profile:` for clarity
- Flat backend parameters with auto-enablement

---

## 2. Provider API

### Design Goals
- Hide implementation types (`ConduitModelClient`, `HiveModelClient`, etc.)
- User sees only provider names
- Natural Swift enum syntax

### Available Providers

| Provider | Syntax |
|----------|--------|
| Ollama | `.ollama(baseURL: String)` |
| Anthropic | `.anthropic(apiKey: String)` |
| OpenAI | `.openAI(apiKey: String)` |
| Foundation Models (Apple) | `.foundationModels()` |

### Examples

```swift
// Single local provider
Colony.agent(.ollama(baseURL: "http://localhost:11434"))

// Single cloud provider
Colony.agent(.anthropic(apiKey: "sk-..."))

// With fallback (first = primary, second = fallback)
Colony.agent(
    .ollama(baseURL: "http://localhost:11434"),
    .anthropic(apiKey: "sk-..."),
)

// Foundation Models (on-device Apple)
Colony.agent(.foundationModels())
```

### Implementation

All providers are `Provider` enum cases in `Colony` namespace. The enum is internal; only the case names are public.

---

## 3. Fallback Chain

### Design Decision
- Variadic providers: first = primary, rest = fallbacks in order
- If primary fails (network error, timeout, rate limit, non-recoverable inference error), next provider is tried
- Retryable errors: network timeout, 429 rate limit, 5xx server error
- Non-retryable errors: invalid API key, authentication failure — do NOT fall back
- Continues until success or all providers exhausted
- Error if all providers fail (aggregated error with reasons from each)

### Example

```swift
Colony.agent(
    .ollama(baseURL: "http://localhost:11434"),     // primary
    .anthropic(apiKey: "sk-..."),                   // fallback #1
    .openAI(apiKey: "sk-..."),                      // fallback #2
)
```

---

## 4. Profile Configuration

### Syntax

```swift
Colony.agent(.ollama(baseURL: "..."), profile: .device)
Colony.agent(.ollama(baseURL: "..."), profile: .cloud)
```

| Profile | Token Budget | Defaults |
|---------|-------------|----------|
| `.device` | ~4k | Scratchbook enabled, strict compaction |
| `.cloud` | Generous | No scratchbook, relaxed limits |

**Note:** `.device` replaces the legacy `.onDevice4k` name (deprecated, removed).

---

## 5. Backend Auto-enablement

### Design Decision
- Capabilities auto-enabled based on provided backends
- Sensible in-memory defaults if not provided

### Backend Parameters

```swift
Colony.agent(
    .ollama(baseURL: "..."),
    filesystem: diskFS,           // ColonyFileSystem.Service
    shell: realShell,             // ColonyShellBackend
    git: gitService,              // ColonyGitService
    lsp: lspBackend,              // ColonyLSPBackend
    memory: memoryService,        // ColonyMemoryService
    profile: .device
)
```

### Defaults (if not provided)

| Backend | Default |
|---------|---------|
| `filesystem` | `ColonyInMemoryFileSystemBackend()` |
| `shell` | `nil` (shell tools unavailable) |
| Other backends | `nil` |

### Auto-enablement Logic

If `filesystem` is provided, `.filesystem` capability is automatically enabled. If `shell` is provided, both `.shell` and `.shellSessions` capabilities are enabled.

---

## 6. Execution API

### Run and Handle Pattern

```swift
let handle = runtime.run("Refactor the auth module")
let outcome = try await handle.outcome
```

### Handle Type

```swift
struct ColonyRunHandle: Sendable {
    let runID: ColonyRunID
    let attemptID: ColonyRunAttemptID
    let outcome: ColonyOutcome
}
```

### Outcome Types

```swift
enum ColonyOutcome: Sendable {
    case finished(output: String, metadata: [String: String]?)
    case interrupted(interrupt: HiveInterruption<ColonySchema>)
    case cancelled(output: String?, metadata: [String: String]?)
    case outOfSteps(maxSteps: Int, output: String?)
}
```

### Interrupt Handling

```swift
if case let .interrupted(interrupt) = outcome {
    let resumed = runtime.resume(
        interrupt: interrupt,
        decision: .approved  // or .rejected
    )
    let final = try await resumed.handle.outcome
}
```

---

## 7. Return Type

`Colony.agent()` returns `ColonyRuntime` directly.

```swift
let runtime: ColonyRuntime = Colony.agent(.ollama(baseURL: "..."))
```

No new wrapper type needed — `ColonyRuntime` is the concrete type with all runtime methods.

---

## 8. Full Migration Path

### Before

```swift
import Colony

// Old API
let factory = ColonyAgentFactory()
let runtime = try factory.makeRuntime(
    profile: .onDevice4k,
    modelName: "test-model",
    model: AnyHiveModelClient(ColonyFoundationModelsClient())
)
```

### After

```swift
import Colony

// New API
let runtime = Colony.agent(.foundationModels(), profile: .device)

// Migration note: old `.onDevice4k` is now `.device`
```

---

## 9. Types to Remove / Rename

| Type | Status |
|------|--------|
| `ColonyBuilder` | Removed — replaced by `Colony.agent()` |
| `ColonyAgentFactory` | Removed — deprecated alias |
| `Colony.start()` | Removed — deprecated entry point |
| `ColonyBootstrap` | Removed — deprecated entry point |
| `makeRuntime()` | Removed — had the model client gap |
| `ColonyProfile.onDevice4k` | Renamed to `.device` |
| `ColonyProfile.cloud` | Unchanged |

---

## 10. Implementation Notes

### Provider Enum (Internal)

```swift
enum Provider: Sendable {
    case ollama(baseURL: String)
    case anthropic(apiKey: String)
    case openAI(apiKey: String)
    case foundationModels
}
```

### Colony.agent() Signature

```swift
public func agent(
    _ providers: Provider...,
    profile: ColonyProfile = .device,
    filesystem: (any ColonyFileSystemBackend)? = nil,
    shell: (any ColonyShellBackend)? = nil,
    git: (any ColonyGitService)? = nil,
    lsp: (any ColonyLSPBackend)? = nil,
    memory: (any ColonyMemoryBackend)? = nil
) -> ColonyRuntime
```

### Conformance to HiveModelClient

Each `Provider` case maps to a `HiveModelClient` internally:
- `.ollama` → `ConduitModelClient<OllamaProvider>`
- `.anthropic` → `ConduitModelClient<AnthropicProvider>`
- `.openAI` → `ConduitModelClient<OpenAIProvider>`
- `.foundationModels` → `ColonyFoundationModelsClient`

---

## 11. Open Questions / Future Considerations

- [ ] Add more providers (Gemini, Azure OpenAI, etc.)
- [ ] Support provider-specific configuration (temperature, maxTokens, etc.)
- [ ] Connection pooling for high-throughput scenarios
- [ ] Provider health checks and automatic failover

---

## 12. Approval

Approved by: User
Date: 2026-03-24
