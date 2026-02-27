# Framework Audit Todo (2026-02-27)

## Plan
- [x] Reconfirm repository state and branch status
- [x] Run baseline verification (`swift build`, `swift test`) and capture failures
- [x] Triage findings by severity (P0/P1 first)
- [x] Implement fixes with targeted tests first (TDD)
- [ ] Re-run full tests and build to verify no regressions
- [ ] Commit changes with detailed message
- [ ] Push branch and open/update PR

## Review
- P0 fixed: `Package.swift` no longer depends on a non-buildable remote Hive root manifest; it now consumes `.deps/Hive/Sources/Hive` deterministically.
- CI/developer scripts updated to match policy (`bootstrap-hive.sh`, `check-dependency-policy.sh`) and to support offline runners (skip only lockfile reproducibility when dependency hosts are unreachable).
- Documentation updated for the new bootstrap-first Hive flow (`README.md`, release docs, changelog).
- Verification blocker: host volume has very limited free space and SwiftPM build currently fails with `error: other(28)` (ENOSPC).
