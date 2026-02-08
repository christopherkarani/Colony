# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test

Colony is a Swift Package (swift-tools-version: 6.2) targeting iOS 26+ and macOS 26+.

**Prerequisite:** A sibling Hive checkout must exist at `../hive` (local SPM dependency).

```bash
swift build                          # build all targets
swift test                           # run all tests
swift test --filter ColonyTests      # run only ColonyTests target
swift test --filter ColonyTests.colonyInterruptsAndResumesApproved  # single test by function name
swift run ColonyResearchAssistantExample --help                     # run the example CLI
```

## Architecture

### Two-Module Split

- **ColonyCore** — Pure value types, protocols, and policies. Zero runtime logic. Contains: capabilities, configuration, tool approval, compaction, summarization, scratchbook, filesystem/shell/subagent contracts, built-in tool definitions.
- **Colony** — Runtime orchestration built on HiveCore. Contains: the agent graph (`ColonyAgent`), factory (`ColonyAgentFactory`), runtime wrapper (`ColonyRuntime`), Foundation Models client, on-device model router, default subagent registry.

Both modules re-export `HiveCore` (from the local `../hive` dependency). Colony `@_exported import`s ColonyCore, so downstream consumers only need `import Colony`.

### Runtime Loop

The agent graph (`ColonyAgent.swift`) implements a cyclic state machine:

```
preModel → model → routeAfterModel → tools → toolExecute → preModel
```

The loop runs until the model produces a final answer (no tool calls) or an interrupt fires (e.g. tool approval required).

### Capability-Gated Tool Families

Tools are only injected into the prompt/schema when their corresponding capability is enabled AND a backend is wired:

| Capability       | Tools                                                        | Backend Protocol             |
|-----------------|--------------------------------------------------------------|------------------------------|
| `.planning`     | `write_todos`, `read_todos`                                  | (built-in)                   |
| `.filesystem`   | `ls`, `read_file`, `write_file`, `edit_file`, `glob`, `grep` | `ColonyFileSystemBackend`    |
| `.shell`        | `execute`                                                    | `ColonyShellBackend`         |
| `.scratchbook`  | `scratch_read/add/update/complete/pin/unpin`                 | (built-in, filesystem-backed)|
| `.subagents`    | `task`                                                       | `ColonySubagentRegistry`     |

### Profiles

`ColonyAgentFactory` provides two preset profiles via `ColonyProfile`:

- **`.onDevice4k`** — Strict ~4k token budget. Compaction at 2,600 tokens, summarization at 3,200, tool result eviction at 700 tokens. Scratchbook enabled. Designed for on-device Foundation Models.
- **`.cloud`** — Generous limits (compaction at 12k, summarization at 170k, eviction at 20k). No scratchbook by default.

Both profiles are customizable via the `configure:` closure on `makeRuntime()`.

### Key Types

- `ColonyAgentFactory` — Entry point. Call `makeRuntime()` to get a configured `ColonyRuntime`.
- `ColonyRuntime` — Thin wrapper around `HiveRuntime<ColonySchema>`. Provides `sendUserMessage(_:)` and `resumeToolApproval(interruptID:decision:)`.
- `ColonyConfiguration` — All agent settings (capabilities, approval policy, compaction, summarization, token limits, memory/skill sources).
- `ColonyContext` — Runtime context holding configuration + backend references. Passed as `HiveEnvironment.context`.
- `ColonyAgent` — The compiled `HiveGraph`. The graph definition is in `ColonyAgent.swift`.

### Human-in-the-Loop

Tool approval is controlled by `ColonyToolApprovalPolicy` (`.never`, `.always`, `.allowList(Set<String>)`). When approval is required, the runtime emits an `.interrupted` outcome with `.toolApprovalRequired` payload. Resume with `resumeToolApproval(interruptID:decision:)`.

## Testing Conventions

- Uses **Swift Testing** framework (`import Testing`, `@Test` attribute). No XCTest.
- Tests use scripted mock `HiveModelClient` implementations (e.g. `ScriptedModel`, `ExecuteToolModel`, `TaskToolModel`, `RecordingRequestModel`) that return deterministic responses.
- In-memory backends: `ColonyInMemoryFileSystemBackend`, `InMemoryCheckpointStore`, `RecordingShellBackend`, `RecordingSubagentRegistry`.
- Test targets: `ColonyTests` (core library), `ColonyResearchAssistantExampleTests` (CLI example).

## Example: ColonyResearchAssistantExample

A CLI research assistant at `Sources/ColonyResearchAssistantExample/`. Demonstrates:
- Model resolution (`auto`/`foundation`/`mock` modes)
- Profile selection (`on-device`/`cloud`)
- Interactive REPL with human-in-the-loop tool approval
- Subagent delegation for focused research tasks
