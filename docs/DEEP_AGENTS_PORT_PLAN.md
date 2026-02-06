# DeepAgents → Colony (Swift) Port Plan

Date: 2026-02-06

This plan is the execution companion to `docs/DEEP_AGENTS_PARITY.md`.

## Goals

1. **Behavioral parity** with the Deep Agents Python library (`deepagents-master-2/libs/deepagents/deepagents/`) for the default “batteries-included” harness.
2. **Swifty API parity**: a single top-level factory comparable to `create_deep_agent(...)` that produces a ready-to-run agent.
3. **Correct-by-construction tool calling** across real providers (no invalid message histories, deterministic tool loop).
4. **On-device first**: safe defaults for iOS/macOS, capability-gated tooling, clear extension points.

## Non-goals (initially)

- Reproducing Deep Agents CLI feature parity in the `Colony` library target itself (treat as a separate executable/module).
- Provider-specific middleware parity (e.g. Anthropic prompt caching) unless it is required for correctness or first-class UX.

## Reference Baseline (Python)

Primary references:
- `deepagents/graph.py` (factory, middleware stack ordering, defaults)
- `deepagents/middleware/*` (filesystem eviction, summarization + offload, memory, skills, subagents, tool-call patching)
- `deepagents/backends/*` (backend protocol, composite routing, sandbox providers)

## Architecture Decision (Swift)

- **Hive** is the LangGraph analog: typed graph compilation + deterministic runtime + checkpoints + interrupts + event streaming.
- **Colony** is the Deep Agents analog: a batteries-included harness built as a Hive graph with:
  - default tool suite
  - pre-model “middleware-like” behavior
  - tool loop + tool result handling
  - HITL interrupts + resume
- **SwiftAgents (Swarm)** is the LangChain analog **only where it adds leverage**:
  - tool definitions + parameter schemas
  - optional tool registry interoperability
  - (potentially) a higher-level agent authoring UX

## Workstreams & Milestones

### Workstream A — Colony Parity (Library)

#### P0 — Correctness & Protocol Validity

**A0. Dangling tool-call patching** ✅ (implemented; parity follow-ups remain)
- Reference: `deepagents/middleware/patch_tool_calls.py`
- Why: Many tool-calling providers require every assistant tool call to be followed by a corresponding tool-result message; rejecting/cancelling tool execution must still “close” tool calls.
- Colony changes:
  - Add a “patch tool calls” pass before model invocation.
  - Ensure the “rejected tool approval” path emits cancellation tool messages (one per tool call id).
  - Ensure cancellation tool messages are deterministic and id-stable.
- Hive changes:
  - Allow `run(threadID:input:)` with a pending interrupt by treating new input as “cancel interrupt and restart graph”.
- Tests (Swift Testing):
  - Rejection path produces tool messages for each tool call id.
  - Patched histories remain stable across resume.

**A1. Large tool result eviction** ✅ (implemented; parity follow-ups remain)
- Reference: `deepagents/middleware/filesystem.py` (`/large_tool_results/{tool_call_id}`)
- Colony changes:
  - Current: fixed eviction threshold (~20k tokens ≈ 80k chars) in tool execution; if tool output exceeds threshold and filesystem is available:
    - write full content to `/large_tool_results/<sanitized-tool-call-id>`
    - replace tool message content with preview + file reference
  - Follow-up: make eviction threshold configurable and match Deep Agents preview formatting more closely.
- Tests:
  - Large tool output writes file and replaces tool message content.
  - Eviction is skipped when filesystem is absent.

**A2. Per-tool HITL configuration (+ optional edits)**
- Reference: `interrupt_on` in `deepagents/graph.py` + `HumanInTheLoopMiddleware`
- Colony changes:
  - Replace/extend `ColonyToolApprovalPolicy` to support per-tool configs (at minimum: `approve`, `interrupt`, `disable`).
  - Extend resume payload to optionally accept modified tool call arguments (editing) or per-call approval decisions.
- Tests:
  - Only configured tools interrupt.
  - Resume with modified tool call arguments executes modified call deterministically.

**A3. Deep Agents step/recursion default**
- Reference: `.with_config({"recursion_limit": 1000})` in `deepagents/graph.py`
- Colony changes:
  - `ColonyAgentFactory` (see A7) sets `HiveRunOptions(maxSteps: 1000)` by default for parity.

#### P1 — Behavioral Parity (“Batteries Included”)

**A4. `AGENTS.md` memory loader** ✅ (implemented)
- Reference: `deepagents/middleware/memory.py`
- Colony changes:
  - Add config for memory sources: `[ColonyVirtualPath]` or `[String]`.
  - Load at startup (or before first model call), concatenate in a stable order, and inject into the system prompt.
  - Follow-up: bound memory size (token or byte cap) and surface truncation clearly in the prompt.
- Tests:
  - Loads multiple sources; missing files are non-fatal (parity with Deep Agents).
  - Injected memory appears in the system prompt for model request.

**A5. Skills loader (SKILL.md) + progressive disclosure** ✅ (metadata + discovery implemented; disclosure guidance TBD)
- Reference: `deepagents/middleware/skills.py`
- Colony changes:
  - Add config for skill sources: directories containing subdirectories with `SKILL.md`.
  - Parse YAML frontmatter (`name`, `description`).
  - Inject skill catalog metadata into system prompt (without body).
  - Follow-up: source layering/override semantics + stronger progressive-disclosure instructions (read skill body only when needed).
- Tests:
  - YAML parsing and validation behaviors.
  - Source layering + override semantics.

**A6. Summarization + history offload** ✅ (history offload implemented; summary text parity TBD)
- Reference: `deepagents/middleware/summarization.py` (`/conversation_history/{thread_id}.md`)
- Colony changes:
  - Add `ColonySummarizationPolicy` (trigger, keep, offload path prefix).
  - When triggered, offload evicted messages to file, then replace with a single “summary” message + preserved recent tail.
  - Prefer deterministic formatting and stable, append-only history files.
  - Follow-up: generate an actual summary (LLM-based) instead of a marker-only summary message.
- Tests:
  - Trigger summarization; verifies file append; verifies messages are compacted into summary + tail.

**A7. First-class factory API**
- Reference: `create_deep_agent(...)`
- Colony changes:
  - Add a single entry point (suggestion): `ColonyAgentFactory.createDeepAgent(...)` that returns a ready-to-run wrapper:
    - compiled graph
    - `HiveRuntime`
    - default `HiveRunOptions` (maxSteps parity, checkpoint policy, buffer size)
    - stable default tools, prompts, and policies
  - Preserve low-level escape hatches (`ColonyAgent.compile` remains available).
- Tests:
  - Factory produces a runnable agent with default tools enabled when backends exist.

**A8. First-party subagent manager** ✅ (minimal default `general-purpose` implemented; parity follow-ups remain)
- Reference: `deepagents/middleware/subagents.py` + default general-purpose subagent built in `deepagents/graph.py`
- Colony changes:
  - Provide a default `ColonySubagentRegistry` implementation that spins up subagents as Colony/Hive runs with:
    - isolated context window policies
    - optional skills/memory stack
    - state filtering rules (do not leak private state between agents)
- Tests:
  - `task` tool routes to the correct subagent and returns only a single tool result message.

**A9. Composite backend routing (prefix dispatch)** ✅ (filesystem routing implemented; execution routing TBD)
- Reference: `deepagents/backends/composite.py`
- Colony changes (two options; pick one):
  1) Add `ColonyCompositeFileSystemBackend` routing by `ColonyVirtualPath` prefix.
  2) Introduce a unified `ColonyBackend` protocol that covers filesystem + execution and provide a `Composite` implementation.
- Tests:
  - Longest-prefix match routing.
  - Root listing shows virtual route directories (optional parity).

### Workstream B — Hive Enhancements (LangGraph-like primitives)

These are not strictly required for Colony’s harness (Colony already has a custom loop), but they reduce duplication and make Hive a better “LangGraph replacement”.

**B0. Streaming-first model component**
- Add a `ModelStreamTurn` (or extend `ModelTurn`) that uses `stream(...)` and emits `.modelToken` events.

**B1. Tool loop component**
- Add a reusable “agent turn” component that detects tool calls, runs them via `HiveToolRegistry`, appends tool messages, and iterates until stable (bounded).

**B2. Checkpoint inspection/editing**
- Provide APIs to load the latest checkpoint and apply typed external writes, enabling HITL “state edits” workflows.

**B3. Long-term store abstraction**
- Deep Agents can persist via `StoreBackend`; Hive currently has checkpoint persistence but no general “store”.
- Add a minimal `HiveStore` protocol (namespaces, get/put/search) with an implementation backed by Wax or the filesystem.

### Workstream C — CLI & Ecosystem Parity (Optional Module)

Deep Agents’ README describes CLI extras (resume, web search, remote sandboxes, persistent memory, skills, HITL approvals). Treat this as a separate deliverable.

**C0. `ColonyCLI` executable**
- Add a Swift CLI target that:
  - resumes threads from checkpoints
  - runs with HITL approvals and displays tool-call diffs
  - supports skills + memory sources

**C1. Sandbox providers**
- Provide a lifecycle interface comparable to `SandboxProvider` (list/get-or-create/delete).
- Implement at least a local sandbox backend; remote providers can follow later.

**C2. MCP tool adapters**
- Deep Agents supports MCP through LangChain adapters; provide Swift equivalents via `HiveToolRegistry` or SwiftAgents tooling.

**C3. Observability exporters**
- Export Hive event stream into OpenTelemetry (or an equivalent) and document recommended spans/events.

## Acceptance Criteria (“Perfect Port” Definition)

- A single factory creates a runnable agent with the Deep Agents default tool suite when backends are provided.
- Rejecting/cancelling tool calls never produces an invalid message history for tool-calling providers.
- Large tool outputs are automatically evicted to files with stable references.
- Summarization offloads history to a file per thread and preserves a usable summary in-context.
- `AGENTS.md` memory and `SKILL.md` skills are discovered/loaded and reflected in the system prompt deterministically.
- Subagents exist out-of-the-box with a “general-purpose” default and predictable isolation semantics.
