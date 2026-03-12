# Mission-Critical Audit Plan (2026-03-12)

## Checklist
- [x] Baseline current health: run `swift build` and full `swift test`
- [x] Perform focused static audit for correctness/safety gaps (concurrency, error paths, boundary conditions)
- [x] Identify dead/unused code with potential production value and decide keep/remove actions
- [x] Implement fixes with TDD (add/adjust tests first where gaps exist)
- [x] Re-run targeted tests for each fix, then full test suite
- [x] Ensure build compiles cleanly
- [x] Commit changes with detailed message
- [ ] Push branch and open PR

## Review
- Restored broken dependency resolution by re-pinning Hive to `0.1.5` and updating lock metadata.
- Removed process-kill behavior in subagent registry graph bootstrap by surfacing compile failures as typed runtime errors.
- Hardened harness stream reliability and failure transparency:
  - synchronous subscriber registration to eliminate event-loss race
  - stream consumers now receive runtime failures
  - durable run-state failures are no longer silently dropped
  - failed runs are persisted with explicit `.failed` phase.
- Eliminated production `try!` crash vectors around virtual path defaults.
- Restored cancellation semantics for tool approvals (including Codable compatibility) and preserved cancellation-specific messaging.
- Restored regression-sensitive output text for large-tool eviction and summarization marker expectations.
- Tightened request hard-token budget behavior with conservative padding to keep oldest-message trimming deterministic.
- Hardened DeepResearch conversation persistence:
  - write/delete/load operations throw on storage failures
  - corrupt conversation files are quarantined
  - UI model captures persistence errors instead of silently reporting success.
- Validation:
  - `swift build` ✅
  - `swift test --filter DefaultSubagentRegistryTests --filter ColonyHarnessSessionTests` ✅
  - `swift test` ✅ (113 tests passed)
