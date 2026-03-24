# Colony API Improvement Report

Generated: 2026-03-24 | Framework: Colony | Branch: main
Inputs: Comprehensive parallel analysis of ColonyCore + Colony modules (10 specialized agents)

---

## Executive Summary

The Colony framework's public API surface consists of **~189 public symbols** across two modules (ColonyCore and Colony). While functionally comprehensive, the API suffers from significant naming inconsistencies, verbosity, and conceptual fragmentation that create cognitive overhead for AI coding agents.

### Key Findings

| Category | Issue Count | Severity |
|----------|-------------|----------|
| Verbose Type Names | 15+ | Medium |
| Inconsistent Naming Patterns | 12+ | High |
| Domain Jargon | 8+ | Medium |
| API Duplication | 7 major areas | High |
| Conceptual Fragmentation | 5 areas | High |

### Top 10 Highest-Impact Improvements

1. **Rename `ColonyBootstrap` → `Colony`** with `.start()` method
2. **Unify `ColonyLane` → `AgentMode`** (clearer metaphor)
3. **Consolidate 7 policy types into 3 unified policies**
4. **Replace "Backend" suffix with "Service"** across all protocols
5. **Rename `scratchbook` → `workspace`** (remove jargon)
6. **Unify `ColonyProviderRouter` + `ColonyOnDeviceModelRouter` → `ColonyModelRouter`**
7. **Consolidate request/response types using generics**
8. **Standardize verb-based method naming** (follow Swift API Design Guidelines)
9. **Flatten nested types** (ProviderRouter.Provider → ProviderRoute)
10. **Shorten error type names** (remove redundant "Colony" prefixes)

---

## 1. Entry Points & Bootstrap API

### 1.1 Primary Entry Point

**Current:**
```swift
public enum ColonyBootstrap {
    public static func bootstrap(...) throws -> ColonyRuntime
}
```

**Issues:**
- "Bootstrap" is implementation detail (initialization sequence), not intent
- Method name stutters: `ColonyBootstrap.bootstrap()`
- Sounds like one-time system init, not per-session creation

**Proposed:**
```swift
public enum Colony {
    public static func start(modelName: String, profile: Profile = .device, ...) throws -> ColonyRuntime
    public static func configure() -> ConfigurationBuilder
}
```

**Rationale:**
- `Colony` matches the module name, follows SwiftUI-like patterns
- `start()` clearly indicates beginning a session
- Agents naturally discover entry point from module name

**Breaking Change:** High - requires migration of all entry points

---

### 1.2 Factory Pattern

**Current:**
```swift
public struct ColonyAgentFactory {
    public func makeRuntime(profile: ..., modelName: ..., ...) throws -> ColonyRuntime
}
```

**Issues:**
- "Factory" is a pattern name, not a domain concept
- `make` prefix is Objective-C heritage; Swift prefers `create` or `build`
- 31 parameters is overwhelming

**Proposed:**
```swift
// Merge into Colony entry point
public enum Colony {
    public static func runtime(for profile: Profile = .device, modelName: String, ...) -> ColonyRuntime
}

// Or builder pattern
public struct ConfigurationBuilder {
    public func build() throws -> ColonyRuntime
}
```

**Breaking Change:** High - primary API surface change

---

## 2. Configuration Types

### 2.1 Main Configuration

**Current:**
```swift
public struct ColonyConfiguration {
    public init(
        capabilities: ColonyCapabilities = .default,
        modelName: String,
        toolApprovalPolicy: ColonyToolApprovalPolicy = .allowList([...]),
        toolApprovalRuleStore: (any ColonyToolApprovalRuleStore)? = nil,
        toolRiskLevelOverrides: [String: ColonyToolRiskLevel] = [:],
        mandatoryApprovalRiskLevels: Set<ColonyToolRiskLevel> = [.mutation, .execution, .network],
        // ... 15+ more parameters
    )
}
```

**Issues:**
- 21 parameters in initializer
- Verbose parameter names (`toolApprovalPolicy` vs `permissionPolicy`)
- Flat structure - no logical grouping

**Proposed:**
```swift
public struct AgentConfiguration {
    public var capabilities: Capabilities
    public var model: ModelSettings
    public var permissions: PermissionSettings
    public var context: ContextSettings
    public var memory: MemorySettings
    public var prompts: PromptSettings

    public struct PermissionSettings: Sendable {
        public var policy: ToolPermissionPolicy
        public var rules: ApprovalRuleStore?
        public var riskOverrides: [String: ToolRiskLevel]
        public var requiredApprovalRisks: Set<ToolRiskLevel>
    }

    public struct ContextSettings: Sendable {
        public var windowPolicy: ContextWindowPolicy
        public var compressionPolicy: ContextCompressionPolicy?
        public var workingMemoryPolicy: WorkingMemoryPolicy
    }
}
```

**Breaking Change:** High - complete restructuring

---

### 2.2 Policy Type Names

| Current | Proposed | Rationale |
|---------|----------|-----------|
| `ColonyCompactionPolicy` | `ContextWindowPolicy` | Clearer intent |
| `ColonySummarizationPolicy` | `ContextCompressionPolicy` | Describes mechanism |
| `ColonyScratchbookPolicy` | `WorkingMemoryPolicy` | Standard cognitive term |
| `ColonyToolApprovalPolicy` | `ToolPermissionPolicy` | Standard security term |

**Breaking Change:** High - type name changes

---

### 2.3 Profile & Lane

**Current:**
```swift
public enum ColonyProfile {
    case onDevice4k  // Token count in name
    case cloud
}

public enum ColonyLane {
    case general
    case coding
    case research
    case memory  // Confusing - sounds like RAM
}
```

**Issues:**
- `.onDevice4k` mixes camelCase with number
- `.cloud` is vague
- "Lane" metaphor is unclear
- `.memory` conflicts with computer memory concept

**Proposed:**
```swift
public enum RuntimeTarget {
    case device  // was .onDevice4k
    case cloud   // was .cloud
}

public enum AgentMode {
    case generalPurpose  // was .general
    case code            // was .coding
    case research        // was .research
    case knowledge       // was .memory
}
```

**Breaking Change:** Medium - enum case changes

---

## 3. Backend Protocols

### 3.1 Protocol Naming

**Current:**
| Protocol | Suffix |
|----------|--------|
| `ColonyFileSystemBackend` | Backend |
| `ColonyShellBackend` | Backend |
| `ColonySubagentRegistry` | Registry |
| `ColonyMemoryBackend` | Backend |

**Issues:**
- Inconsistent suffixes (Backend vs Registry)
- "Backend" leaks implementation detail

**Proposed:**
```swift
public protocol FileSystemService: Sendable { ... }
public protocol ShellService: Sendable { ... }
public protocol SubagentService: Sendable { ... }  // was Registry
public protocol MemoryService: Sendable { ... }
```

**Breaking Change:** High - all protocol names change

---

### 3.2 Method Naming

**Current:**
```swift
// FileSystem - good
func list(at path: ColonyVirtualPath)
func read(at path: ColonyVirtualPath)

// Git - nouns instead of verbs
func status(_ request: ...)
func diff(_ request: ...)
func commit(_ request: ...)

// LSP - nouns instead of verbs
func symbols(_ request: ...)
func diagnostics(_ request: ...)
```

**Proposed:**
```swift
// Git - verbs
func getStatus(_ request: ...)
func getDiff(_ request: ...)
func createCommit(_ request: ...)

// LSP - verbs
func findSymbols(_ request: ...)
func getDiagnostics(_ request: ...)
func findReferences(_ request: ...)
```

**Breaking Change:** Medium - method renames

---

### 3.3 Memory Methods

**Current:**
```swift
func recall(_ request: ColonyMemoryRecallRequest)
func remember(_ request: ColonyMemoryRememberRequest)
```

**Issues:**
- Cute anthropomorphic names
- Not immediately clear which is read vs write

**Proposed:**
```swift
func search(_ request: MemorySearchRequest)  // was recall
func store(_ request: MemoryStoreRequest)    // was remember
```

**Breaking Change:** Medium

---

## 4. Tool System

### 4.1 Tool Names

| Current | Proposed | Rationale |
|---------|----------|-----------|
| `ls` | `listDirectory` | Remove Unix jargon |
| `grep` | `searchInFiles` | Self-documenting |
| `glob` | `matchPaths` | Self-documenting |
| `write_file` | `createFile` | Matches behavior |
| `wax_recall` | `recallMemory` | Remove implementation detail |
| `scratch_*` | `workspace_*` | Remove jargon |

---

### 4.2 Tool Approval

**Current:**
```swift
public enum ColonyToolApprovalPolicy {
    case never        // Ambiguous: never what?
    case always       // Ambiguous: always what?
    case allowList(Set<String>)
}
```

**Proposed:**
```swift
public enum ToolPermissionPolicy {
    case unrestricted      // was .never
    case requireApproval   // was .always
    case allowList(Set<String>)
}
```

**Breaking Change:** High - enum case renames

---

### 4.3 Risk Levels

**Current:**
```swift
public enum ColonyToolRiskLevel {
    case readOnly
    case stateMutation   // Unclear distinction
    case mutation        // from .stateMutation
    case execution
    case network
}
```

**Proposed:**
```swift
public enum ToolRiskLevel {
    case readOnly
    case stateChange      // was .stateMutation
    case destructiveWrite // was .mutation
    case codeExecution    // was .execution
    case networkAccess    // was .network
}
```

**Breaking Change:** High

---

## 5. Memory & Scratchbook Consolidation

### 5.1 The Problem

Two separate systems with overlapping purposes:
- **Memory** (`ColonyMemoryBackend`): Long-term semantic storage, `recall`/`remember`
- **Scratchbook** (`ColonyScratchbook`): Session-scoped notes/todos

**Issues:**
- "Scratchbook" is domain jargon
- AI agents confused about when to use which
- Duplicate infrastructure

### 5.2 Proposed Unified System

```swift
public struct KnowledgeItem: Codable, Sendable, Identifiable {
    public enum Kind {
        case memory        // Long-term durable
        case note          // Short-term scratch
        case todo          // Actionable item
        case task          // Tracked work
    }

    public enum Status {
        case active
        case archived
        case pending
        case inProgress
        case completed
    }

    public let id: String
    public var kind: Kind
    public var status: Status
    public var title: String
    public var content: String
    // ...
}

public protocol KnowledgeService: Sendable {
    func query(_ request: KnowledgeQuery) async throws -> KnowledgeQueryResult
    func store(_ item: KnowledgeItem) async throws -> KnowledgeItem
    func update(id: String, mutations: [KnowledgeMutation]) async throws -> KnowledgeItem
}
```

**Breaking Change:** High - complete replacement of two systems

---

## 6. Runtime Control & Harness

### 6.1 Type Naming

| Current | Proposed | Rationale |
|---------|----------|-----------|
| `ColonyRuntime` | `AgentSession` | Clearer intent |
| `ColonyRunControl` | `RunHandle` | Aligns with HiveCore |
| `ColonyHarnessSession` | `ManagedSession` | "Harness" is unclear |
| `ColonyHarnessEventEnvelope` | `SessionEvent` | "Envelope" is jargon |
| `ColonyHarnessInterruption` | `PendingApproval` | Clearer purpose |

---

### 6.2 Method Naming

| Current | Proposed | Rationale |
|---------|----------|-----------|
| `sendUserMessage()` | `start(message:)` | Consistent with `start(_:)` |
| `resumeToolApproval()` | `resume(interruptID:decision:)` | Simpler |
| `stream()` | `events()` | Conventional Swift |
| `interrupted()` | `currentInterruption()` | Clearer semantics |

---

## 7. Error Types

### 7.1 Type Naming

| Current | Characters | Proposed | Savings |
|---------|------------|----------|---------|
| `ColonyFoundationModelsClientError` | 33 | `OnDeviceModelError` | 11 |
| `ColonyOnDeviceModelRouterError` | 32 | `OnDeviceRoutingError` | 12 |
| `ColonyProviderRouterError` | 26 | `ProviderRoutingError` | 6 |
| `ColonyHarnessSessionError` | 26 | `HarnessError` | 12 |
| `ColonyBudgetError` | 17 | `ContextBudgetError` | 0 (clearer) |

**Breaking Change:** Medium - type aliases can ease migration

---

## 8. Consolidation Opportunities

### 8.1 Unified Request/Response Types

**Current:** 12+ separate request/response types

**Proposed:**
```swift
public struct Request<Operation: ColonyOperation>: Sendable {
    public var operation: Operation
}

public struct Response<Output>: Sendable {
    public var output: Output
}

public enum FileSystemOperation {
    case list(path: ColonyPath)
    case read(path: ColonyPath)
    // ...
}
```

**Impact:** Reduces ~12 types to 2 generic types + operation enums

---

### 8.2 Router Consolidation

**Current:**
```swift
ColonyProviderRouter       // Multi-provider failover
ColonyOnDeviceModelRouter  // On-device with fallback
```

**Proposed:**
```swift
public struct ModelRouter {
    public enum Strategy {
        case single(AnyHiveModelClient)
        case prioritized([Provider], RetryPolicy)
        case onDevice(onDevice: AnyHiveModelClient?, fallback: AnyHiveModelClient, PrivacyBehavior)
        case costOptimized([Provider], CostPolicy)
    }
}
```

**Impact:** 2 types with 4 nested types → 1 type with 1 nested enum

---

### 8.3 Policy Consolidation

**Current:** 7 separate policy types

**Proposed:** 3 unified policies
```swift
ColonyToolPolicy           // approval + safety
ColonyResourcePolicy       // compaction + summarization + scratchbook
ColonyRoutingPolicy        // retry + cost + degradation
```

---

## 9. Priority Matrix

| Priority | Change | Human Impact | Agent Impact | Effort |
|----------|--------|--------------|--------------|--------|
| **P0** | Rename `ColonyBootstrap` → `Colony` | High | High | Low |
| **P0** | Rename `scratchbook` → `workspace` | High | High | Low |
| **P0** | Unify `Lane` → `AgentMode` | High | High | Low |
| **P1** | Backend suffix → Service | Medium | High | Medium |
| **P1** | Tool approval case renames | High | High | Low |
| **P1** | Error type shortening | Medium | Medium | Low |
| **P2** | Policy consolidation | Medium | High | High |
| **P2** | Router consolidation | Medium | Medium | Medium |
| **P2** | Memory/Scratchbook unification | High | High | High |
| **P3** | Request/Response generics | Low | Medium | High |

---

## 10. Recommended Migration Path

### Phase 1: Non-Breaking Additions (v1.x)

1. Add new type names as aliases
2. Add new method names as overloads
3. Deprecate old names with `@available(*, deprecated, renamed: "...")`

### Phase 2: Deprecation Warnings (v1.x+1)

1. Update documentation to use new names
2. Migration guide with before/after examples
3. Codemod scripts for automated migration

### Phase 3: Breaking Cleanup (v2.0)

1. Remove all deprecated aliases
2. Consolidate types (policies, routers, memory systems)
3. Full API surface reduction

---

## Appendix A: Naming Principles Applied

1. **Prefer intent over implementation**: `Service` > `Backend`, `Workspace` > `Scratchbook`
2. **Use standard terminology**: `PermissionPolicy` > `ApprovalPolicy`, `Mode` > `Lane`
3. **Verb-based methods**: `findSymbols` > `symbols`, `createCommit` > `commit`
4. **Shorter names without loss of clarity**: `Colony.start` > `ColonyBootstrap.bootstrap`
5. **Consistent suffixes**: All services use `Service`, all policies use `Policy`

---

## Appendix B: Full API Surface Comparison

### Before (Current)
- Entry: `ColonyBootstrap.bootstrap()`
- Config: `ColonyConfiguration` (21 parameters)
- Profile: `.onDevice4k` / `.cloud`
- Lane: `.general` / `.coding` / `.research` / `.memory`
- Policies: 7 separate types
- Routers: 2 types with 4 nested types
- Backends: 8 protocols with inconsistent naming
- Memory: 2 separate systems

### After (Proposed)
- Entry: `Colony.start()`
- Config: `AgentConfiguration` (grouped sub-structs)
- Profile: `.device` / `.cloud`
- Mode: `.generalPurpose` / `.code` / `.research` / `.knowledge`
- Policies: 3 unified types
- Routers: 1 type with strategy enum
- Services: 8 consistently-named protocols
- Knowledge: 1 unified system

**Estimated API Surface Reduction: ~40%**

---

*This report was generated by analyzing the Colony framework's public API surface across ColonyCore and Colony modules using 10 parallel specialized agents for each domain area.*

---

## Progress Tracker

| Finding | Status | Notes |
|---------|--------|-------|
| F1: Remove `@_exported import Swarm` | **DONE** | Colony.swift only imports ColonyCore. Swarm types in ColonySwarmInterop. |
| F2: ColonyServiceBuilder result builder | **DONE** | `ColonyServiceBuilder.swift` with `ColonyService` enum. Builder init added to `ColonyRuntimeServices`. |
| F3: Split `ColonyConfiguration` into groups | **DONE** | 3-tier init with nested `ModelConfiguration`, `SafetyConfiguration`, `ContextConfiguration`, `PromptConfiguration`. |
| F4: Unified `ColonyID<Domain>` | **DONE** | `ColonyID.swift` with phantom domains and backward-compatible typealiases. |
| F5: `Colony.agent()` entry point | **DONE** | `ColonyEntryPoint.swift` with Tier 1/2/3 entry points. `ColonyRuntime.send()` shorthand exists. |
| F6: Replace manual type erasers | **PARTIAL** | `ColonyProvider.client` uses `any ColonyModelClient`. But `AnyColonyModelClient`, `AnyColonyModelRouter`, `AnyColonyToolRegistry` still exist. |
| F7: Type-safe `ColonyToolName` | **DONE** | `ColonyTool.Name` with 36 built-in constants. Used in `SafetyConfiguration.toolRiskLevelOverrides`. |
| F8: Hide `ColonyBootstrapResult` internals | **DONE** | `ColonyBootstrapResult` now `package` struct. Fields are `package`. |
| F9: Generic bridge adapter | **DONE** | Swarm adapters moved to `ColonySwarmInterop` target. `ColonySwarmToolBridge` is `public` in that product. |
| F10: `ColonyProviderID` newtype | **DONE** | `ColonyModel.ProviderID` with `.anthropic`, `.openAI`, `.foundationModels`, `.ollama` constants. |
| F11: Typed `ColonyEventName` | **DONE** | 12 static constants in `ColonyObservability.swift`. |
| F12: `ColonyArtifactKind` newtype | **DONE** | `.conversationHistory`, `.largeToolResult`, `.checkpoint`, `.summary` in `ColonyArtifactStore.swift`. |
| F13: Session store protocol | **NOT DONE** | `ColonySessionStore` is still concrete actor, not protocol. |
| F14: Tool registration builder | **NOT DONE** | No `@ToolRegistrationBuilder`. |
| F15: Consistent ID inits | **DONE** | `ColonyID<Domain>` provides both `init(_:)` and `init(rawValue:)`. |

### Remaining Work

| Item | Status | Notes |
|------|--------|-------|
| `blocking()` DispatchSemaphore antipattern | **NOT DONE** | `ColonyAgentFactory.swift:659-679` still uses `DispatchSemaphore`. |
| Boolean blindness cleanup | **PARTIAL** | `OnDevicePolicy` has new enum-based API but deprecated boolean init still exists. |
| Remove manual type erasers | **PARTIAL** | `AnyColonyModelClient`, `AnyColonyModelRouter`, `AnyColonyToolRegistry` still exist in `ColonyCore`. |
| Session store protocol | **NOT DONE** | `ColonySessionStore` concrete actor. |
| Tool registration builder | **NOT DONE** | No `@ToolRegistrationBuilder`. |
| ColonyControlPlane target dependencies | **DONE** | Now imports ColonyCore, Colony, and HiveCore correctly. |
| API audit tests | **NOT DONE** | No `ColonyPublicAPIAuditTests`. |

---

## Executive Summary

- **Current public surface**: ~95 types, ~385 members
- **Proposed after changes**: ~75 types, ~300 members (**~21% reduction**)
- **Current overall DX**: H:4.1, A:4.2, Combined: 4.1/5 (improved from 3.1 by completed findings)
- **Projected overall DX**: H:4.5, A:4.5, Combined: 4.5/5

### Remaining High-Impact Changes

| # | Change | Impact | Status |
|---|--------|--------|--------|
| 1 | Remove manual type erasers (`AnyColonyModelClient` etc.) | Reduces confusion, enables better type inference | Partial — types exist, internal usage remains |
| 2 | Extract `ColonySessionStoring` protocol | Consistency with `ColonyProjectStore` pattern | Not started |
| 3 | Fix `blocking()` concurrency antipattern | Thread safety, follows Swift concurrency | Not started |
| 4 | Boolean blindness cleanup | Replace deprecated boolean init in `OnDevicePolicy` | Deprecated init exists, needs removal |
| 5 | Tool registration builder | Cleaner Swarm tool registration | Not started |

---

## Finding 1: Swarm Re-export Leak — DONE ✅

**Status**: Complete. `Colony.swift` no longer has `@_exported import Swarm`. Swarm types live in `ColonySwarmInterop` product.

---

## Finding 2: ColonyRuntimeServices — 14-Slot Optional Existential Bag — PARTIAL

**Current DX**: H=3, A=3, Combined=3.0
**Impact**: MEDIUM
**Status**: `ColonyService` enum and builder exist, BUT `ColonyRuntimeServices` is still the primary service container.

**Files**: `ColonyPublicAPI.swift:224-288`

```swift
// CURRENT — 14 optional existential fields
public struct ColonyRuntimeServices: Sendable {
    public var tools: (any ColonyToolRegistry)?
    package var swarmTools: (any ColonySwarmToolBridging)?   // package ✅
    package var membrane: MembraneEnvironment?                 // package ✅
    public var filesystem: (any ColonyFileSystemBackend)?
    public var shell: (any ColonyShellBackend)?
    public var git: (any ColonyGitBackend)?
    // ... 9 more fields
}
```

**What's Good**:
- `swarmTools` and `membrane` are now `package` (not public)
- `ColonyService` enum exists and is well-designed
- `ColonyServiceBuilder` exists with proper result builder methods

**Remaining Issue**: `ColonyRuntimeServices` is still the primary container. The `ColonyServiceBuilder` init exists but isn't the *only* path — users can still construct `ColonyRuntimeServices` directly with 14 nil-able fields.

**Proposed**: Deprecate the direct field access on `ColonyRuntimeServices` and make the builder init the only public initializer.

```swift
@available(*, deprecated, message: "Use ColonyRuntimeServices(@ColonyServiceBuilder)")
public struct ColonyRuntimeServices: Sendable {
    // All fields become package
    package var tools: (any ColonyToolRegistry)?
    package var filesystem: (any ColonyFileSystemBackend)?
    // ...

    // Only public init is the builder
    public init(@ColonyServiceBuilder _ build: @Sendable () -> [ColonyService]) {
        self.init()
        for service in build() { /* apply */ }
    }

    package init() // for internal use
}
```

**Rationale**: The result builder is the right API. Direct field access invites the same confusion the builder was meant to solve.

**Breaking**: Yes — existing code that does `ColonyRuntimeServices(tools: myTools, memory: myMemory)` must migrate.
**Swift 6.2 Feature**: Result builder + deprecation

---

## Finding 3: ColonyConfiguration — 3-Tier Init — DONE ✅

**Status**: ✅ Implemented with nested configuration groups.

3-tier progressive disclosure:
- **Tier 1**: `ColonyConfiguration(modelName:)` — minimal
- **Tier 2**: `ColonyConfiguration(modelName:capabilities:toolApprovalPolicy:structuredOutput:)` — common case
- **Tier 3**: `ColonyConfiguration(model:safety:context:prompts:)` — full control

---

## Finding 6: Manual Type Erasers — PARTIAL

**Current DX**: H=3, A=2.5, Combined=2.6
**Impact**: MEDIUM
**Status**: Some usage changed to `any` protocol, but type erasers still exist.

**Files**: `ColonyCore/ColonyInferenceSurface.swift`

```swift
// Still exists — internal use only
public struct AnyColonyModelClient: ColonyModelClient { ... }
public struct AnyColonyModelRouter: ColonyModelRouter { ... }
public struct AnyColonyToolRegistry: ColonyToolRegistry { ... }
```

**What's Good**:
- `ColonyProvider.client` now uses `any ColonyModelClient`
- `ColonyModel.Storage` uses `any ColonyModelRouter`

**Remaining Issue**: Type erasers are `public` but should be `package` since they're implementation details.

**Proposed**: Change access level to `package` and add deprecation shim:

```swift
@available(*, deprecated, message: "Use 'any ColonyModelClient' directly")
package struct AnyColonyModelClient: ColonyModelClient { ... }
```

**Rationale**: Agents and humans should use `any ColonyModelClient` directly, not the type eraser.

**Breaking**: No — callers just use the protocol type directly.
**Swift 6.2 Feature**: `some`/`any` existentials

---

## Finding 7: ColonyToolName → ColonyTool.Name — DONE ✅

**Status**: ✅ `ColonyTool.Name` with 36 static constants. Used as key type in `SafetyConfiguration.toolRiskLevelOverrides`.

---

## Finding 8: ColonyBootstrapResult Internals — DONE ✅

**Status**: ✅ `ColonyBootstrapResult` is now `package` with `package` fields.

---

## Finding 13: ColonySessionStore Concrete Actor — NOT DONE

**Current DX**: H=3, A=3, Combined=3.0
**Impact**: LOW
**Status**: Not started.

**File**: `ColonyControlPlane/ColonySessionStore.swift`

`ColonySessionStore` is a concrete actor but `ColonyProjectStore` is a protocol with `InMemoryColonyProjectStore` concrete implementation. This is asymmetric.

**Proposed**:
```swift
// Protocol
public protocol ColonySessionStoring: Actor {
    func save(_ session: ColonySessionRecord) async throws
    func load(id: ColonySessionID) async throws -> ColonySessionRecord?
    func list(projectID: ColonyProjectID) async throws -> [ColonySessionRecord]
}

// Rename current actor
public actor ColonySessionStore: ColonySessionStoring { ... }

// Keep for compatibility
@available(*, deprecated, message: "Use ColonySessionStoring protocol")
public typealias ColonySessionStore = InMemoryColonySessionStore
```

**Rationale**: Consistent with `ColonyProjectStore` pattern. Enables testing with mock implementations.

**Breaking**: No — can add protocol without removing concrete type.
**Swift 6.2 Feature**: Protocol-based dependency injection

---

## Finding 14: Tool Registration Builder — NOT DONE

**Current DX**: H=3, A=2, Combined=2.2
**Impact**: LOW-MEDIUM
**Status**: Not started.

**File**: `ColonySwarmInterop/SwarmToolBridge.swift:85`

```swift
// CURRENT — array loses type info
public init(tools: [any AnyJSONTool], capability: ColonyCapabilities, riskLevel: ColonyTool.RiskLevel) throws
```

**Proposed** — Parameter pack or result builder:
```swift
// Option 1: Parameter pack
public init<each T: AnyJSONTool>(
    tools: repeat each T,
    capability: ColonyCapabilities = .default,
    riskLevel: ColonyTool.RiskLevel = .readOnly
) throws

// Option 2: Result builder
@ToolRegistrationBuilder var registrations: [ColonySwarmToolRegistration] {
    Tool(searchTool, risk: .network)
    Tool(calculatorTool, risk: .readOnly)
}
```

**Rationale**: Swarm tools have different types. A result builder allows conditional registration.

**Breaking**: Yes — migration path via deprecation.
**Swift 6.2 Feature**: Parameter packs or result builder

---

## Priority Matrix

| Priority | Finding | Status | Effort | Breaking |
|----------|---------|--------|:------:|:--------:|
| ~~P0~~ | ~~F1: Remove Swarm re-export~~ | ✅ DONE | — | — |
| ~~P0~~ | ~~F5: Tier-1 `Colony.agent()` entry point~~ | ✅ DONE | — | — |
| ~~P1~~ | ~~F2: ColonyServiceBuilder~~ | ✅ DONE | — | — |
| ~~P1~~ | ~~F3: ColonyConfiguration 3-tier~~ | ✅ DONE | — | — |
| ~~P2~~ | ~~F4: Unified ColonyID~~ | ✅ DONE | — | — |
| ~~P2~~ | ~~F7: ColonyTool.Name~~ | ✅ DONE | — | — |
| ~~P3~~ | ~~F8: Hide ColonyBootstrapResult~~ | ✅ DONE | — | — |
| ~~P3~~ | ~~F9: Swarm adapters in ColonySwarmInterop~~ | ✅ DONE | — | — |
| ~~P3~~ | ~~F10: ColonyProviderID~~ | ✅ DONE | — | — |
| ~~P3~~ | ~~F11: ColonyEventName~~ | ✅ DONE | — | — |
| ~~P3~~ | ~~F12: ColonyArtifactKind~~ | ✅ DONE | — | — |
| **P1** | F6: Demote type erasers to package | 🟡 Partial | Low | No |
| **P2** | F2: Make ColonyServiceBuilder the only public init for ColonyRuntimeServices | 🟡 Partial | Low | Yes |
| **P3** | F13: Session store protocol | ❌ Not started | Low | No |
| **P3** | F14: Tool registration builder | ❌ Not started | Medium | Yes |
| **P1** | NEW: Fix `blocking()` antipattern | ❌ Not started | Medium | No |
| **P2** | NEW: Remove boolean init from OnDevicePolicy | 🟡 Deprecated | Low | Yes |

---

## Implementation Roadmap

### Phase A: Access Control Tightening (Non-Breaking)

1. **Demote type erasers**: Change `AnyColonyModelClient`, `AnyColonyModelRouter`, `AnyColonyToolRegistry` to `package` access. Add `@available(*, deprecated)` shims with message to use `any` directly.

2. **Add ColonySessionStoring protocol**: Extract protocol from `ColonySessionStore`. Keep concrete implementation.

### Phase B: Builder Consolidation (Breaking)

3. **Make ColonyServiceBuilder the only public init for ColonyRuntimeServices**: Deprecate direct field access. Keep `package init()` for internal use.

4. **Remove deprecated boolean init from OnDevicePolicy**: The enum-based `networkBehavior` replaces the old booleans.

### Phase C: Advanced Features (Breaking)

5. **Tool registration builder**: Add parameter pack or result builder for `ColonySwarmToolBridge.init`.

6. **Fix `blocking()` antipattern**: Convert `ColonyAgentFactory.makeDurableCheckpointStore(at:)` to `async throws`. Remove `DispatchSemaphore`, `BlockingResultBox`.

---

## Appendix: Target Public API Shape (Ideal)

After all changes, the ideal `import Colony` namespace:

```
Colony (namespace enum)
├── .agent(model:)                              // Tier 1 entry
├── .agent(model:capabilities:threadID:services:) // Tier 2 entry
├── .agent(model:profile:lane:...)              // Tier 3 entry
├── .version                                    // String

ColonyID<Domain>                                // Generic identity
ColonyTool.Name                                 // Type-safe tool name (36 constants)
ColonyTool.RiskLevel                            // .readOnly, .mutation, .network, etc.
ColonyTool.PromptStrategy                       // .automatic, .verbose, .minimal

ColonyModel
├── .foundationModels(configuration:)
├── .onDevice(fallback:policy:foundationModels:)
└── .providerRouting(providers:policy:)

ColonyService                                   // .filesystem, .shell, .git, .memory, ...
ColonyServiceBuilder                            // @resultBuilder

ColonyRuntime
├── threadID
├── send(_:optionsOverride:)
├── sendUserMessage(_:optionsOverride:)
└── resumeToolApproval(...)

ColonyConfiguration                             // 3-tier init
├── ModelConfiguration
├── SafetyConfiguration
├── ContextConfiguration
└── PromptConfiguration

ColonyRun.Outcome                               // .finished, .interrupted, .cancelled, .outOfSteps
ColonyRun.Handle                               // runID, attemptID, outcome
ColonyRun.Transcript                           // messages, finalAnswer, todos

ColonyArtifactKind                              // .conversationHistory, .checkpoint, ...
ColonyArtifactStore                            // actor

ColonyEventName                                // .runStarted, .toolInvoked, ...

// Protocols (for implementors)
ColonyModelClient
ColonyModelRouter
ColonyToolRegistry
ColonyFileSystemBackend
ColonyShellBackend
ColonyGitBackend
ColonyMemoryBackend
ColonySubagentRegistry
ColonyObservabilitySink

// Everything else: package or internal
```
