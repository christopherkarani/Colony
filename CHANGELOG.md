# Changelog

All notable changes to this project are documented in this file.

The format is based on Keep a Changelog and this project follows Semantic Versioning.

## [Unreleased]

### Added
- CI workflow at `.github/workflows/ci.yml` with explicit quality gates for:
  - `swift test`
  - protocol contract tests
  - E2E approve/deny/resume tests
  - security tests
- Dependency policy scripts under `scripts/ci/`:
  - `check-dependency-policy.sh`
  - `run-contract-tests.sh`
  - `run-e2e-tests.sh`
  - `run-security-tests.sh`
- Release documentation:
  - `docs/release/release-policy.md`
  - `docs/release/upgrade-flow.md`

### Changed
- `Package.swift`: removed legacy lowercase sibling path (`../hive`) and standardized pinned Hive checkout path via `HIVE_DEPENDENCY.lock` + `scripts/ci/bootstrap-hive.sh`:
  - path now: `.package(path: ".deps/Hive/Sources/Hive")`
- `README.md`: updated setup guidance for pinned Hive checkout bootstrap flow and release/upgrade doc links.

### Notes
- Hive tag `0.1.5` / revision `4b52f38d014bf5610a53069ec8af62b918c5d00d` is pinned in `HIVE_DEPENDENCY.lock`.
- Direct SwiftPM remote pinning is enabled with the pinned `0.1.5` Hive release.
