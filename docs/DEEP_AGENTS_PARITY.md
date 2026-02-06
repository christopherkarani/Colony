# Colony ↔ Deep Agents Parity Audit

Scope:
- Deep Agents reference: `deepagents-master-2/libs/deepagents/deepagents/`
- Colony reference: `Sources/Colony` + `Sources/ColonyCore`
- Hive reference (Swift): `../hive/libs/hive/Sources/HiveCore`
- Date: 2026-02-06
- Closure plan: `docs/DEEP_AGENTS_PLAN.md`

## Reference Map (Python → Swift)

Deep Agents is a thin factory (`create_deep_agent`) that wires a default middleware stack around a LangGraph graph.
Colony is the Swift harness graph itself (built on Hive) with capability-gated built-in tools and an interrupt/resume path.

| Deep Agents (Python) | Responsibility | Colony/Hive (Swift) | Notes |
|---|---|---|---|
| `deepagents.graph.create_deep_agent` | single “batteries-included” factory returning a compiled graph | `ColonyAgentFactory.makeRuntime(...)` + `ColonyAgent.compile(...)` | ✅ Colony now ships a first-party factory with on-device/cloud presets. |
| `TodoListMiddleware` | todo list state + tools | `ColonySchema.Channels.todos` + `write_todos` / `read_todos` | Implemented. |
| `FilesystemMiddleware` | filesystem tools + dynamic prompt; filters `execute` if backend can’t run it; evicts large tool results | `ColonyBuiltInToolDefinitions` + `ColonyFileSystemBackend` | Tools implemented; large-tool-result eviction implemented (minimal parity). |
| `SubAgentMiddleware` | `task` tool; invokes compiled subagents; isolates/filters shared state | `ColonySubagentRegistry` + `task` tool + `ColonyDefaultSubagentRegistry` | Default “general-purpose” subagent now ships; still missing multi-subagent config + full Deep Agents state filtering surface. |
| `SummarizationMiddleware` | auto-summarization + history offload to backend | `ColonySummarizationPolicy` + pre-model offload | Implemented: history offload + in-context marker. Still missing LLM-generated summary text parity. |
| `PatchToolCallsMiddleware` | patches dangling tool calls by inserting tool-cancellation messages | `ColonyAgent.preModel` patching + Hive interrupt cancellation | Implemented: patches missing tool results; Hive also allows new input to cancel a pending interrupt. |
| `MemoryMiddleware` | loads `AGENTS.md` sources and injects into system prompt | `ColonyConfiguration.memorySources` + prompt injection | Implemented (filesystem-backed). |
| `SkillsMiddleware` | loads `SKILL.md` sources; progressive disclosure; injects skill metadata into prompt | `ColonyConfiguration.skillSources` + SKILL frontmatter parsing | Implemented: discovery + metadata-only injection (no body). Progressive-disclosure instructions still minimal vs Deep Agents. |
| `CompositeBackend` | route backends by virtual path prefix | `ColonyCompositeFileSystemBackend` | Implemented for filesystem (not execution). |

## Feature Parity Matrix

| Area | Deep Agents | Colony | Status |
|---|---|---|---|
| Harness graph loop (`model -> tools -> model`) | ✅ | ✅ | ✅ |
| Planning tools (`write_todos`, `read_todos`) | ✅ | ✅ | ✅ |
| Filesystem tools (`ls`, `read_file`, `write_file`, `edit_file`, `glob`, `grep`) | ✅ | ✅ | ✅ |
| Shell execution (`execute`) | ✅ | ✅ (via injected `ColonyShellBackend`) | ⚠️ partial |
| Subagent task delegation (`task`) | ✅ | ✅ (via injected `ColonySubagentRegistry`) | ⚠️ partial |
| Human-in-the-loop tool interrupt | ✅ (`interrupt_on` per tool) | ✅ (`ColonyToolApprovalPolicy`) | ⚠️ partial |
| Prompt defaults for tool usage | ✅ | ✅ | ⚠️ less complete |
| Context summarization middleware | ✅ | ✅ | ⚠️ partial |
| Offload large tool output to files | ✅ | ✅ | ⚠️ partial |
| Patch dangling tool calls on resume/interrupt | ✅ | ✅ | ✅ |
| Memory loading from `AGENTS.md` | ✅ | ✅ | ✅ |
| Skills loading from `SKILL.md` sources | ✅ | ✅ | ⚠️ partial |
| Backend routing/composition by path prefix | ✅ (`CompositeBackend`) | ✅ (filesystem only) | ⚠️ partial |
| Sandbox provider lifecycle (list/create/delete) | ✅ | ❌ | ❌ |
| Upload/download file APIs for backends | ✅ | ❌ | ❌ |
| Single factory API (`create_deep_agent`) | ✅ | ✅ (`ColonyAgentFactory`) | ⚠️ partial |
| Model recursion/step limit default | ✅ (`recursion_limit=1000`) | ✅ (cloud preset `maxSteps=1000`) | ⚠️ partial |

## Detailed Notes

### Implemented in Colony

- Base harness with deterministic message reducer and tool execution loop.
- `preModel` runs before every model turn (including after tool results) to enforce patching + summarization + compaction under small context windows.
- Capability-gated built-in tools:
  - planning + filesystem
  - shell (`execute`)
  - subagent delegation (`task`)
- On-device friendly primitives:
  - `ColonyInMemoryFileSystemBackend`
  - `ColonyDiskFileSystemBackend` with root restriction
- Tool approval interrupt + resume path.

### Partial (close, but not equivalent)

- `execute`: Colony supports shell through dependency injection, but does not yet ship:
  - a default sandbox implementation
  - remote/local sandbox lifecycle management
- `task`: Colony delegates through registry but does not yet include:
  - built-in “general-purpose” subagent orchestration stack
  - compiled subagent spec pipeline matching Deep Agents defaults
- Tool approvals: Colony supports global policy, not per-tool `interrupt_on` configuration.
- System prompt guidance is intentionally minimal vs Deep Agents’ long-form operational instructions.
- Colony currently supports streaming tokens (`HiveModelClient.stream(...)`), but Hive’s DSL `ModelTurn` is `complete(...)`-only. This matters if we want a reusable “Deep Agents style” component outside Colony itself.

### Missing (material parity gaps)

- Summarization parity: LLM-generated summary content (current implementation offloads history + adds marker).
- Skill progressive disclosure parity: guidance + safe “read skill body only when needed” semantics.
- Composite backend parity beyond filesystem: execution + upload/download.
- A single high-level builder API equivalent to `create_deep_agent(...)`.

## Correctness Watchlist (must-fix for “real providers”)

1. **Dangling tool calls**: If an assistant message contains tool calls and we reject/cancel execution, many providers require tool result messages for each tool call ID.
2. **Large tool outputs**: Tool results can exceed provider context limits; eviction/offload prevents compaction from dropping critical context.

Status (2026-02-06):
- ✅ Dangling tool calls are patched by inserting cancellation tool messages before model invocation.
- ✅ Rejecting tool execution emits tool messages that close each pending tool call ID.
- ✅ Large tool outputs are evicted to `/large_tool_results/{tool_call_id}` when filesystem is available.

## Priority Closure Plan (On-Device First)

### P0 — Safety and Correctness

1. ✅ Add `ColonyAgentFactory.makeRuntime(...)` with stable defaults and explicit config points.
2. Add per-tool interrupt configuration (not just global approval mode).
3. ✅ Add dangling tool-call patching before model invocation.
4. ✅ Add large tool-output eviction to `/large_tool_results/...` via filesystem backend.
5. ✅ Add summarization channel + offload history snapshots.

### P1 — Deep Agents Behavioral Parity

6. ✅ Add `AGENTS.md` memory loader and prompt injection.
7. ✅ Add skills loader (`SKILL.md` metadata, source layering, selection guidance).
8. ✅ Add a first-party subagent manager with default “general-purpose” subagent.
9. ✅ Add composite backend routing with prefix-based dispatch.

### P2 — Platform Completeness

10. Add default shell backend strategy:
    - macOS: process-backed shell backend with strict limits.
    - iOS: disable shell by default (capability off) and require explicit custom backend.
11. Expand backend protocol to include upload/download and structured operation errors.
12. Optional: add a `ColonyCLI` executable target matching the Deep Agents CLI surface (resume, web search, sandbox providers, persistent memory, skills).

## Current Verdict

- Colony covers core harness execution and major built-in tool categories.
- Colony is significantly closer to Deep Agents parity (P0 + key P1 middleware behaviors implemented).
- Main missing surface is: per-tool HITL config parity, richer backend ecosystem (sandbox providers, upload/download), and stronger summarization (LLM summary) parity.
