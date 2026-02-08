# Swarm-Orchestration Migration Plan (Full Cutover)

## Status
- Branch: `codex/swarm-migration`
- Migration mode: **breaking major release**
- Target architecture: **Colony built on top of Swarm**, with **Hive as the only execution core**

## Non-Negotiable Architecture
- `SwiftAgents` (Swarm) is the orchestration surface.
- `Hive` remains the only runtime/execution engine.
- `Colony` becomes product policy + API packaging on top of Swarm.
- No long-lived dual-orchestration runtime is allowed.

## Goals
1. Rebuild Colony orchestration on Swarm primitives.
2. Preserve proven Colony behavior contracts (safety, budgets, isolation, deterministic replay).
3. Ship a major-version breaking release with a clean runtime surface.

## Constraints
- Breaking API changes are allowed.
- Swift 6.2 strict concurrency and Sendable correctness are required.
- Swift Testing framework is mandatory for new tests.
- No implementation phase is complete without green phase-gate tests.

## Explicit Non-Goals
- Maintaining old `ColonyRuntime.sendUserMessage` / `resumeToolApproval` API compatibility in the final release.
- Supporting non-Hive execution backends in Colony.
- Preserving legacy internal orchestration code after parity is proven.

## Required Upstream Primitives in Swarm (Blockers)
These must exist before full Colony cutover:
1. Resumable run control API:
   - run handle IDs
   - interrupt IDs
   - resume entrypoint with typed payload
2. First-class approval interrupt contract:
   - interrupt on approval-required tool paths
   - approve/reject/cancel transitions
3. Strict Hive runtime mode:
   - `requireHive` mode that fails fast if Hive runtime path is unavailable
   - no silent fallback to non-Hive engine when `requireHive` is requested
4. Deterministic identity guarantees:
   - stable interrupt/tool-call/run correlation semantics
5. Hive runtime option passthrough:
   - checkpoint policy
   - thread identity
   - max steps/concurrency/event buffering settings
6. Checkpoint store injection for deterministic resume/replay.

## Behavior Invariants to Preserve in Colony vNext
The following are release blockers:
1. Human approval flow determinism (interrupt/resume correctness).
2. Idempotent resume behavior under duplicate/stale resume attempts.
3. Hard request token-limit enforcement including tool schema payload.
4. Deterministic tool-result eviction semantics.
5. Summarization and history offload behavior contracts.
6. Subagent isolation and recursion guards.
7. Stable client-facing event semantics for interrupt/finish/failure paths.

## Migration Strategy
Use a **strangler-by-domain execution plan** with hard deletion after parity:
- Implement a Swarm-backed domain.
- Achieve parity tests.
- Delete corresponding legacy Colony orchestration path.
- Repeat until no legacy orchestration remains.

This is a full migration, but not a greenfield rewrite without tests.

## Phase Plan

### Phase 0: Contract Freeze
**Objective**
Freeze architecture, risk boundaries, and gate criteria.

**Deliverables**
- This document approved and frozen.
- Explicit breaking-change table.
- Invariant-to-test mapping matrix.

**Exit Criteria**
- Architecture and acceptance gates are immutable for this migration.

---

### Phase 1: Swarm Runtime Capability Closure
**Objective**
Close upstream Swarm gaps required for Colony parity.

**To-Do**
- Add resumable run-control primitives.
- Add approval interrupt/resume APIs.
- Add strict `requireHive` runtime mode and fast-fail behavior.
- Add checkpoint store + Hive options passthrough.
- Add deterministic identity guarantees and tests.

**Exit Criteria**
- Swarm can represent Colony-critical interrupt/resume lifecycle semantics.
- `requireHive` mode verified in CI.

---

### Phase 2: Colony vNext Public API Definition (Breaking)
**Objective**
Define final Colony API on Swarm semantics.

**To-Do**
- Replace legacy runtime methods with Swarm-native run/control APIs.
- Define new event and error contracts.
- Define run handle and approval decision surface.
- Publish migration guide skeleton with old->new mapping.

**Exit Criteria**
- New API compiles.
- Legacy API marked for removal and excluded from new docs.

---

### Phase 3: Test-First Domain Matrix
**Objective**
Lock test-first migration order and failing tests.

**Domain Order**
1. Approval/interrupt/resume
2. Budgeting + context discipline
3. Tool execution + schema/guardrails
4. Subagent handoff/isolation
5. Streaming/event contract
6. Memory/summarization/offload

**To-Do**
- Add failing behavior tests for each domain before implementation.
- Add deterministic replay suite for interrupted/resumed runs.

**Exit Criteria**
- Every migration task has a failing test committed first.

---

### Phase 4: Domain-by-Domain Cutover + Deletion
**Objective**
Migrate runtime internals by behavior domain and remove legacy logic immediately after parity.

**To-Do per domain**
- Implement Swarm-backed path.
- Pass parity + replay + concurrency tests.
- Remove legacy Colony orchestration code for that domain.
- Re-run full suite.

**Exit Criteria**
- No migrated domain retains legacy orchestrator code paths.

---

### Phase 5: Observability and Operational Readiness
**Objective**
Stabilize production telemetry and stream behavior before RC.

**To-Do**
- Standardize event schema versions.
- Ensure trace IDs and run correlation map to Swarm/Hive run-control IDs.
- Add dashboards and alerting for interruptions, resume failures, guardrail triggers, and latency.

**Exit Criteria**
- Operational parity with clear failure diagnostics.

---

### Phase 6: Release Candidate and Cleanup
**Objective**
Ship major release with no legacy orchestration residue.

**To-Do**
- Final API migration cookbook and release notes.
- Remove dead adapters and compatibility shims.
- RC soak tests for long conversations + repeated interrupt/resume cycles.
- Post-RC incident triage checklist.

**Exit Criteria**
- Major release shipped.
- Legacy Colony orchestration internals removed.

## CI and Quality Gates (Fail Closed)
A PR fails if any of the following is false:
1. Swarm runtime in Colony integration runs in `requireHive` mode.
2. Interrupt/resume replay tests are green.
3. Budget + token-limit tests are green.
4. Subagent isolation tests are green.
5. Event contract compatibility tests are green.
6. No legacy-orchestrator files remain for completed domains.

## Risks and Mitigations
1. Approval-flow regressions
   - Mitigation: deterministic replay, idempotency tests, strict interrupt identity.
2. Silent non-Hive fallback
   - Mitigation: `requireHive` runtime gate + CI assertion.
3. Budget regressions
   - Mitigation: hard-limit tests and deterministic budget fixtures.
4. Subagent leakage/recursion
   - Mitigation: adversarial isolation tests and explicit recursion guards.
5. Event contract breakage
   - Mitigation: versioned schema + client contract tests.

## Immediate Week-1 Actions
1. Implement Phase 1 Swarm blocker primitives and tests.
2. Freeze Colony vNext breaking API signatures.
3. Commit failing approval/replay and budget parity tests in Colony.
4. Land first Swarm-backed approval path and delete legacy equivalent.

## Ownership Model
- Swarm maintainers own orchestration/runtime primitives.
- Colony maintainers own product policy, behavior parity, and release contract.
- No plan edits without explicit migration RFC addendum.

## Definition of Done
- Colony orchestration is fully Swarm-surfaced.
- Hive is the only execution path.
- All invariant tests pass under deterministic replay.
- Legacy Colony orchestration code is removed.
- Major-version migration docs are published.
