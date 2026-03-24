# Colony API Final Audit

Generated: 2026-03-20 | Framework: Colony + ColonyCore + ColonyControlPlane | Branch: develop

---

## Critical Issues (must fix before shipping)

### C1: `@_exported import ColonyCore` — ALREADY FIXED (2026-03-22 verification)

- **File**: `Sources/Colony/Colony.swift:1`
- **Current**: `import ColonyCore` (NO `@_exported`)
- **Verification**: Agent audit confirmed Colony.swift only has a regular `import ColonyCore`. ColonyCore types are NOT re-exported via `import Colony`. Users must explicitly `import ColonyCore`.
- **Status**: C1 from 2026-03-20 audit is OUTDATED — the issue was already resolved.
- **Note**: The api-surface-catalog.md incorrectly stated ~95 ColonyCore types were available via `import Colony`. This has been corrected — ColonyCore requires separate import.

### C2: `ColonyArtifactStore.put()` and `.list()` expose `HiveThreadID` / `HiveRunID`

- **File**: `Sources/Colony/ColonyArtifactStore.swift:97-98, 128-129`
- **Current**:
  ```swift
  public func put(threadID: HiveThreadID, runID: HiveRunID?, ...) // line 97
  public func list(threadID: HiveThreadID?, runID: HiveRunID?, ...) // line 128
  ```
- **Proposed**:
  ```swift
  public func put(threadID: ColonyThreadID, runID: UUID?, ...) // use Colony types
  public func list(threadID: ColonyThreadID?, runID: UUID?, ...) // use Colony types
  ```
- **Reason**: `HiveThreadID` and `HiveRunID` are internal HiveCore types. An agent trying to call `put()` gets a compile error unless they `import HiveCore`. This completely breaks the API contract that Colony wraps Hive.
- **Breaking**: Yes — callers must pass `ColonyThreadID` instead of `HiveThreadID`.

### C3: `ColonyDefaultSubagentRegistry` public init exposes `AnyHiveModelClient`

- **File**: `Sources/Colony/ColonyDefaultSubagentRegistry.swift:29, 46`
- **Current**:
  ```swift
  public init(modelName: String, model: AnyHiveModelClient, clock: any HiveClock, logger: any HiveLogger, ...)
  public init(profile: ColonyProfile, modelName: String, model: AnyHiveModelClient, clock: any HiveClock, logger: any HiveLogger, ...)
  ```
- **Proposed**: Demote both inits to `package`. Users should never construct this directly — it's created internally by `ColonyAgentFactory`. If users need a custom subagent registry, they conform to `ColonySubagentRegistry` protocol.
- **Reason**: `AnyHiveModelClient`, `HiveClock`, and `HiveLogger` are all HiveCore types. An agent cannot construct this without `import HiveCore`.

### C4: `SwarmToolRegistration` and `SwarmToolBridge` expose Swarm types

- **File**: `Sources/Colony/SwarmToolBridge.swift:11-32, 61-125`
- **Current**:
  ```swift
  public struct SwarmToolRegistration: Sendable {
      public let tool: any AnyJSONTool  // Swarm type
  }
  public struct SwarmToolBridge: ColonyToolRegistry, Sendable {
      public init(registrations: [SwarmToolRegistration]) throws
      public init(tools: [any AnyJSONTool], ...) throws  // Swarm type
  }
  ```
- **Proposed**: These are intentional Swarm interop types — they SHOULD remain public, but with a clear naming convention. Rename to `ColonySwarmToolRegistration` and `ColonySwarmToolBridge` to make it obvious these are bridge types.
  Alternatively, move to a separate `ColonySwarmInterop` product so they don't pollute `import Colony`.
- **Reason**: These types require `import Swarm` to use. An agent trying to register Swarm tools from pure Colony code gets compile errors.

### C5: `SwarmMemoryAdapter` exposes Swarm types in public init

- **File**: `Sources/Colony/SwarmMemoryAdapter.swift:40-56`
- **Current**:
  ```swift
  public init(_ memory: any Memory)  // Swarm type
  public init(backend: any PersistentMemoryBackend, ...)  // Swarm type
  ```
- **Proposed**: Same as C4 — rename to `ColonySwarmMemoryAdapter` and/or move to `ColonySwarmInterop`.
- **Reason**: Requires `import Swarm` to construct.

### C6: `ColonyDurableRunStateStore.appendEvent(_:threadID:)` exposes `HiveThreadID`

- **File**: `Sources/Colony/ColonyDurableRunStateStore.swift:60`
- **Current**: `public func appendEvent(_ envelope: ColonyHarnessEventEnvelope, threadID: HiveThreadID)`
- **Proposed**: `public func appendEvent(_ envelope: ColonyHarnessEventEnvelope, threadID: ColonyThreadID)`
- **Reason**: Same as C2. HiveCore leak in public method signature.

### C7: `SwarmSubagentAdapter` exposes Swarm's `AgentRuntime` in public init

- **File**: `Sources/Colony/SwarmSubagentAdapter.swift:34-41`
- **Current**:
  ```swift
  public struct SwarmSubagentAdapter: ColonySubagentRegistry, Sendable {
      public init(agents: [(name: String, agent: any AgentRuntime, description: String)])
  }
  ```
- **Proposed**: Same as C4/C5 — rename to `ColonySwarmSubagentAdapter` and/or move to `ColonySwarmInterop`.
- **Reason**: `AgentRuntime` is a Swarm protocol. Requires `import Swarm` to use.

### C8: `ColonyHardenedShellBackend` is `@unchecked Sendable` public class

- **File**: `Sources/ColonyCore/ColonyHardenedShellBackend.swift:5`
- **Current**: `public final class ColonyHardenedShellBackend: ColonyShellBackend, @unchecked Sendable`
- **Proposed**: Convert to `actor` or prove thread safety with documentation.
- **Reason**: `@unchecked Sendable` in public API is a red flag. It promises thread safety without compiler verification. The class uses an internal `ColonyShellSessionManager` that manages state.

---

## Medium Issues (should fix)

### M1: In-memory test doubles exposed as public types

| Type | File | Proposed |
|------|------|----------|
| `ColonyInMemoryObservabilitySink` | `Colony/ColonyObservability.swift:58` | `package` access |
| `ColonyInMemoryMemoryBackend` | `ColonyCore/ColonyMemory.swift:72` | `package` access |
| `InMemoryColonyProjectStore` | `ColonyControlPlane/ColonyProjectStore.swift:10` | `package` access |
| `ColonySessionStore` | `ColonyControlPlane/ColonySessionStore.swift:3` | `package` access |
| `ColonyInMemoryFileSystemBackend` | `ColonyCore/ColonyFileSystem.swift:110` | `package` access |
| `ColonyInMemoryToolApprovalRuleStore` | `ColonyCore/ColonyToolApprovalRules.swift:77` | `package` access |
| `ColonyInMemoryToolAuditLogStore` | `ColonyCore/ColonyToolAudit.swift:116` | `package` access |
| `ColonyApproximateTokenizer` | `ColonyCore/ColonyTokenizer.swift:12` | `package` access |

- **Reason**: Test doubles pollute autocomplete. An agent sees `ColonyInMemory…` alongside production types and may choose the wrong one. These should live in test support or be `package` access.
- **Note**: `ColonySessionStore` is misleadingly named — it's actually an in-memory implementation but lacks the `InMemory` prefix. If kept public, rename to `InMemoryColonySessionStore`.

### M2: `ColonyObservabilityEvent.sessionID` and `.threadID` are raw `String?`

- **File**: `Sources/Colony/ColonyObservability.swift:33-34`
- **Current**:
  ```swift
  public let sessionID: String?
  public let threadID: String?
  ```
- **Proposed**:
  ```swift
  public let sessionID: ColonyHarnessSessionID?
  public let threadID: ColonyThreadID?
  ```
- **Reason**: The whole point of `ColonyID<Domain>` is to prevent accidental mixing. These fields bypass the type safety layer. An agent passing `threadID` as `sessionID` gets no compile error.

### M3: `ColonyArtifactRecord.id` and `.threadID` are raw `String`

- **File**: `Sources/Colony/ColonyArtifactStore.swift:32-33`
- **Current**:
  ```swift
  public let id: String
  public let threadID: String
  ```
- **Proposed**:
  ```swift
  public let id: ColonyID<ArtifactDomain>
  public let threadID: ColonyThreadID
  ```
- **Reason**: Same as M2. Missed during the `ColonyID<Domain>` migration.

### M4: `ColonyRunStateSnapshot.threadID` is raw `String`

- **File**: `Sources/Colony/ColonyDurableRunStateStore.swift:15`
- **Current**: `public let threadID: String`
- **Proposed**: `public let threadID: ColonyThreadID`
- **Reason**: Same pattern. Missed in migration.

### M5: `ColonyToolCall.name` should use `ColonyToolName`

- **File**: `Sources/ColonyCore/ColonyInferenceSurface.swift:33`
- **Current**: `public let name: String`
- **Proposed**: `public let name: ColonyToolName`
- **Reason**: `ColonyToolName` was created specifically for this purpose (with 37 static members for autocomplete), but the data type that carries tool names still uses raw `String`. This defeats the purpose of the newtype.
- **Breaking**: Yes — all code constructing `ColonyToolCall` must use `ColonyToolName`.
- **Note**: This cascades to `ColonyToolDefinition.name` (`ColonyInferenceSurface.swift:19`), `ColonyToolResult.toolCallID` (keep `String`, it's a call-instance ID, not a tool name), and `ColonyToolSafetyAssessment.toolName` (`ColonyToolSafetyPolicy.swift:76`).

### M6: `ColonyToolDefinition.name` should use `ColonyToolName`

- **File**: `Sources/ColonyCore/ColonyInferenceSurface.swift:19`
- **Current**: `public let name: String`
- **Proposed**: `public let name: ColonyToolName`
- **Reason**: Same as M5. This is where tool names originate.

### M7: `ColonySubagentRequest.subagentType` is raw `String`

- **File**: `Sources/ColonyCore/ColonySubagents.swift:72`
- **Current**: `public var subagentType: String`
- **Proposed**: Create `ColonySubagentType` newtype or use an enum. The `ColonyDefaultSubagentRegistry` only accepts `"general-purpose"` or `"compactor"`.
- **Reason**: An agent guessing the subagent type gets a runtime error instead of a compile error.

### M8: `ColonyInferenceHints` init has zero defaults

- **File**: `Sources/ColonyCore/ColonyInferenceSurface.swift:225-236`
- **Current**: All 4 parameters required with no defaults.
- **Proposed**:
  ```swift
  public init(
      latencyTier: ColonyLatencyTier = .interactive,
      privacyRequired: Bool = false,
      tokenBudget: Int? = nil,
      networkState: ColonyNetworkState = .online
  )
  ```
- **Reason**: Progressive disclosure violation. Most common use case is `.interactive` + `.online` + not privacy-sensitive.

### M9: Backward-compatible typealiases pollute autocomplete

- **File**: `Sources/Colony/ColonyPublicAPI.swift:198-202`
- **Current**:
  ```swift
  public typealias ColonyFoundationModelConfiguration = ColonyModel.FoundationModelConfiguration
  public typealias ColonyOnDeviceModelPolicy = ColonyModel.OnDevicePolicy
  public typealias ColonyProviderID = ColonyModel.ProviderID
  public typealias ColonyProvider = ColonyModel.Provider
  public typealias ColonyProviderRoutingPolicy = ColonyModel.RoutingPolicy
  ```
- **Proposed**: Mark as `@available(*, deprecated, renamed: "ColonyModel.FoundationModelConfiguration")` etc. and remove in next major version. Or delete now — they were just added in this PR.
- **Reason**: These create duplicate entries in autocomplete: `ColonyProviderID` AND `ColonyModel.ProviderID`.

### M10: `ColonyRecordMetadata` is `[String: String]` typealias

- **File**: `Sources/ColonyControlPlane/ColonyControlPlaneDomain.swift:4`
- **Current**: `public typealias ColonyRecordMetadata = [String: String]`
- **Proposed**: Keep — this is an intentional semantic typealias for stringly-typed metadata.
- **Note**: Low priority but worth noting that it's just a typealias.

### M11: `ColonyDefaultSubagentRegistry` should be `package` entirely

- **File**: `Sources/Colony/ColonyDefaultSubagentRegistry.swift:5`
- **Current**: `public struct ColonyDefaultSubagentRegistry: ColonySubagentRegistry`
- **Proposed**: `package struct ColonyDefaultSubagentRegistry: ColonySubagentRegistry`
- **Reason**: Users should never construct this directly — `ColonyAgentFactory` creates it internally. The `ColonySubagentRegistry` protocol is the public contract. Exposing the concrete type leaks implementation details (and the HiveCore-typed inits from C3).

### M12: `ColonyDurableRunStateStore` may be premature to expose publicly

- **File**: `Sources/Colony/ColonyDurableRunStateStore.swift:37`
- **Proposed**: Consider `package` access. The harness session creates and uses this internally.
- **Reason**: An agent building on Colony doesn't need direct access to durable run state persistence. If they do, they should use the harness session API.

### M13: `ColonyWaxMemoryBackend` is a concrete backend exposed publicly

- **File**: `Sources/Colony/ColonyWaxMemoryBackend.swift:5`
- **Proposed**: Keep public — users may want to construct it directly.
- **Note**: Its init takes `WaxStorageBackend` (a MembraneWax type), but this is expected for Wax integration.

---

## Low Issues (nice to have)

### L1: `ColonyCapabilities` vs `ColonyModelCapabilities` naming ambiguity

- **Files**: `ColonyCore/ColonyCapabilities.swift:1`, `ColonyCore/ColonyModelCapabilities.swift`
- **Current**: Two `OptionSet` types with near-identical names:
  - `ColonyCapabilities` = runtime capabilities (`.filesystem`, `.shell`, `.git`, etc.)
  - `ColonyModelCapabilities` = model capabilities (`.managedToolPrompting`, `.managedStructuredOutputs`)
- **Proposed**: Rename `ColonyCapabilities` to `ColonyRuntimeCapabilities` or rename `ColonyModelCapabilities` to `ColonyModelFeatures`.
- **Reason**: An agent frequently confuses these. "capabilities" is overloaded.

### L2: `ColonyHarnessSession.stop()` is `public` on a `package` actor

- **File**: `Sources/Colony/ColonyHarnessSession.swift:118`
- **Current**: `public func stop()` on `package actor ColonyHarnessSession`
- **Proposed**: Change to `package func stop()`
- **Reason**: The `public` modifier is meaningless on a `package`-level type. Agents won't see the actor but the access level inconsistency is confusing if reading source.

### L3: `ColonyRunInterruption.checkpointID` is raw `String`

- **File**: `Sources/ColonyCore/ColonyRuntimeSurface.swift:65`
- **Current**: `public let checkpointID: String`
- **Proposed**: Create `ColonyCheckpointID` via `ColonyID<CheckpointDomain>`.
- **Reason**: Lower priority since checkpoints are rarely directly accessed by users.

### L4: `ColonyChatMessage.id` is raw `String`

- **File**: `Sources/ColonyCore/ColonyInferenceSurface.swift:104`
- **Current**: `public let id: String`
- **Proposed**: Could be `ColonyID<MessageDomain>`, but this is a wire-format type that must round-trip with external model APIs, so raw `String` is defensible.
- **Note**: Skip this — `String` is correct for an external-facing ID.

### L5: `ColonyArtifactRecord` init has 7 required params with no defaults

- **File**: `Sources/Colony/ColonyArtifactStore.swift:40-48`
- **Proposed**: `id` could default to `UUID().uuidString`, `createdAt` could default to `Date()`, `redacted` could default to `true`, `metadata` could default to `[:]`.
- **Reason**: Progressive disclosure tier 1 should let you create a record with just `threadID`, `kind`, and `content`.

### L6: `ColonyRunCheckpointPolicy` and `ColonyRunStreamingMode` in ColonyCore

- **File**: `Sources/ColonyCore/ColonyRuntimeSurface.swift:4,11`
- **Note**: These are well-designed enums with good case names. No action needed.

### L7: Protocols with single public conformer

| Protocol | File | Only Conformer |
|----------|------|---------------|
| `ColonyToolAuditSigner` | `ColonyCore/ColonyToolAudit.swift:81` | `ColonyHMACSHA256ToolAuditSigner` |
| `ColonyTokenizer` | `ColonyCore/ColonyTokenizer.swift:3` | `ColonyApproximateTokenizer` |
| `ColonyShellBackend` | `ColonyCore/ColonyShell.swift:112` | `ColonyHardenedShellBackend` |

- **Proposed**: Keep as protocols — they enable test mocking. But note that `ColonyTokenizer` and its sole conformer `ColonyApproximateTokenizer` may be over-abstracted.

### L8: Protocols with 6+ requirements

| Protocol | File | Requirements | Note |
|----------|------|:---:|------|
| `ColonyFileSystemBackend` | `ColonyCore/ColonyFileSystem.swift:96` | 6 | list, read, write, edit, glob, grep |
| `ColonyShellBackend` | `ColonyCore/ColonyShell.swift:112` | 6 | execute, open/write/read/close session, list |
| `ColonyGitBackend` | `ColonyCore/ColonyGit.swift:247` | 6 | status, diff, commit, branch, push, preparePR |

- **Proposed**: These are cohesive backends — the requirements are related. No split recommended. Just noting for DX awareness.

### L9: Phantom domain types are module-level enums

- **File**: `Sources/ColonyCore/ColonyID.swift:43-49`
- **Current**: `public enum ThreadDomain: Sendable {}` etc. are top-level
- **Proposed**: Nest under `ColonyID` namespace:
  ```swift
  extension ColonyID {
      public enum Thread: Sendable {}
      public enum Interrupt: Sendable {}
      // ...
  }
  public typealias ColonyThreadID = ColonyID<ColonyID.Thread>
  ```
- **Reason**: `ThreadDomain`, `InterruptDomain` etc. pollute the module namespace as top-level enums. Nesting them removes 7 symbols from autocomplete.

---

## Score Card

| Category | Score (1-5) | Notes |
|----------|:-----------:|-------|
| Entry Points | 4.5 | `Colony.agent(model:)` is excellent. 3 tiers of progressive disclosure. Docked for incomplete progressive disclosure on some types |
| Progressive Disclosure | 4.0 | Good 3-tier init on `ColonyConfiguration`. `ColonyInferenceHints` and `ColonyArtifactRecord` miss defaults |
| Type Safety (IDs) | 3.0 | `ColonyID<Domain>` exists but 10+ public fields still use raw `String` where they should use it |
| Cross-Module Isolation | 2.0 | `HiveThreadID`, `HiveRunID`, `AnyHiveModelClient`, `AnyJSONTool`, `Memory` leak through public signatures |
| Naming Consistency | 3.5 | `ColonyCapabilities` vs `ColonyModelCapabilities` is confusing. Backward typealiases add noise |
| Test Double Isolation | 2.5 | 4 in-memory implementations exposed publicly. `ColonySessionStore` is misleadingly named |
| Protocol Design | 4.5 | All protocols are small (1-4 requirements), well-focused, and `Sendable` |
| Sendable Compliance | 4.0 | `ColonyHardenedShellBackend` uses `@unchecked Sendable` (C8) |
| Result Builder / DSL | 4.5 | `@ColonyServiceBuilder` is clean and functional |
| `ColonyID<Domain>` Generics | 4.0 | Well-designed phantom-type system. Docked for incomplete adoption (M2-M5) |

---

## Revised Agent DX Rating: 71/100

**Breakdown**:
- **Base score: 85/100** — The progressive disclosure entry points, result builder, phantom-typed IDs, and nested configuration are all excellent.
- **C1 ALREADY FIXED** — `@_exported import ColonyCore` was removed. ColonyCore types require separate `import ColonyCore`.
- **-5 for HiveCore leaks** (C2, C3, C6) — Agents hit compile errors trying to call `put()`, `list()`, or construct `ColonyDefaultSubagentRegistry`.
- **-5 for incomplete `ColonyID<Domain>` adoption** (M2-M5) — The type safety story is inconsistent. Some fields use typed IDs, others use raw `String`.
- **-3 for Swarm type leaks** (C4, C5, C7) — Bridge types are expected but require `import Swarm` to use. `SwarmSubagentAdapter` was missed in the initial redesign.
- **-3 for test double pollution** (M1) — 8 in-memory implementations exposed publicly across 3 modules.
- **-1 for `@unchecked Sendable`** (C8) — `ColonyHardenedShellBackend` bypasses Sendable checking.
- **+2 for correct ColonySwarmInterop isolation** (C4/C5 addressed) — Swarm bridge types properly prefixed and isolated in separate product.

**To reach 90+**: Fix C2/C6 (replace HiveCore types with Colony types), M2-M5 (complete `ColonyID<Domain>` adoption), M1 (demote test doubles), and NC1 (fix `PromptStrategy` enum cases). That's ~20 file changes.

---

## Implementation Priority

### Quick Wins (< 1 hour each, non-breaking)

1. **L7**: Nest phantom domain types under `ColonyID` extension
2. **L2**: Change `ColonyHarnessSession.stop()` to `package`
3. **M8**: Add defaults to `ColonyInferenceHints.init`
4. **M9**: Deprecate backward-compatible typealiases
5. **M11**: Demote `ColonyDefaultSubagentRegistry` to `package`
6. **M12**: Demote `ColonyDurableRunStateStore` to `package` (if not externally used)
7. **M1**: Demote in-memory test doubles to `package`

### Medium Lifts (1-4 hours, breaking)

1. **C1**: Remove `@_exported import ColonyCore` — requires updating all downstream imports
2. **C2/C6**: Replace `HiveThreadID`/`HiveRunID` with `ColonyThreadID`/`UUID` in `ColonyArtifactStore` and `ColonyDurableRunStateStore`
3. **M2-M4**: Replace raw `String` IDs with `ColonyThreadID`/`ColonyHarnessSessionID` in `ColonyObservabilityEvent` and `ColonyRunStateSnapshot`
4. **M5-M6**: Adopt `ColonyToolName` in `ColonyToolCall.name` and `ColonyToolDefinition.name`
5. **M7**: Create `ColonySubagentType` newtype

### Strategic Changes (4+ hours)

1. **C4/C5**: Create `ColonySwarmInterop` separate product to isolate Swarm bridge types from `import Colony`
2. **L1**: Rename `ColonyCapabilities` → `ColonyRuntimeCapabilities`

---

## 2026-03-22 Source Verification Audit — New Findings

The following issues were verified by agent audit teams cross-referencing source code against this audit document:

### Critical Discrepancies Found

| # | Issue | File | Actual State |
|---|-------|------|-------------|
| NC1 | **`ColonyTool.PromptStrategy` enum cases WRONG** | `ColonyCore/ColonyModelCapabilities.swift` | Actual cases are `.includeInSystemPrompt`, `.omitFromSystemPrompt` — NOT `.verbose`, `.minimal` as listed above in C5 section |
| NC2 | **`ColonyToolSafetyPolicyEngine` is `package` not `public`** | `ColonyCore/ColonyToolSafetyPolicy.swift` | Cannot be accessed externally; safety policy customization is NOT actually possible |
| NC3 | **`SwarmSubagentAdapterError` leaks unprefixed enum** | `ColonySwarmInterop/SwarmSubagentAdapter.swift` | `enum SwarmSubagentAdapterError` (not `ColonySwarm*`) appears in public `run()` error path |
| NC4 | **Deprecated transport typealiases misleading** | `ColonyControlPlane/ColonyControlPlaneDeprecations.swift` | `ColonyControlPlaneRESTTransport`, `ColonyControlPlaneSSETransport`, `ColonyControlPlaneWebSocketTransport` all alias to `ControlPlaneTransport` — claim distinct types that don't exist |

### Missing from Catalog (Public Types in Source)

These types exist as `public` in source but are NOT listed in `api-surface-catalog.md`:

| Type | File | Importance |
|------|------|-----------|
| `ColonyCost`, `ColonyTokenCount` | ColonyModelValueTypes.swift | MEDIUM |
| `ColonyModelName` | ColonyModelName.swift | MEDIUM |
| `ColonyToolAudit` namespace (9 types) | ColonyToolAudit.swift | HIGH |
| `ColonyPatch`, `ColonyWebSearch`, `ColonyCodeSearch`, `ColonyMCP` namespaces | ColonyCodingBackends.swift | MEDIUM |
| `ColonyFileSystem.DiskBackend` | ColonyFileSystem.swift | MEDIUM |
| `ColonyToolApprovalRule*` types | ColonyToolApprovalRules.swift | MEDIUM |
| `ColonyScratchItem`, `ColonyScratchbook` | ColonyScratchbook.swift | MEDIUM |

### What Was Confirmed Correct

| Issue | Status |
|-------|--------|
| C1 (`@_exported import ColonyCore`) | ALREADY FIXED — Colony.swift only has `import ColonyCore` |
| C4/C5 (Swarm type naming) | ALREADY ADDRESSED — `ColonySwarmToolBridge`, `ColonySwarmSubagentAdapter` are properly prefixed |
| `ColonySwarmInterop` product | EXISTS — separate product correctly isolates Swarm bridge types |
| `ColonyTool.Name` static constants | EXISTS — 36 static constants correctly defined |
| `ColonySwarmToolBridging` protocol | `package` — correctly not public |
