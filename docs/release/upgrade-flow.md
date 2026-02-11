# Upgrade Flow

Last updated: 2026-02-10

## For Colony Maintainers

1. Review `CHANGELOG.md` and classify the next release (`MAJOR`/`MINOR`/`PATCH`).
2. Validate dependency policy:
   - `scripts/ci/check-dependency-policy.sh`
   - `scripts/ci/bootstrap-hive.sh`
3. Run targeted quality gates:
   - `scripts/ci/run-contract-tests.sh`
   - `scripts/ci/run-e2e-tests.sh`
   - `scripts/ci/run-security-tests.sh`
4. Run full suite:
   - `swift test`
5. Tag and publish release notes.

## For Colony Consumers

1. Update Colony version in your `Package.swift`.
2. Run:
   - `swift package resolve`
   - `swift test`
3. Read upgrade notes in `CHANGELOG.md`.
4. Apply any migration steps called out for your current and target versions.

## Dependency Update Guardrails

- Keep dependencies reproducible with committed `Package.resolved`.
- Keep Hive pin metadata in `HIVE_DEPENDENCY.lock` (URL/tag/revision) in sync with `Package.swift`.
- Use `COLONY_USE_LOCAL_HIVE_PATH=1` only for offline/local fallback workflows (with `.deps/Hive/Sources/Hive` bootstrapped).
- Avoid local path dependencies for Hive in released code.
