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
- Hive tag `0.1.2` / revision `3074a0e24d6ab9db1f454dc072fa5caba1461310` is pinned in `HIVE_DEPENDENCY.lock`.
- Direct SwiftPM remote pinning is blocked today because Hive’s manifest is nested under `Sources/Hive/Package.swift` instead of repository root.
