# Mission-Critical Audit Todo

- [x] Establish baseline: run full test suite and build; capture failures
- [x] Perform focused static audit for correctness/safety gaps in Swift sources
- [x] Implement fixes for identified issues with minimal, production-grade changes
- [x] Add/adjust regression tests (TDD) covering each fix
- [x] Re-run full tests and build to prove no regressions
- [ ] Prepare commit(s), push branch, and create PR with detailed notes

## Review
- Baseline: initial build/test runs were blocked by SwiftPM path/dependency resolution and API skew (`.cancelled` not present in `ColonyToolApprovalDecision`).
- Correctness fixes applied:
  - Removed force-unwrap/force-try crash paths for default virtual path constants and registry graph compilation.
  - Hardened session creation lineage handling to avoid forced unwrap.
  - Hardened DeepResearch URL constants and tool summary rendering against force unwraps.
  - Reworked DeepResearch `ConversationStore` to report IO/encode/decode failures instead of silently swallowing them.
- Regression coverage added/updated:
  - Added tests for default path constants, default audit log prefix writes, and auto-generated session lineage behavior.
  - Updated run-control test flow to align with explicit rejection decision model.
  - Tightened brittle eviction/summarization/context-budget assertions to deterministic invariants.
- Verification:
  - `COLONY_USE_LOCAL_HIVE_PATH=1 swift test` passed.
  - `COLONY_USE_LOCAL_HIVE_PATH=1 swift build` passed.
