# Colony On-Device 4k Harness Plan (Immutable)

Date: 2026-02-06
Status: Frozen
Owner: CTO Orchestrator

## Immutability

This document is the authoritative plan for this execution cycle.
It is read-only after creation. Follow-up changes must be captured in a new plan file.

## Goals

1. Enforce strict request-level 4k context budgeting in Colony.
2. Keep API type-safe and hard to misuse.
3. Preserve current behavior for non-4k/cloud profiles unless explicitly configured.
4. Maintain deterministic, testable orchestration behavior.

## Constraints

- Swift 6.2
- Structured concurrency only
- Sendable-first API design
- Swift Testing framework (XCTest only if unavoidable)
- Correctness before optimization

## Non-Goals

- Full cloud sandbox provider surface
- New CLI UX
- Prompt redesign beyond budget-specific truncation/enforcement

## Architecture Decisions

1. Add explicit request budget controls to `ColonyConfiguration`:
   - hard cap for total model request input tokens
2. Enforce budget in `ColonyAgent.model(...)` immediately before `HiveChatRequest` invocation.
3. Keep deterministic trimming strategy:
   - preserve system message
   - retain newest conversation messages first
4. Keep existing compaction/summarization policies as pre-filters; new budget is a final hard guardrail.
5. On-device profile sets a strict default request cap (4k), cloud remains effectively unbounded by default.

## Workstreams

### WS-A: Context Budget Foundation (Current Execution Slice)

- A1: Add typed configuration for hard request input cap.
- A2: Implement deterministic enforcement in model request assembly.
- A3: Add focused tests for cap enforcement and recency retention.
- A4: Validate on-device profile default wiring.

### WS-B: Budget-Aware Compression (Next Slice)

- B1: Fraction-based summarization defaults by model window.
- B2: Tool-argument truncation policy for old tool calls.
- B3: Summary-tag exclusion from re-offload.

### WS-C: On-Device Orchestration Hardening (Next Slice)

- C1: Per-tool HITL interrupt policies.
- C2: Shell/tool output truncation harmonization.
- C3: Skills progressive disclosure tightening.

## Task to Agent Mapping

- Context/Research Agent: completed (gap and parity analysis).
- Planning Agent: this immutable plan.
- Implementation Agent (Tests): failing tests first for WS-A.
- Implementation Agent (Code): WS-A implementation.
- Code Review Agents (2): correctness/type safety/API clarity review.
- Fix/Gap Agent: address review findings and re-run tests.

## Acceptance Criteria for WS-A

1. Colony can enforce an explicit hard cap on request input token count.
2. Enforcement is deterministic and preserves the newest conversation context.
3. On-device profile uses the 4k cap by default.
4. Tests prove behavior and pass.

## Deferred Risks

- Approximate token counting may differ from provider tokenizers.
- Tool definition payload size is not separately budgeted yet.

