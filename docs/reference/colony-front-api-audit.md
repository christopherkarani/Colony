# Colony Front-Facing API Audit

Generated: 2026-03-20
Scope: `Colony`, `ColonyCore`, `ColonyControlPlane`, plus the effective `import Colony` surface created by `@_exported import Swarm`

## Executive Summary

Current direction:
- Human DX: `2.5 / 5`
- Agent DX: `2.0 / 5`

Why the score is low:
- the `Colony` product is not a bounded API; it re-exports all of `Swarm`
- Colony-owned entry points are duplicated across `ColonyBootstrap`, `ColonyAgentFactory`, and low-level service bags
- several public APIs leak `Hive`, `Swarm`, `Membrane`, and `Wax` types directly into the default surface
- too much of the support infrastructure is public instead of living behind a smaller canonical runtime API
- the inference/tooling layer is still heavily stringly typed where a stronger Swift surface would materially help agents and humans

The good part:
- the building blocks are already strong enough to produce a much cleaner API
- `ColonyModel`, `ColonyRuntime`, `ColonyHarnessSession`, and `ColonyControlPlaneService` can anchor a much smaller, much more elegant public surface

## Highest-Priority Findings

### 1. `Colony` currently exports all of `Swarm`

Evidence:
- `Sources/Colony/Colony.swift:1`
- `Sources/Colony/Colony.swift:2`

Problem:
- `import Colony` is not just “Colony”; it is effectively “Colony + ColonyCore + Swarm”.
- That destroys autocomplete signal for both humans and AI agents.
- It also makes any Colony API audit unstable, because Swarm evolution becomes Colony surface-area churn.

Recommendation:
- Remove `@_exported import Swarm`.
- Keep `@_exported import ColonyCore` only if `Colony` is intentionally the umbrella product.
- If Swarm adapters must remain public, move them into a separate adapter target instead of exporting the entire Swarm module.

### 2. Default Colony APIs leak lower layers directly

Evidence:
- `Sources/Colony/ColonyBootstrap.swift:13`
- `Sources/Colony/ColonyBootstrap.swift:30`
- `Sources/Colony/ColonyBootstrap.swift:38`
- `Sources/Colony/ColonyBootstrap.swift:84`
- `Sources/Colony/ColonyBootstrap.swift:103`
- `Sources/Colony/ColonyWaxMemoryBackend.swift:16`
- `Sources/Colony/SwarmToolBridge.swift:13`

Problem:
- the default runtime/bootstrap path exposes `MembraneEnvironment`, `WaxStorageBackend`, `AnyJSONTool`, `HiveModelClient`, `HiveCheckpointStore`, `HiveClock`, `HiveLogger`
- these are implementation-layer dependencies, not the ideal Colony language
- for an AI coding agent, this makes the “right” entry point ambiguous and encourages wrong-layer usage

Recommendation:
- keep one public Colony-native runtime assembly path
- move Swarm/Wax/Hive/Membrane bridges to explicit adapter/support targets:
  - `ColonySwarmAdapters`
  - `ColonyMemoryAdapters`
  - `ColonyHarnessSupport`
- keep only Colony-native protocols and option structs in the default `Colony` product

### 3. Runtime assembly has too many competing entry points

Evidence:
- `Sources/Colony/ColonyPublicAPI.swift:172`
- `Sources/Colony/ColonyPublicAPI.swift:221`
- `Sources/Colony/ColonyPublicAPI.swift:258`
- `Sources/Colony/ColonyBootstrap.swift:56`
- `Sources/Colony/ColonyBootstrap.swift:174`
- `Sources/Colony/ColonyAgentFactory.swift:76`
- `Sources/Colony/ColonyAgentFactory.swift:79`

Problem:
- today the user can start with `ColonyBootstrap`, `ColonyAgentFactory`, `ColonyRuntimeCreationOptions`, `ColonyBootstrapOptions`, or direct runtime services
- that is too many top-level nouns for one job
- agents need a single obvious path for first-try correctness

Recommendation:
- make `ColonyBootstrap` the only default construction API
- demote `ColonyAgentFactory` to `package` or move it behind an advanced support target
- rename:
  - `ColonyRuntimeServices` -> `ColonyEnvironment`
  - `ColonyRuntimeCreationOptions` -> `ColonyRuntimeOptions`
  - `ColonyBootstrapOptions` -> `ColonyBootstrap.Configuration` or `ColonyBootstrapOptions` only if all other option structs are collapsed

### 4. `ColonyRuntimeServices` is a 14-slot optional existential bag

Evidence:
- `Sources/Colony/ColonyPublicAPI.swift:172`
- `Sources/Colony/ColonyPublicAPI.swift:188`

Problem:
- every dependency is optional
- most fields are existentially typed (`any Protocol`)
- the type mixes core runtime seams with optional advanced seams and Swarm/Membrane-specific seams
- the call site is noisy and hard to autocomplete correctly

Recommendation:
- split the current bag into clearer groups:
  - `ColonyWorkspace`
  - `ColonyTooling`
  - `ColonyMemory`
  - `ColonySubagents`
- if a single wrapper is still desired, make it a composed value with default constructors, not a flat bag of optionals

Suggested shape:

```swift
public struct ColonyEnvironment: Sendable {
    public var workspace: ColonyWorkspace
    public var tools: ColonyToolEnvironment
    public var memory: ColonyMemoryEnvironment
    public var subagents: ColonySubagentEnvironment
}
```

### 5. The inference and tool surface is still too stringly typed

Evidence:
- `Sources/ColonyCore/ColonyInferenceSurface.swift:47`
- `Sources/ColonyCore/ColonyInferenceSurface.swift:59`
- `Sources/ColonyCore/ColonyInferenceSurface.swift:81`
- `Sources/ColonyCore/ColonyInferenceSurface.swift:163`
- `Sources/ColonyCore/ColonyToolApproval.swift:112`
- `Sources/Colony/ColonyAgentFactory.swift:88`

Problem:
- tool definitions, tool calls, structured output, tool approval allow-lists, provider ids, artifact kinds, model names, and subagent kinds are all primarily `String`
- that is workable for plumbing, but weak for front-facing Swift
- AI agents benefit heavily from typed affordances and enum-backed choices

Recommendation:
- keep raw JSON/string bridges internally
- add typed overlays publicly

High-value additions:
- `ColonyModelID`
- `ColonyToolName`
- `ColonyArtifactKind`
- `ColonySubagentKind`
- `ColonyStructuredSchema<Output>`
- `ColonyToolSpec<Arguments, Output>`

## What Should Stay

Keep as the canonical default API:
- `ColonyBootstrap`
- `ColonyModel`
- `ColonyRuntime`
- `ColonyRunHandle`
- `ColonyHarnessSession`
- `ColonyConfiguration`
- `ColonyRunOptions`
- `ColonyToolApprovalDecision`
- `ColonyVirtualPath`
- `ColonyControlPlaneService`

Keep, but only in an advanced/support layer:
- `ColonyArtifactStore`
- `ColonyDurableRunStateStore`
- `ColonyObservabilityEmitter`
- `ColonyRedactionPolicy`
- `ColonyHardenedShellBackend`
- `ColonyDiskFileSystemBackend`
- `ColonyCompositeFileSystemBackend`

## What Should Be Removed, Split, or Demoted

Remove from default `Colony` surface:
- `@_exported import Swarm`

Demote to `package` or move to adapter/support targets:
- `ColonyAgentFactory`
- `ColonyCapabilityReportingModelClient`
- `ColonyCapabilityReportingModelRouter`
- `SwarmToolBridge`
- `SwarmToolRegistration`
- `SwarmMemoryAdapter`
- `SwarmSubagentAdapter`
- `ColonyWaxMemoryBackend`
- `ColonyDefaultSubagentRegistry`
- `ColonyPrompts`
- `ColonyScratchbookStore`
- `ColonyApproximateTokenizer`
- `ColonyInMemoryMemoryBackend`
- `ColonyInMemoryFileSystemBackend`
- `ColonyDiskFileSystemBackend`
- `ColonyInMemoryToolApprovalRuleStore`
- `ColonyFileToolApprovalRuleStore`
- `ColonyInMemoryToolAuditLogStore`
- `ColonyFileSystemToolAuditLogStore`

Rationale:
- these are useful implementation pieces, but they are not the smallest possible front-facing API
- exposing them by default teaches callers the wrong abstraction level

## Rename Audit

### Keep but rename

| Current | Recommended | Reason |
| --- | --- | --- |
| `ColonyFoundationModelConfiguration` | `ColonyFoundationModelsOptions` | “Options” reads as configuration input; “FoundationModels” matches the framework name |
| `ColonyOnDeviceModelPolicy` | `ColonyOnDevicePolicy` | shorter and still precise |
| `ColonyProviderRoutingPolicy` | `ColonyRoutingPolicy` | avoid repeating “Provider” when `ColonyProvider` already exists |
| `ColonyRuntimeServices` | `ColonyEnvironment` | this is dependency injection, not “services” in the runtime sense |
| `ColonyRuntimeCreationOptions` | `ColonyRuntimeOptions` | simpler noun |
| `ColonyProductSessionID` | `ColonySessionID` | “Product” adds noise without clarifying meaning |
| `ColonyProductSessionVersionID` | `ColonySessionVersionID` | same |
| `ColonyProductSessionRecord` | `ColonySessionRecord` | same |
| `ColonyStructuredOutputPayload` | `ColonyStructuredResult` | it is the emitted structured result, not just a payload |
| `ColonyControlPlaneRouteDescriptor` | `ColonyRoute` | shorter and still clear within the module |

### Names that should become enums instead of free-form strings

- `ColonyProvider.id`
- `ColonyModelRequest.model`
- `ColonyToolDefinition.name`
- `ColonyToolCall.name`
- `ColonyArtifactRecord.kind`
- `ColonySubagentRequest.subagentType`

## Access-Control Audit

### Strong demotion candidates

These should not be part of the default public story:
- `ColonyPrompts` (`Sources/ColonyCore/ColonyPrompts.swift:3`)
- `ColonyScratchbookStore` (`Sources/ColonyCore/ColonyScratchbookStore.swift:3`)
- `ColonyCapabilityReportingModelClient` (`Sources/Colony/ColonyModelCapabilityReporting.swift:4`)
- `ColonyCapabilityReportingModelRouter` (`Sources/Colony/ColonyModelCapabilityReporting.swift:16`)
- `ColonyWaxMemoryBackend` (`Sources/Colony/ColonyWaxMemoryBackend.swift:5`)
- `SwarmToolBridge` and `SwarmToolRegistration` (`Sources/Colony/SwarmToolBridge.swift:11`, `Sources/Colony/SwarmToolBridge.swift:61`)
- `SwarmMemoryAdapter` (`Sources/Colony/SwarmMemoryAdapter.swift:32`)
- `SwarmSubagentAdapter` (`Sources/Colony/SwarmSubagentAdapter.swift:34`)

### Support types that belong in a support product

- `ColonyArtifactStore`
- `ColonyDurableRunStateStore`
- `ColonyObservabilityEmitter`
- `ColonyRedactionPolicy`
- `ColonyHardenedShellBackend`

## Generics and Strong-Typing Opportunities

### 1. Strong IDs via one generic building block

Current repetition:
- `ColonyThreadID`
- `ColonyInterruptID`
- `ColonyProjectID`
- `ColonyProductSessionID`
- `ColonyProductSessionVersionID`
- `ColonySessionShareToken`
- `ColonyHarnessSessionID`

Recommended:

```swift
public struct ColonyID<Tag>: Hashable, Codable, Sendable, LosslessStringConvertible {
    public let rawValue: String
}
```

Then:

```swift
public enum ColonyProjectTag {}
public typealias ColonyProjectID = ColonyID<ColonyProjectTag>
```

If the team wants better ergonomics, a macro is justified here:
- `@StrongID("project")`
- `@StrongID("session")`

This is one of the few macro uses with clear leverage because it removes repetitive wrappers without obscuring behavior.

### 2. Typed structured outputs

Current:
- `ColonyStructuredOutput.jsonSchema(name:schemaJSON:)`
- `ColonyStructuredOutputPayload.json`

Problem:
- callers hand around schema JSON and response JSON as raw strings

Recommended:

```swift
public struct ColonyStructuredSchema<Output: Decodable & Sendable>: Sendable {
    public let name: String
    public let schemaJSON: String
}

public struct ColonyDecodedOutput<Output: Decodable & Sendable>: Sendable {
    public let rawJSON: String
    public let value: Output
}
```

Then add typed request/response overlays instead of replacing the raw bridge immediately.

### 3. Typed tool specs

Current:
- `ColonyToolDefinition`
- `ColonyToolCall`
- `ColonyToolResult`

Recommended overlay:

```swift
public struct ColonyToolSpec<Arguments: Codable & Sendable, Output: Codable & Sendable>: Sendable {
    public let name: ColonyToolName
    public let description: String
}
```

Keep the raw JSON types internally for model/provider boundaries, but let user-facing registration and invocation be generic.

### 4. Control-plane route typing

Current:
- string paths
- enum operation
- optional method/stream event

This is already close, but if expanded further it should become:
- `ColonyRoute<Operation>`
- or a nested `ColonyControlPlaneOperation.Metadata`

This is a lower-priority generic opportunity than strong ids and typed outputs.

## Enum Audit

Use enums more aggressively for:
- artifact kinds
- subagent kinds
- provider ids if the default package ships known providers
- model families if Colony wants first-class model presets

Keep enums as they are:
- `ColonyToolApprovalDecision`
- `ColonyToolRiskLevel`
- `ColonyRunOutcome`
- `ColonyRunCheckpointPolicy`
- `ColonyRunStreamingMode`

## `some` / `any` Audit

Good:
- `ColonyProvider.init(client: some ColonyModelClient, ...)`
- `ColonyModel` constructors taking `some ColonyModelClient` / `some ColonyModelRouter`

Needs work:
- `ColonyRuntimeServices` stores many `any` backends in public mutable properties
- `ColonyBootstrapResult` publicly returns `any ColonyMemoryBackend`
- `SwarmToolRegistration` publicly stores `any AnyJSONTool`

Recommendation:
- use `some` at construction boundaries
- hide existential storage behind concrete public wrappers
- keep `any` only where heterogeneous storage is truly part of the public contract

## Macro Audit

Macros are justified only in a few places:

### Worth it

- strong raw-value ids
- possibly route descriptor declarations if the control plane grows significantly
- possibly typed tool schema generation if Colony decides to own a tool-definition macro

### Not worth it yet

- runtime/environment configuration
- scratchbook storage
- shell/git/lsp backends

The API problems here are mostly structural and naming issues, not boilerplate generation issues.

## Recommended Target Product Split

### `Colony`

Keep lean:
- `ColonyBootstrap`
- `ColonyModel`
- `ColonyRuntime`
- `ColonyHarnessSession`
- `ColonyConfiguration`
- `ColonyRunOptions`
- Colony-native protocols and value types

### `ColonyAdapters`

Move here:
- Swarm bridges
- Wax memory adapter/backend
- Membrane environment adapter
- advanced capability-reporting protocols if still needed

### `ColonySupport`

Move here:
- artifact store
- durable run-state store
- observability sinks/emitter
- hardened shell backend
- redaction and persistence helpers

### `ColonyControlPlane`

Keep separate, but simplify naming:
- drop `Product` from session types
- replace repetitive ID wrappers with generic or macro-generated strong IDs

## Proposed Canonical User Story

The ideal call site should read like this:

```swift
let runtime = try await ColonyBootstrap().bootstrap(
    .init(
        runtime: .init(
            profile: .cloud,
            threadID: "colony:session-1",
            model: .foundationModels(),
            modelName: "foundation-models",
            services: .default
        )
    )
).runtime
```

Longer-term, the API should compress further toward:

```swift
let runtime = try await ColonyBootstrap().runtime(
    .coding(
        model: .foundationModels(),
        workspace: .disk(root: repoURL),
        memory: .wax(at: memoryURL)
    )
)
```

That is the level of call-site clarity that will materially improve both human and agent usage.

## Verification Notes

Completed:
- source-level public surface audit across `Sources/ColonyCore`, `Sources/Colony`, and `Sources/ColonyControlPlane`
- public declaration counting by module
- line-level review of entry points, adapters, runtime assembly, inference surface, safety surface, persistence support, and control-plane types

Blocked:
- `swift package dump-symbol-graph` for the full Colony package

Blocker:
- upstream `Conduit` compile errors during package graph build, specifically in `OpenAIProvider+Helpers.swift` and `AnthropicProvider+Helpers.swift`

Conclusion:
- the audit findings are still actionable because the public source surface is explicit and readable
- before shipping a breaking cleanup, re-run a symbolgraph-based audit after the `Conduit` blocker is fixed
