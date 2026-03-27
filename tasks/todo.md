# Current Execution: Colony on Public Swarm 0.5.0 Only

- [x] Audit `Colony` and `Swarm` git state, dependency pins, and interrupted local changes.
- [x] Confirm `Colony` stays pinned to published `Swarm 0.5.0` and declares no direct `Hive` package dependency.
- [x] Reject the earlier local-`Swarm` SPI bridge approach as the wrong end state for this task.
- [x] Start migrating `ColonyCore` request/message/tool bridges onto public `Swarm` provider types (`InferenceMessage`, `InferenceResponse`, `ToolSchema`, `TokenUsage`, `SendableValue`).
- [x] Finish `ColonyCore` cleanup and remove all remaining non-public `Swarm*` runtime/type references from `Sources/ColonyCore`.
- [x] Rework provider-facing `Colony` model clients and routers to use `ColonyInferenceRequest` / `ColonyInferenceResponse` plus public `Swarm` provider protocols only.
- [x] Replace graph-runtime-centric `Colony` execution APIs with Colony-owned session/turn/interruption/checkpoint types built on public `Swarm` APIs only.
- [x] Preserve approval, denial, interruption, durable checkpoint, and resume semantics inside Colony without relying on Swarm graph runtime internals.
- [x] Update harness and persistence integrations to the Colony-owned runtime model.
- [x] Migrate tests from removed `Hive*` / non-public `Swarm*` symbols to the new Colony-owned or public-Swarm types.
- [x] Verify `swift package resolve`, `swift build`, and `swift test` in remote mode with `COLONY_USE_LOCAL_SWARM_PATH=0 AISTACK_USE_LOCAL_DEPS=0 CONDUIT_SKIP_MLX_DEPS=1`.
- [x] Grep final build and test logs for compiler `warning:` / `error:` noise and clear them.
- [x] Re-run dependency and API leakage audits to confirm no direct `Hive` dependency and no new public Hive leakage.

### Review Notes for Current Execution

- Published `Swarm 0.5.0` exposes provider/session/agent APIs, but not the graph runtime/checkpoint/interruption types Colony had been depending on.
- The production fix is therefore a Colony-owned runtime rewrite on top of public `Swarm`, not another internal `Swarm` bridge.
- Local `Swarm` modifications are intentionally out of scope for this execution path.
- The remaining multi-turn regressions were fixed by persisting Colony-owned thread snapshots across runs inside `ColonyRuntimeEngine`, which restored summarization/history offload and strict recency trimming behavior.
- Final remote-oriented verification passed against published `Swarm 0.5.0`: `swift package resolve`, `swift build`, and `swift test` all succeeded with no `warning:` or `error:` matches in the final logs.
- Final audits passed: no direct `Hive` package dependency in `Colony`, no `Hive*` or `AnyHive*` source references in `Colony`, no public Hive leakage across `Swarm` and `Colony`, and no remaining `@_spi(ColonyInternal) import Swarm` in `Colony` production sources.

# Colony Production Readiness Plan

## Current Execution: Colony -> Swarm 0.5.0 Runtime Migration

- [ ] Audit current `Colony` and `Swarm` state, including dirty files and the untracked `Swarm/Sources/Swarm/ColonyInternalSupport.swift` partial change.
- [ ] Replace this plan section with the final review once implementation and verification finish.
- [ ] Inventory every remaining `Hive*` / `AnyHive*` dependency in `Colony` sources and tests.
- [ ] Confirm `Colony/Package.swift` stays pinned to `Swarm 0.5.0` and does not declare a direct `Hive` package dependency.
- [ ] Determine whether `Colony` can migrate to existing `Swarm 0.5.0` public APIs only, or whether a minimal Swarm-owned SPI is required for Colony's durable graph runtime.
- [ ] If Swarm support is required, replace the interrupted partial file with a minimal Swarm-owned SPI surface that hides Hive from public API/source checks.
- [ ] Migrate `ColonyCore` inference/message/ID bridges off direct `Hive*` types onto Swarm-owned types.
- [ ] Migrate `Colony` runtime, run control, builder/bootstrap, model router, and graph agent internals off direct `Hive*` usage onto Swarm-owned types.
- [ ] Migrate `Colony` tests off direct `Hive*` imports/usages where the Swarm-owned replacement exists.
- [ ] Remove any temporary or redundant compatibility layer that would preserve public/publicly-visible Hive leakage.
- [ ] Verify local `Swarm` build/test if the Swarm package changed.
- [ ] Verify remote-oriented `Colony` resolve/build/test with `COLONY_USE_LOCAL_SWARM_PATH=0 AISTACK_USE_LOCAL_DEPS=0 CONDUIT_SKIP_MLX_DEPS=1`.
- [ ] Grep final verification logs for `warning:` and `error:`.
- [ ] Re-run Hive leakage audits across `Swarm` and `Colony` and confirm no new public Hive leakage remains.

### Review Notes for Current Execution

- Audit findings before implementation:
- `Colony` is already pinned to `Swarm 0.5.0`, but source and tests still reference dozens of removed Hive-shaped runtime symbols directly.
- `Colony` has local uncommitted changes in `Package.swift`, `Package.resolved`, and this file; those must be preserved while applying the migration.
- `Swarm` has an untracked `Sources/Swarm/ColonyInternalSupport.swift` partial change. It currently looks like a broad SPI typealias dump and must be validated or replaced rather than assumed correct.
- The required verification bar is zero direct `Hive` package dependency in `Colony`, green build/test, zero compiler warnings, and no new public Hive leakage in either framework.

## Current Execution: Swarm 0.5.0 Compatibility Check

- [ ] Repoint `Colony` from `Swarm 0.4.7` to `Swarm 0.5.0`.
- [ ] Refresh `Package.resolved` in remote-only mode.
- [ ] Run remote-only `swift build` and fix any API or dependency breakage.
- [ ] Run remote-only `swift test` and fix any regressions until green.
- [ ] Confirm final verification logs contain no compiler warnings.

### Review Notes for Current Execution

- Triggered on 2026-03-27 after `Swarm 0.5.0` was published.
- Goal for this pass: prove `Colony` still compiles and tests cleanly against the new released Swarm tag.
- Scope is compatibility verification and any required fixes inside `Colony`; no unrelated refactors.

## Current Execution: Production Dependency Policy

- [x] Audit package manifests for production-default local dependency behavior.
- [x] Remove automatic local-path fallback from `Colony/Package.swift`; local `Swarm` usage is now explicit opt-in via `COLONY_USE_LOCAL_SWARM_PATH=1`.
- [ ] Verify `Swarm` and `Colony` build/test cleanly in production dependency mode with zero warnings.

### Review Notes for Current Execution

- Published GitHub tags are the production source of truth.
- Local package paths remain available only for explicit iteration workflows and must never be auto-selected in released manifests.
- The previous `Colony` manifest behavior of preferring `../Swarm` whenever it existed was invalid for production because it leaked monorepo assumptions into downstream consumption.
- Current release blocker: the published `Membrane` and `Conduit` manifests still pull `mlx-swift`, `mlx-swift-lm`, and `mlx-swift-examples` during dependency resolution, so a full remote-source verification cannot pass until fixed tags are released upstream.

## Current Execution: Hide Hive from Public API

- [ ] Freeze the target boundary: `Swarm` is the only public dependency for `Colony`; `HiveCore` and `SwarmHive` become implementation details only.
- [ ] Inventory every public Hive-shaped symbol in `Swarm` and `Colony` and classify each as `replace with Swarm-owned type`, `replace with Colony-owned type`, `make internal`, or `delete`.

### Phase 1 — Collapse the Public Bridge Product

- [ ] Move the implementation currently under `Swarm/Sources/Swarm/HiveSwarm` into the main `Swarm` target under an internal-only namespace/path.
- [ ] Stop excluding `HiveSwarm` from the `Swarm` target once the files are relocated or merged.
- [ ] Keep `HiveCore` imports only in internal implementation files that back the Swarm runtime bridge.
- [ ] Delete `Swarm/Sources/Swarm/HiveSwarm/HiveCoreReexports.swift`.
- [ ] Remove `@_exported import HiveCore` from `Swarm/Sources/Swarm/Swarm.swift`.
- [ ] Remove the `SwarmHive` product and target from `Swarm/Package.swift`.
- [ ] Update `Swarm` tests to import `Swarm` only, except for test-only direct `HiveCore` fixtures where internal bridge behavior is being asserted.

### Phase 2 — Define Swarm-Owned Runtime Abstractions

- [ ] Introduce Swarm-owned public types/protocols for the runtime surface currently leaking Hive types.
- [ ] Replace public `Hive*`-typed request/response/message/tool abstractions with Swarm-owned equivalents or wrappers.
- [ ] Replace public run/checkpoint/event/interrupt identifiers exposed by `Swarm` with Swarm-owned identifiers.
- [ ] Keep Hive-backed engines, codecs, checkpoints, and workflow adapters internal to `Swarm`.
- [ ] Audit `Swarm/Sources/Swarm/Workflow/*` and any other non-bridge files that still import `HiveCore`; reduce those imports to internal-only implementation boundaries.

### Phase 3 — Rebase Colony onto Swarm Only

- [ ] Remove `@_exported import SwarmHive` from `Colony/Sources/Colony/Colony.swift`.
- [ ] Remove all `import SwarmHive` statements from `Colony` sources and tests.
- [ ] Change `Colony/Package.swift` so public Colony targets depend on `Swarm` only, not `SwarmHive`.
- [ ] Replace all public Hive-shaped Colony APIs with Colony-owned or Swarm-owned abstractions.
- [ ] Rework `ColonyBuilder`, `ColonyRuntime`, `ColonyRunControl`, `ColonyRuntimeSurface`, routers, model clients, tool definitions, interrupt payloads, and typed IDs so no public signature mentions `Hive*` or `AnyHive*`.
- [ ] Restrict any temporary compatibility shims to internal or package scope; do not preserve Hive-shaped public aliases.

### Phase 4 — Cleanup and Surface Audit

- [ ] Remove any remaining public Hive exposure from `ColonyCore`, `ColonyControlPlane`, and shared support modules.
- [ ] Confirm `Swarm` no longer re-exports Hive and no longer ships a discoverable `SwarmHive` product.
- [ ] Confirm users of `Colony` and `Swarm` can build without importing `HiveCore` or knowing Hive exists.
- [ ] Update docs and migration notes to reflect the new public runtime surface.

### Verification

- [ ] `rg -n "@_exported import HiveCore|@_exported import SwarmHive" Swarm/Sources Colony/Sources` returns no matches.
- [ ] `rg -n "\\.library\\(name: \\\"SwarmHive\\\"|name: \\\"SwarmHive\\\"" Swarm/Package.swift` returns no matches.
- [ ] `rg -n "public .*Hive|public typealias .*Hive|open .*Hive" Swarm/Sources Colony/Sources -g '*.swift'` returns no public Hive-shaped API.
- [ ] `rg -n "^import SwarmHive$" Colony/Sources Colony/Tests -g '*.swift'` returns no matches.
- [ ] `cd Swarm && swift build && swift test` passes with zero warnings.
- [ ] `cd Colony && swift build && swift test` passes with zero warnings.

### Review Notes for This Execution

- Hiding Hive from the public API and hiding `SwarmHive` from the package graph are separate tasks; the latter only becomes possible once Colony stops importing `SwarmHive`.
- The execution order is fixed: first fold the bridge into `Swarm`, then replace public types, then remove the product, then rebase `Colony`.
- This is a breaking API migration. Preserving raw public Hive-shaped APIs would directly conflict with the goal.

## Current Execution: Colony on Swarm

- [x] Write the implementation plan and freeze the dependency-inversion goal.
- [x] Repoint `Colony` package dependencies from `Hive` to `Swarm`.
- [x] Move Colony source imports off direct `HiveCore` usage and onto the `Swarm` package bridge.
- [x] Re-export the Hive boundary from `Swarm` so existing Colony runtime types continue to compile during the migration.
- [x] Update Colony tests to compile without a direct `Hive` package dependency.
- [x] Run targeted Colony builds and the isolated Colony test-target build.
- [x] Run the broader package test suite after removing the unrelated `DeepResearchApp` package targets.

## Review Notes for Current Execution

- Scope for this pass: dependency inversion first, not a full public API redesign.
- Success condition for this pass: `Colony` no longer declares a direct `Hive` package dependency and compiles through `Swarm`.
- Follow-up work may still be needed to fully eliminate Hive-shaped public Colony APIs, but not to remove the direct package dependency.
- `Colony` now depends on `Swarm` products instead of a direct `Hive` package reference; the compatibility surface currently flows through `SwarmHive`.
- Verified locally: `swift build --target Colony`, `swift build --target ColonyCore`, `swift build --target ColonyTests`, and `swift build --target Swarm`.
- The previous package-wide blocker was the unrelated `DeepResearchApp` target graph; the app target graph and source/test tree are now removed so verification is Colony-only.

## Scope
Prepare Colony for external production release with stable API guarantees, runtime safety, and operational readiness on iOS 26+ / macOS 26+.

## Plan

- [ ] Phase 0 — Define GA Criteria
- [ ] 1) Publish production definition: external consumer support scope, compatibility targets, failure budget, and acceptance criteria.
- [ ] 2) Add a release gate section in `docs/release/release-policy.md` with explicit GA criteria.
- [ ] 3) Identify owners per phase and freeze the risk acceptance matrix.

- [ ] Phase 1 — Public API Boundary Hardening
- [ ] 4) Replace public Hive-domain identifiers in core artifacts with Colony domain types.
- [ ] 4a) Update `Sources/Colony/ColonyArtifactStore.swift` signatures:
- [ ] 4b) `threadID` and `runID` should use Colony typed IDs.
- [ ] 4c) Update `ColonyArtifactRecord` fields to typed IDs where available.
- [ ] 5) Fix `Sources/Colony/ColonyDurableRunStateStore.swift`:
- [ ] 5a) `appendEvent` should accept Colony thread types, not `HiveThreadID`.
- [ ] 5b) `ColonyRunStateSnapshot.threadID` should be a typed Colony ID.
- [ ] 6) Audit public API for internal type leakage and deprecate or remove accidental internals.
- [ ] 6a) `Sources/Colony/ColonyDefaultSubagentRegistry.swift` should not expose Hive-typed public inits.
- [ ] 6b) Reclassify test-only in-memory public implementations as internal/package.
- [ ] 7) Tighten observability IDs in `Sources/Colony/ColonyObservability.swift` to typed IDs.
- [ ] 8) Add typed aliases or wrappers for remaining high-risk stringly fields (`toolName`, `threadID`, etc.).

- [ ] Phase 2 — Concurrency and Runtime Safety
- [ ] 9) Remove/replace `@unchecked Sendable` in `Sources/ColonyCore/ColonyHardenedShellBackend.swift`.
- [ ] 10) Make shell session state handling explicitly thread-safe.
- [ ] 11) Add deterministic process timeout/kill cleanup and output truncation assertions.
- [ ] 12) Validate cancellation and interruption behavior for all tool execution paths.

- [ ] Phase 3 — Subagent and Tooling Contract Stability
- [ ] 13) Define stable subagent request/result model with constrained types where appropriate.
- [ ] 14) Finalize service protocol migration in `Sources/ColonyCore/ColonySubagents.swift` and update deprecation strategy.
- [ ] 15) Ensure subagent type list is validated through typed constants/enums or dedicated namespace types.
- [ ] 16) Verify tool registration names and tool-call payloads remain stable under schema tests.

- [ ] Phase 4 — Governance and Compatibility
- [ ] 17) Set framework version to a non-placeholder SemVer in `Sources/Colony/Colony.swift`.
- [ ] 18) Add migration notes for breaking changes and deprecated shims.
- [ ] 19) Update `CHANGELOG.md` with breaking changes, migration guidance, and rollout notes.
- [ ] 20) Regenerate API surface docs (`docs/reference/`) from code and remove stale references.

- [ ] Phase 5 — Validation and Release Gate
- [ ] 21) Add explicit GA gate checks in CI.
- [ ] 22) Ensure `swift test`, contract, e2e approval, and security checks pass in protected release branch.
- [ ] 23) Run dependency policy and lockfile reproducibility checks in release pipeline.
- [ ] 24) Add a smoke runbook: bootstrap, build, run sample, recover from interrupted run, resume.
- [ ] 25) Define rollback and support playbook for public consumers.

## Success Criteria
- [ ] No public API surface requires importing `HiveCore`/`Swarm` to use baseline runtime.
- [ ] No public function in `Colony`/`ColonyCore` exposes raw internal IDs where typed IDs exist.
- [ ] No `@unchecked Sendable` remains in public runtime classes without documented proof.
- [ ] 1.0 release candidate approved by migration/compatibility review.

## Review
- [ ] Final architecture/API review completed with explicit sign-off.
- [ ] Release readiness memo created (scope, risks, rollback path, SLIs).
- [ ] GA decision made with acceptance checklist complete.
