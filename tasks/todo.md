# Mission-Critical Audit TODO

- [x] Load automation memory + establish session memory context
- [x] Baseline quality: run test suite and package build
- [x] Audit failures and high-severity correctness risks
- [x] Add/adjust tests that reproduce each issue first (TDD)
- [x] Implement production-grade fixes with minimal scope
- [x] Re-run full tests and verify clean build
- [x] Commit with detailed message
- [ ] Push branch and open PR

## Review
- Fixed dependency pinning breakage by updating Hive pin from `0.1.2` (no root `Package.swift`) to `0.1.5`.
- Migrated `HiveRuntime` construction call sites to throwing initializer semantics.
- Restored explicit `.cancelled` tool-approval semantics and deterministic cancellation messaging.
- Hardened provider router with atomic budget admission and stream-task cancellation on termination.
- Removed crash-on-compile failure path in default subagent registry by surfacing a typed runtime error.
- Added parser edge-case tests for Foundation Models tool-call parsing boundary.
- Verification complete: `swift build` and `swift test` pass.
- Branch pushed: `automation/check-frameworks-audit-20260310`.
- PR creation blocked in this environment: `gh` token for `christopherkarani` is invalid (`gh auth status`).
