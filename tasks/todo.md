# Colony Production Readiness Plan

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
