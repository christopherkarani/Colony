# Colony On-Device Scratchbook Plan (Immutable)

Date: 2026-02-06
Status: Frozen
Owner: CTO Orchestrator

## Immutability

This document is the authoritative plan for this execution cycle.
It is read-only after creation. Follow-up changes must be captured in a new plan file.

## Goals

1. Add a first-party on-device Scratchbook system for durable notes, todos, and long-running task state.
2. Expose a minimal, misuse-resistant Scratchbook tool surface to the model (CRUD + view + pin/complete).
3. Inject a compact, budgeted Scratchbook view into the system prompt each model turn (4k-safe).
4. When conversation history is offloaded, retain continuity by updating Scratchbook with a compact summary + extracted next actions (subagent-driven when available; deterministic fallback otherwise).
5. Improve effective 4k density by:
   - removing redundant “Tools:” listing from the system prompt when tool definitions are already provided out-of-band, and
   - ensuring tool-result eviction previews respect the configured eviction budget.

## Constraints

- Swift 6.2
- Structured concurrency only
- Sendable-first API design
- Swift Testing framework (XCTest only if unavoidable)
- Offline/on-device only; no network assumptions
- Preserve existing behavior for cloud profile unless explicitly configured

## Non-Goals

- UI for Scratchbook browsing/editing
- Cloud sync / multi-device sync
- Vector search / embeddings (future work; not required for 4k posture)

## Architecture Decisions

### A1. Data model (ColonyCore)

- Add `ColonyScratchbook` (Codable, Sendable) containing an append-only list of `ColonyScratchItem` plus pin metadata.
- Add `ColonyScratchItem` (Codable, Sendable, Identifiable) with:
  - `kind`: `.note | .todo | .task`
  - `status`: `.open | .inProgress | .blocked | .done | .archived`
  - `title`, `body`, `tags`
  - `createdAtNanoseconds`, `updatedAtNanoseconds` for deterministic ordering
  - optional task fields: `phase`, `progress`
- Provide deterministic view rendering (`renderView(...)`) that prioritizes:
  1) pinned items, 2) open/in-progress tasks, 3) open todos, 4) recent notes.

### A2. Storage (ColonyCore + Colony)

- Persist Scratchbook per thread to the configured virtual filesystem backend:
  - path: `{scratchbookPathPrefix}/{sanitizedThreadID}.json`
  - default prefix: `/scratchbook`
- Use JSON with `.sortedKeys` encoding for determinism.
- Store full-fidelity content on disk; only the injected view is budget-trimmed.

### A3. Configuration & budgeting (ColonyCore)

- Add `ColonyScratchbookPolicy` to `ColonyConfiguration`:
  - `pathPrefix`
  - `viewTokenLimit` (on-device default: small, e.g. ~600–900 tokens)
  - `maxRenderedItems` (hard cap to keep view dense)
  - `autoCompact` (optional; default enabled on-device)
- Add `includeToolListInSystemPrompt: Bool` to `ColonyConfiguration`:
  - on-device default: `false`
  - cloud default: `true` (preserve current behavior)

### A4. Tool surface (ColonyCore + Colony)

- Add a dedicated capability gate: `ColonyCapabilities.scratchbook`.
- Add built-in tools (names intentionally short to reduce tool definition overhead):
  - `scratch_read` (returns the compact view)
  - `scratch_add` (create note/todo/task)
  - `scratch_update` (patch item fields by id)
  - `scratch_complete` (mark done)
  - `scratch_pin` / `scratch_unpin` (pin management)
- Tools are implemented as safe, scoped operations over the thread’s Scratchbook file only (no arbitrary file writes).

### A5. System prompt injection (Colony)

- During `ColonyAgent.model(...)`, if Scratchbook is enabled and a filesystem backend exists:
  - load Scratchbook
  - render compact view under `scratchbookPolicy.viewTokenLimit`
  - inject as `Scratchbook:\n...` section into the system prompt.

### A6. Offload + compactor integration (Colony)

- Extend the current “history offload” (`maybeSummarize(...)`) to:
  1) offload history to `/conversation_history/...` as today
  2) update Scratchbook with a compact summary note + next actions
     - preferred: invoke a dedicated “compactor” subagent when subagents are configured
     - fallback: deterministic summary note that references the history file path
- The compactor subagent is isolated (no recursive subagents) and uses Scratchbook tools + read-only filesystem access where possible.

### A7. Tool-result eviction preview budget (Colony)

- Ensure eviction previews returned to the model are capped as a function of `toolResultEvictionTokenLimit` so tool outputs cannot dominate the 4k window.

## Workstreams (Current Execution Slice)

### WS-A: Scratchbook Core + Storage

- Add data model + JSON store helpers.
- Add deterministic view rendering and budget trimming.

### WS-B: Tools + Capability Gating

- Add Scratchbook tool definitions.
- Implement tool execution paths in `ColonyTools.executeBuiltIn(...)`.
- Wire on-device allowlist to include Scratchbook tools.

### WS-C: Prompt Injection

- Inject Scratchbook view into `ColonyPrompts.systemPrompt(...)`.
- Disable redundant tool list in system prompt for on-device by default.

### WS-D: Offload + Compactor

- Add compactor subagent type to the default registry.
- Wire offload trigger to update Scratchbook via compactor (fallback path when unavailable).

### WS-E: 4k Density Fixes

- Make tool eviction preview budget-aware.

## Task to Agent Mapping

- Task Decomposition Agent: create `.md` tasks for WS-A…WS-E.
- Implementation Agents (Tests): write failing Swift Testing tests first for each workstream.
- Implementation Agents (Code): implement per task files without deviation.
- Code Review Agents (2–3): correctness/type safety/API clarity; concurrency/storage integrity; budget behavior.
- Fix/Gap Agent: address review findings; run `swift test`.

## Acceptance Criteria (Current Slice)

1. Scratchbook tools can create/update/read/pin/complete items and persist per thread via filesystem backend.
2. System prompt injects a compact Scratchbook view within configured token budget.
3. Offloaded conversation history results in Scratchbook continuity (compactor path when available; deterministic fallback otherwise).
4. On-device profile defaults include Scratchbook enabled and tool-list-in-system-prompt disabled.
5. Tool eviction previews do not exceed the configured eviction budget (and are covered by tests).

