# Changelog

All notable changes to this project are documented in this file.

The format is based on Keep a Changelog and this project follows Semantic Versioning.

## [Unreleased]

### Breaking Changes
- **API Hardening**: All public APIs now use Colony domain types instead of HiveCore types
  - `ColonyArtifactStore.put()` and `.list()` now accept `ColonyThreadID` and `ColonyRunID` instead of `HiveThreadID`/`HiveRunID`
  - `ColonyDurableRunStateStore.appendEvent()` now accepts `ColonyThreadID` instead of `HiveThreadID`
  - `ColonyObservabilityEvent` now uses `ColonyThreadID`, `ColonyRunID`, and `ColonyHarnessSessionID` instead of raw strings/UUID
  - `ColonyRunStateSnapshot` now uses `ColonyThreadID` and `ColonyRunID` instead of `String`/`UUID`
  - `ColonyArtifactRecord` now uses `ColonyArtifactID`, `ColonyThreadID`, and `ColonyRunID` instead of `String`/`UUID`
- **Subagent Types**: `ColonySubagentRequest.subagentType` is now `ColonySubagentType` instead of `String`
- **Access Control**: `ColonyDefaultSubagentRegistry` is now `package` access (was `public`)
  - Consumers should use `ColonySubagentRegistry` protocol or factory methods

### Migration Guide
1. Replace `HiveThreadID` with `ColonyThreadID` (use `.hiveThreadID` property to convert if needed)
2. Replace `HiveRunID` with `ColonyRunID` (use `.hiveRunID` property to convert if needed)
3. Replace raw string IDs with typed equivalents:
   - Thread IDs: `ColonyThreadID(rawValue: string)` or `ColonyThreadID.generate()`
   - Run IDs: `ColonyRunID(rawValue: uuid.uuidString)` or use conversion extensions
4. Replace subagent type strings with `ColonySubagentType` constants (`.general`, `.compactor`, etc.)

### Added
- `ColonyArtifactID` typed ID for artifact identifiers
- `ColonySubagentType.compactor` constant
- `Sendable` conformance documentation for `ColonyHardenedShellBackend`

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
