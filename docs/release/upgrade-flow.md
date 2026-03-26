# Upgrade Flow

Last updated: 2026-03-26

## For Colony Maintainers

1. Review `CHANGELOG.md` and classify the next release (`MAJOR`/`MINOR`/`PATCH`).
2. Release `Swarm` first and note the exact tag to consume from Colony.
3. Update `Colony/Package.swift` to that exact `Swarm` tag.
4. Validate dependency policy:
   - `EXPECTED_SWARM_VERSION=<tag> scripts/ci/check-dependency-policy.sh`
   - `EXPECTED_SWARM_VERSION=<tag> scripts/ci/verify-remote-release.sh`
5. Run targeted quality gates:
   - `scripts/ci/run-contract-tests.sh`
   - `scripts/ci/run-e2e-tests.sh`
   - `scripts/ci/run-security-tests.sh`
6. Run full suite:
   - `swift test`
7. Tag and publish release notes.

## For Colony Consumers

1. Update Colony version in your `Package.swift`.
2. Run:
   - `swift package resolve`
   - `swift test`
3. Read upgrade notes in `CHANGELOG.md`.
4. Apply any migration steps called out for your current and target versions.

## Dependency Update Guardrails

- Keep dependencies reproducible with committed `Package.resolved`.
- Keep the `Swarm` dependency aligned between `Package.swift` and `Package.resolved`.
- Use `COLONY_USE_LOCAL_SWARM_PATH=1` only for explicit local iteration workflows.
- Avoid local path dependencies in released code.
