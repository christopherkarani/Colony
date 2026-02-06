# Deep Agents → Colony Closure Plan (On‑Device 4k First)

Date: 2026-02-06

This plan is a companion to `docs/DEEP_AGENTS_PARITY.md`. It is intended to drive the remaining work needed for “Deep Agents parity” while optimizing for **on‑device ~4k context** and keeping a path open for **cloud**.

## Goals

1. **Correctness parity** with Deep Agents harness semantics:
   - tool-call validity (no dangling tool_call_id)
   - safe interrupt/resume behavior
   - large tool result eviction + recoverability
2. **On‑device usability** with a ~4k context window:
   - bounded system prompt + injected memory/skills
   - bounded tool outputs (eviction + previews)
   - bounded conversational history (summarize/offload)
3. **Cloud future-proofing**:
   - higher step limits and looser budgets when desired
   - backend abstractions that can map to sandbox providers + upload/download later

## Constraints

- Swift 6.2, `Sendable`-first, structured concurrency only.
- Type safety + API clarity over cleverness.
- No “infinite prompt” defaults: on-device profile must stay 4k-safe by design.

## Non‑Goals (for this phase)

- Full Deep Agents CLI parity (remote sandboxes, web search, interactive UX).
- Exact prompt-text parity with LangChain middleware templates.

## Current State (baseline)

- P0 correctness implemented in Colony:
  - dangling tool-call patching (Deep Agents’ `PatchToolCallsMiddleware`)
  - tool rejection emits cancellation tool messages that close tool_call_id
  - large tool results evicted to `/large_tool_results/{tool_call_id}` when filesystem exists
- On-device support exists via:
  - `ColonyAgentFactory` presets (`.onDevice4k`, `.cloud`)
  - `preModel` runs before every model turn (including after tool results)

## Workstreams

### WS1 — Human-in-the-loop (HITL) parity (P0)

Deep Agents exposes `interrupt_on` per-tool. Colony currently supports a global approval policy.

**To implement**
- Add a per-tool config surface, e.g.:
  - `ColonyToolApprovalPolicy.interruptOn(Set<String>)`
  - (optional) richer config later (allow edits / reason strings)
- Ensure interrupt payloads remain stable and minimal (4k-friendly).

**Files**
- `Sources/ColonyCore/ColonyToolApproval.swift`
- `Sources/Colony/ColonyAgent.swift`
- `Sources/ColonyCore/ColonyInterrupts.swift`
- Tests in `Tests/ColonyTests/*`

### WS2 — Summarization parity (P0/P1)

Deep Agents generates **LLM summaries** and offloads full history to `/conversation_history/{thread}.md`.
Colony currently offloads history + inserts an in-context marker, but does not generate summaries.

**To implement**
- Extend `ColonySummarizationPolicy` to support a strategy:
  - `.markerOnly` (on-device default option)
  - `.modelGenerated(modelName?, prompt?, maxInputTokens?, maxSummaryTokens?)` (cloud default option)
- Add incremental summary update semantics (use prior summary + new transcript chunk).
- Add optional truncation of large tool arguments in *offloaded* history to keep the history file readable.

**Files**
- `Sources/ColonyCore/ColonySummarizationPolicy.swift`
- `Sources/Colony/ColonyAgent.swift`
- `Sources/ColonyCore/ColonyTokenizer.swift`
- Tests: add model-stubbed summary generation tests + regression for repeated summarization events.

### WS3 — Backend parity & routing (P1/P2)

Deep Agents has a unified backend protocol covering filesystem, execution, upload/download, plus a composite router.
Colony currently has separate filesystem/shell backends and a filesystem-only composite router.

**To implement**
- Define a unified backend protocol *or* expand existing ones:
  - upload/download APIs (batch + structured errors)
  - shell sandbox lifecycle hooks (optional)
- Add a composite router for **shell execution** (longest-prefix routing like filesystem).
- Decide whether these are:
  - Hive-level (generic to any graph), or
  - Colony-level (Deep Agents–specific harness needs).

**Files**
- `Sources/ColonyCore/ColonyFileSystem.swift`
- `Sources/ColonyCore/ColonyShell.swift`
- `Sources/ColonyCore/ColonyCompositeFileSystemBackend.swift`
- (Potential) `../hive/...` changes if routing belongs in Hive.

### WS4 — Skills parity (P1)

Deep Agents’ SkillsMiddleware injects a progressive disclosure guide and validates frontmatter.
Colony injects metadata-only skills, and now includes a minimal progressive-disclosure hint in the base prompt.

**To implement**
- Add lightweight validation for frontmatter (name/description length; optional “name matches directory” warning).
- Optional: support `allowed_tools` → feed into tool approval defaults for safer on-device behavior.
- Add source layering semantics (“last one wins”) if we add override behavior in Swift.

**Files**
- `Sources/Colony/ColonyAgent.swift` (frontmatter parsing + discovery)
- `Sources/ColonyCore/ColonyPrompts.swift`

### WS5 — Cloud future + SwiftAgents (Swarm) integration (P2)

Deep Agents uses LangChain for middleware. In Swift, SwiftAgents can play the role of a “tool + agent composition layer”.

**To evaluate**
- Where Colony should integrate with SwiftAgents (if at all):
  - tool registry bridging
  - subagent stacks as reusable “agent presets”
  - structured output helpers
- Keep on-device profile lean; cloud profile can afford heavier defaults.

## Task → Agent Mapping (for execution)

When implementing this plan, use a Tier‑2 orchestration flow:
- **Context/Research agent**: confirm Deep Agents behavior for the workstream.
- **Planning agent**: produce a focused task breakdown per workstream.
- **Implementation agent(s)**: implement tests first, then code.
- **Code review agent(s)**: validate parity + on-device 4k budgets.
- **Fix/gap agent**: resolve review findings until green.

