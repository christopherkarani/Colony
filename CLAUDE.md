# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test

Colony is a Swift Package (`swift-tools-version: 6.2`) targeting **iOS 26+** and **macOS 26+**.

**Dependency:** Colony builds on [Swarm](https://github.com/christopherkarani/Swarm) (orchestration primitives). Production builds resolve Swarm from GitHub at the version pinned in `Package.swift` (currently `0.5.0`). For local development against a sibling Swarm checkout at `../Swarm`, set `COLONY_USE_LOCAL_SWARM_PATH=1` before resolving. Note: `HIVE_DEPENDENCY.lock` and `scripts/ci/bootstrap-hive.sh` are legacy artifacts from the pre-Swarm era — the README still references them but the actual dependency is Swarm.

```bash
swift build                                      # build all targets
swift test                                       # run all test targets
swift test --filter ColonyTests                  # run only the core library tests
swift test --filter ColonyControlPlaneTests      # run only control plane tests
swift test --filter ColonyExecutionHardeningTests
swift test --filter ColonyResearchAssistantExampleTests
swift test --filter ColonyTests.ColonyAgentTests/colonyInterruptsAndResumesApproved  # single test
swift run ColonyResearchAssistantExample --help  # run the example CLI
```

## Architecture

### Module Split

| Target                    | Kind         | Purpose                                                                                                                 |
|---------------------------|--------------|-------------------------------------------------------------------------------------------------------------------------|
| `ColonyCore`              | library      | Pure value types, protocols, policies. Capabilities, configuration, tool approval, compaction, summarization, scratchbook, filesystem/shell/git/LSP/subagent backend contracts, built-in tool definitions, tokenizer, prompts. |
| `Colony`                  | library      | Runtime orchestration built on Swarm primitives. Agent graph (`ColonyAgent`), fluent builder (`ColonyBuilder`), runtime wrapper (`ColonyRuntime`), Foundation Models client, on-device/provider routers, MiniMax OpenAI client, durable checkpointing, observability, harness session. |
| `ColonyControlPlane`      | library      | Project/session management service. REST route descriptors, project store, session store, transport abstraction. Depends on `Colony` + `ColonyCore`. |
| `ColonyResearchAssistantExample` | executable | CLI research assistant example. |

`Colony` does `@_exported import ColonyCore`, so downstream consumers only need `import Colony`. Both libraries depend on `Swarm` (from the `Swarm` package product).

### Runtime Loop

The agent graph (`Sources/Colony/ColonyAgent.swift`) is compiled into a Swarm graph with these nodes:

```
preModel → model → routeAfterModel → tools → toolExecute → preModel
```

- `preModel` — patches dangling tool calls, runs summarization if policy is configured + filesystem is present, applies the compaction policy, writes `llmInputMessages`.
- `model` — builds the system prompt (memory, skills, scratchbook view, optional tool list), enforces `requestHardTokenLimit`, calls the model client.
- `routeAfterModel` — routes to `tools` if the model produced tool calls, otherwise terminates with a final answer.
- `tools` — selects/validates tool calls, raises approval interrupts when policy demands.
- `toolExecute` — dispatches through backends, writes results back, loops to `preModel`.

The loop terminates when the model produces a final answer (no tool calls) or the runtime yields an `.interrupted` outcome (e.g., tool-approval required).

### Capability-Gated Tool Families

Tools are only injected into the prompt/schema when the capability is enabled **and** the backend is wired. Capabilities live in `ColonyCore/ColonyCapabilities.swift` as an `OptionSet`.

| Capability        | Tools                                                                       | Backend Protocol                    |
|-------------------|-----------------------------------------------------------------------------|-------------------------------------|
| `.planning`       | `write_todos`, `read_todos`                                                 | (built-in)                          |
| `.filesystem`     | `ls`, `read_file`, `write_file`, `edit_file`, `glob`, `grep`                | `ColonyFileSystemBackend`           |
| `.shell`          | `execute`                                                                   | `ColonyShellBackend`                |
| `.shellSessions`  | `shell_open`, `shell_read`, `shell_write`, `shell_close`                    | `ColonyShellBackend` (session-capable) |
| `.scratchbook`    | `scratch_read/add/update/complete/pin/unpin`                                | (built-in, filesystem-backed)       |
| `.subagents`      | `task`                                                                      | `ColonySubagentRegistry`            |
| `.git`            | `git_status`, `git_diff`, `git_commit`, `git_branch`, `git_push`, `git_prepare_pr` | `ColonyGitService`           |
| `.lsp`            | `lsp_symbols`, `lsp_diagnostics`, `lsp_references`, `lsp_apply_edit`        | `ColonyLSPBackend`                  |
| `.applyPatch`     | `apply_patch`                                                               | `ColonyApplyPatchBackend` (optional; built-in fallback) |
| `.webSearch`      | `web_search`                                                                | `ColonyWebSearchBackend`            |
| `.codeSearch`     | `code_search`                                                               | `ColonyCodeSearchBackend`           |
| `.mcp`            | `mcp_*`                                                                     | `ColonyMCPBackend`                  |
| `.plugins`        | `plugin_list_tools`, `plugin_invoke`                                        | `ColonyPluginToolRegistry`          |
| `.memory`         | `memory_recall`, `memory_remember`                                          | `ColonyMemoryBackend`               |

`ColonyCapabilities.default == [.planning, .filesystem]`.

### Profiles

`ColonyProfile` (in `Sources/Colony/ColonyAgentFactory.swift`) provides two presets:

- **`.device`** (alias `.onDevice4k`) — Strict ~4k token budget. Compaction at 2,600 tokens, summarization at 3,200, tool result eviction at 700 tokens. Scratchbook enabled. `allowList` tool approval for built-in safe read-only tools. Designed for on-device Foundation Models.
- **`.cloud`** — Generous limits (compaction at 12k, summarization at 170k, eviction at 20k). Scratchbook disabled by default. `.never` tool approval policy.

Both profiles are customizable via `.configure { config in ... }` on the builder; user overrides are merged onto the profile defaults via `mergingOnto`.

### Public Entry Points

The API supports both a modern fluent builder and a legacy factory shim:

```swift
// Modern: top-level Colony namespace
let runtime = try Colony.start(modelName: "llama3.2", profile: .device) { config in
    config.capabilities = [.planning, .filesystem, .subagents]
}

// Modern: fluent builder
let runtime = try ColonyBuilder()
    .model(name: "llama3.2")
    .profile(.device)
    .capabilities([.planning, .filesystem])
    .filesystem(ColonyInMemoryFileSystemBackend())
    .model(myModelClient)            // any ColonyModelClient
    .build()

// Legacy: ColonyAgentFactory is a `typealias` for ColonyBuilder; .makeRuntime(...)
// variants remain for backward compatibility.
// Legacy: ColonyBootstrap.bootstrap(modelName:) is deprecated in favor of Colony.start(...).
```

`ColonyBuilder.build()` requires both a non-empty `modelName` and either a model client or routing policy — otherwise it throws `ColonyBuilderError`.

### Key Types

- `Colony` (enum) — Top-level namespace. `Colony.start(modelName:profile:configure:)` is the simplest entry point.
- `ColonyBuilder` — Fluent builder for runtimes. Value-type, each method returns a new builder. `ColonyAgentFactory` is a deprecated alias.
- `ColonyRuntime` — Thin wrapper around `ColonyRunControl`. Exposes `sendUserMessage(_:)`, `resumeToolApproval(interruptID:decision:)`, and `resumeToolApproval(interruptID:perToolDecisions:)`.
- `ColonyRunControl` — Underlying run control (`start`, `resume`). Holds thread ID + run options.
- `ColonyRuntimeEngine` — Engine that drives the Swarm graph.
- `ColonyConfiguration` — All agent settings: capabilities, approval policy/rules, risk levels, compaction, scratchbook, memory/skill sources, summarization, token limits, system prompt knobs.
- `ColonyContext` — Runtime context holding configuration + all backend references + tokenizer. Passed to graph nodes.
- `ColonyAgent` — `package`-visible namespace owning the node IDs and the node implementations for the compiled Swarm graph.
- `ColonySchema` — Swarm schema defining the agent's channels (messages, llmInputMessages, finalAnswer, …).
- `ColonyProfile` — Preset configuration profile (`.device` / `.cloud`).
- `ColonyModelClient` — Public model-client protocol. Adapted to Swarm via `ColonyModelClientBridge`.
- `ColonyFoundationModelsClient` — On-device Apple Foundation Models client (iOS/macOS 26+).
- `ColonyMiniMaxOpenAIClient` — OpenAI-compatible client for MiniMax (and similar) endpoints.
- `ColonyOnDeviceModelRouter` / `ColonyProviderRouter` / `ColonyModelRouter` — Routing layers selecting a client per request.
- `ColonyRoutingPolicy` — Policy object consumed by the builder's `routingPolicy(_:)`.
- `ColonyDefaultSubagentRegistry` — Default (package-access) subagent registry implementation. Use the `ColonySubagentRegistry` protocol externally.
- `ColonyDurableCheckpointStore` / `ColonyDurableRunStateStore` / `ColonyArtifactStore` — Durable persistence layers; all public APIs now use typed `ColonyThreadID` / `ColonyRunID` / `ColonyArtifactID`.
- `ColonyHarnessSession` — Higher-level orchestrator for long-running harness sessions with checkpointing and observability.
- `ColonyObservability` — Observability event types keyed on typed Colony IDs.

### Human-in-the-Loop Approval

Tool approval is governed by `ColonyToolApprovalPolicy` (`.never`, `.always`, `.allowList(Set<String>)`) combined with per-risk-level rules (`mandatoryApprovalRiskLevels` defaults to `[.mutation, .execution, .network]`) and optional per-tool overrides via `toolRiskLevelOverrides` / `ColonyToolApprovalRuleStore`.

When approval is required, the runtime emits an `.interrupted` outcome with `.toolApprovalRequired(toolCalls)` payload. Resume with:

```swift
await runtime.resumeToolApproval(interruptID: interruption.interrupt.id, decision: .approved)
// or: .rejected, .cancelled, .perTool([...])
```

### Control Plane (ColonyControlPlane)

`ColonyControlPlane` is a separate library product exposing a project/session management service:

- `ColonyControlPlaneService` (actor) — implements project and session CRUD.
- `ColonyControlPlaneRouteDescriptor` / `.defaultRouteDescriptors` — REST route table (`/v1/projects`, `/v1/projects/{id}/sessions`, `/v1/sessions/{id}`, etc.).
- `ColonyControlPlaneTransport` — transport abstraction.
- `ColonyProjectStore` / `ColonySessionStore` — in-memory stores used by the service.
- Domain types: `ColonyProjectID`, `ColonyProductSessionID`, `ColonyProductSessionVersionID`, `ColonySessionShareToken`, `ColonyProjectRecord`.

Tests live in `Tests/ColonyControlPlaneTests/`.

## Testing Conventions

- **Framework:** Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`). No XCTest.
- **Mock model clients:** Tests use scripted in-memory `ColonyModelClient` / Swarm model client implementations (e.g. `ScriptedModel`, `ExecuteToolModel`, `TaskToolModel`, `RecordingRequestModel`) that return deterministic responses.
- **In-memory backends:** `ColonyInMemoryFileSystemBackend`, `InMemoryCheckpointStore`, `RecordingShellBackend`, `RecordingSubagentRegistry`.
- **Legacy compatibility shims:** `LegacyGraphRuntimeCompat.swift` and `ColonyInternalRuntimeCompat.swift` exist to let older tests keep compiling through the Swarm migration — prefer the new fluent builder in new tests.
- **Test targets:**
  - `ColonyTests` — broad core-library coverage (agent loop, compaction, summarization, scratchbook, tool approval/safety/audit, memory, LSP, Git, routing, on-device router, MiniMax client, subagent delegation, persistence/observability, eviction).
  - `ColonyExecutionHardeningTests` — execution sandbox / hardened-shell coverage.
  - `ColonyControlPlaneTests` — control plane service + route tests.
  - `ColonyResearchAssistantExampleTests` — CLI example coverage.

## Example: ColonyResearchAssistantExample

Located at `Sources/ColonyResearchAssistantExample/`. A CLI research assistant demonstrating:

- Model resolution modes: `auto` / `foundation` / `mock`
- Profile selection: `on-device` / `cloud`
- Interactive REPL with human-in-the-loop tool approval
- Subagent delegation for focused research tasks

Entry point: `main.swift` → `ResearchAssistantEntrypoint.run(arguments:)` → `ResearchAssistantApp`.

## Backward Compatibility / Migration Notes

See `CHANGELOG.md` for the authoritative list. Recent breaking changes of note:

- All public APIs use **typed Colony domain IDs** (`ColonyThreadID`, `ColonyRunID`, `ColonyArtifactID`, `ColonyHarnessSessionID`) instead of raw strings/UUIDs or Hive types. Use `.hiveThreadID` / `.hiveRunID` extensions if conversion is needed.
- `ColonySubagentRequest.subagentType` is now `ColonySubagentType` (strongly typed), not `String`. Use constants like `.general`, `.compactor`.
- `ColonyDefaultSubagentRegistry` is now `package` access — external consumers should depend on the `ColonySubagentRegistry` protocol or factory methods.
- The `Hive` dependency has been replaced by `Swarm`. Source code uses `SwarmClock`, `SwarmLogger`, `SwarmThreadID`, `SwarmInferenceHints`, etc. `HIVE_DEPENDENCY.lock` and `scripts/ci/bootstrap-hive.sh` are stale leftovers — do not introduce new references to Hive. Existing `docs/swarm-migration-plan.md` captures the migration history.

## Conventions For Agent Edits

- **Prefer editing existing files.** This repo already has extensive module-level source files; new features usually belong next to an existing sibling.
- **Swift 6.2 strict concurrency is required.** All new types must be `Sendable`-correct; actor isolation matters.
- **Two access tiers:** `public` for the external API surface, `package` for cross-target internals within Colony/ColonyCore. Don't elevate `package` to `public` without a deliberate reason.
- **Tool additions:** add the capability flag in `ColonyCore/ColonyCapabilities.swift`, the tool definition in `ColonyCore/ColonyBuiltInToolDefinitions.swift`, dispatch in `ColonyAgent`'s `toolExecute`, and wire a backend protocol (if external). Write deterministic Swift Testing coverage.
- **Don't commit legacy `HIVE_*` references in new code.** Use Swarm primitives.
- **`CLAUDE.md` files inside `Sources/` and `Tests/` subdirectories are auto-generated by `claude-mem`** and marked with `<claude-mem-context>` — do not hand-edit them.
