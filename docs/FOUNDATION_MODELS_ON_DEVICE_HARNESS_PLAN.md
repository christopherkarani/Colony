# Colony Foundation Models + On‑Device Harness Hardening (Immutable)

Date: 2026-02-06
Status: Frozen
Owner: CTO Orchestrator

## Immutability

This document is the authoritative plan for this execution cycle.
It is read-only after creation. Follow-up changes must be captured in a new plan file.

## Goals

1. Integrate Apple Foundation Models as a first-party on-device model option for Colony.
2. Enforce strict request-level context budgeting that accounts for:
   - system prompt
   - conversation messages
   - tool definition payload
3. Ensure subagents inherit the parent on-device budget posture (4k-safe by default).
4. Preserve Colony’s existing tool approval + tool execution semantics (Colony stays in charge of tools).

## Constraints

- Swift 6.2
- Structured concurrency only
- Sendable-first API design
- Swift Testing framework (XCTest only if unavoidable)
- Correctness before optimization

## Non-Goals

- Replacing Colony’s tool system with Foundation Models `Tool.call(arguments:)` execution
- Full Deep Agents parity workstreams beyond the items listed here
- Provider-accurate tokenization (we keep a deterministic approximation suitable for guarding budgets)

## Architecture Decisions

1. Add a typed configuration surface to `ColonyConfiguration`:
   - `requestTokenLimit` (hard cap) for model invocation input
2. Enforce the cap in `ColonyAgent.model(...)` immediately before model invocation:
   - preserve the system message
   - retain newest conversation messages first
   - account for tool definition payload in the budget
3. If tool definitions alone exceed the cap, fail deterministically with a Colony error (hard-to-miss).
4. Fix subagent configuration to derive from the parent `ColonyProfile` defaults:
   - `.onDevice4k` subagents stay 4k-safe
   - `.cloud` subagents stay cloud-appropriate
   - subagents never recurse into additional subagents by default
5. Implement an opt-in Foundation Models model client adapter:
   - `HiveModelClient` conformance
   - streaming support by diffing partial snapshots into token deltas
   - request mapping: Hive messages + tools → Foundation Models instructions/prompt
6. Provide an optional `HiveModelRouter` that prefers on-device Foundation Models when privacy/offline hints demand it.

## Workstreams (This Slice)

### WS-A — Request-Level Budget Enforcement

- Add `requestTokenLimit` to `ColonyConfiguration`.
- Implement deterministic enforcement in `ColonyAgent.model(...)`.
- Add tests for:
  - system prompt accounted for (not just message compaction)
  - tools counted (budget includes tool definitions)
  - oldest trimmed first, newest preserved

### WS-B — Subagent Budget Inheritance

- Thread `ColonyProfile` into `ColonyDefaultSubagentRegistry`.
- Ensure subagent `ColonyConfiguration` derives from `ColonyAgentFactory.configuration(profile:modelName:)`
  with subagent-specific capability gating applied.
- Add test validating subagent request payload stays within 4k defaults under `.onDevice4k`.

### WS-C — Foundation Models Integration (Opt-In)

- Add `ColonyFoundationModelsClient` (available when `canImport(FoundationModels)`).
- Add `ColonyOnDeviceModelRouter` for preference routing (Foundation Models first, cloud fallback).
- Add compilation-only tests that validate:
  - adapter compiles under `canImport(FoundationModels)`
  - router selection is deterministic

## Task → Agent Mapping

- Planning Agent: this immutable plan.
- Implementation Agent (Tests): failing tests for WS-A + WS-B.
- Implementation Agent (Code): implement WS-A + WS-B + WS-C.
- Code Review Agents (2): correctness/type safety/API clarity review.
- Fix/Gap Agent: address review findings and re-run tests.

## Acceptance Criteria

1. Colony enforces an explicit hard cap on request input token count *including system prompt and tools*.
2. Enforcement is deterministic and preserves newest messages under budget.
3. `.onDevice4k` profile defaults to 4k-safe request limits, including for subagents.
4. Foundation Models adapter can be used as a `HiveModelClient` without changing Colony’s tool semantics.

