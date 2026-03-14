# Mission-Critical Audit Todo (2026-03-14)

## Plan
- [x] Establish baseline by running `swift build` and targeted/full tests.
- [x] Perform static audit sweep for high-risk patterns (`try!`, force unwraps, concurrency/state hazards, unsafe file/path handling, silent error swallowing).
- [x] Prioritize concrete issues (P0-P2), then write/extend regression tests that fail on current behavior.
- [x] Implement minimal production-grade fixes with protocol/type-safe APIs where beneficial.
- [x] Re-run targeted tests, then full `swift test`, then `swift build` for regression safety.
- [x] Commit changes with detailed message.
- [x] Push branch and open PR with detailed summary.

## Review
- Fixed build-blocking dependency pin by moving Hive from `0.1.2` to `0.1.5` and updating lock/resolution metadata.
- Removed production crash-prone force paths by replacing `try! ColonyVirtualPath(...)` defaults with canonical non-throwing constants.
- Hardened subagent registry graph bootstrap to avoid `preconditionFailure` crash; graph compilation now surfaces as throwable error and is test-injectable.
- Hardened provider budget enforcement under concurrency by introducing actor-backed reservation/finalization to prevent check-then-act oversubscription.
- Hardened harness lifecycle stop semantics by cancelling all active monitor tasks, clearing active run state, and emitting deterministic cancellation once.
- Hardened durable run-state recovery by rebuilding snapshots from event logs when `state.json` is missing/stale.
- Removed remaining production force unwraps in DeepResearchApp UI/client defaults.
- Added regression tests:
  - `DefaultSubagentRegistryTests.defaultSubagentRegistry_surfacesGraphCompilationFailureWithoutCrashing`
  - `TaskEPersistenceProviderObservabilityTests.taskE_providerRouterConcurrentRateCeilingReservation`
  - `TaskEPersistenceProviderObservabilityTests.taskE_durableRunStateRebuildsMissingSnapshot`
- Updated compatibility tests for current approval decision enum semantics (`.rejected` path).
- Adjusted conservative token estimation and message wording to restore strict-budget/summarization/eviction guarantees validated by existing tests.
- Verification:
  - `swift test --filter DefaultSubagentRegistryTests --filter ColonyHarnessSessionTests --filter TaskEPersistenceProviderObservabilityTests` ✅
  - `swift test` ✅ (114 tests, 0 failures)
  - `swift build` ✅
