# Mission-Critical Audit TODO

- [x] Baseline build/test to capture current failures
- [x] Audit core Swift modules for correctness/safety defects
- [x] Implement production-grade fixes for identified defects
- [x] Add/adjust tests to prevent regressions (TDD red->green intent)
- [ ] Run full test suite and verify clean compile (blocked by disk capacity: errno 28)
- [ ] Commit, push, and open PR with detailed notes (deferred until successful verification)

## Review
- Fixed invalid Hive dependency pin (`0.1.2` -> `0.1.7`) causing package resolution failure.
- Fixed compile breaks from throwing `HiveRuntime` initializers.
- Tightened filesystem normalization to reject traversal segments only (not benign `a..b`).
- Hardened shell timeout/cancel path to terminate descendant process trees.
- Improved provider router by atomically reserving budget and forwarding stream tokens.
- Added regression tests for virtual path normalization, shell timeout child cleanup, stream forwarding, and failed-attempt budgeting.
- Verification is currently blocked by local disk exhaustion (`errno=28`) during build/link.
