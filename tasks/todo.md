# Mission-Critical Audit Todo (2026-03-08)

## Plan
- [x] Capture baseline (`swift build`, `swift test`) and log failing targets/tests.
- [x] Audit critical Swift modules for correctness gaps, dead code, and unsafe flows.
- [x] Add/adjust tests first for each confirmed issue (TDD).
- [x] Implement production-grade fixes with minimal blast radius.
- [x] Re-run targeted tests after each fix.
- [x] Run full regression suite (`swift test` + `swift build`).
- [x] Commit with detailed message, push branch, and open PR.

## Notes
- Prior automation memory referenced a different path with no package; this run is in a valid Swift package with tests.
- Severity policy: prioritize P0/P1 correctness and safety before maintainability/perf.

## Review
- Baseline failures:
  - Compile break from Hive API evolution: `HiveRuntime(...)` now throws and call sites lacked `try`.
  - Stale decision enum usage: `.cancelled` no longer exists in `ColonyToolApprovalDecision`.
  - Behavioral regressions in runtime markers and budget trimming surfaced by tests:
    - Tool-result eviction marker text mismatch.
    - Summarization marker text mismatch.
    - Strict request budget retained older turns longer than expected.
- Fixes applied:
  - Added `try` to all `HiveRuntime(...)` construction sites in production and tests.
  - Updated research assistant approval prompt/decision mapping to approved/rejected only.
  - Updated run-control test to validate rejected path with current semantics.
  - Restored stable marker phrases for eviction/summarization.
  - Added conservative hard-budget padding in request budgeting to preserve recency-first trimming under approximation drift.
  - Excluded `Tests/ColonyResearchAssistantExampleTests/CLAUDE.md` from test target to remove build warning.
- Verification:
  - `COLONY_USE_LOCAL_HIVE_PATH=1 swift test` passed: 111 tests.
  - `COLONY_USE_LOCAL_HIVE_PATH=1 swift build` passed.
  - PR opened: https://github.com/christopherkarani/Colony/pull/8 (base: `develop`)
