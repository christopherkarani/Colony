# Release Policy

Last updated: 2026-03-26

## Scope

This policy defines how Colony is versioned, released, and consumed safely in CI and from GitHub tags.

## Semantic Versioning

Colony follows SemVer (`MAJOR.MINOR.PATCH`).

- `MAJOR`: breaking API or behavior changes.
- `MINOR`: backward-compatible features.
- `PATCH`: backward-compatible fixes/documentation/test-only hardening.

## Dependency Policy

- Released Colony builds must resolve `Swarm` from GitHub, not from a sibling checkout.
- Local fallback (`COLONY_USE_LOCAL_SWARM_PATH=1`) is allowed only for local iteration and must never be the production default.
- Before a Colony release tag is cut, `Package.swift` must pin `Swarm` with `exact:` to the newly released `Swarm` tag.
- `Package.resolved` is required and must be reproducible after `swift package resolve` in remote-only mode.
- Dependency policy is enforced by `scripts/ci/check-dependency-policy.sh` and the release verification script.

## Release Ordering

- `Swarm` releases first.
- `Colony` then updates to that exact released `Swarm` tag.
- `Colony` is tagged only after remote-only verification passes against that published `Swarm` release.

## Changelog and Upgrade Notes

Every release must update `CHANGELOG.md` with:
- Summary of changes.
- Breaking changes (if any).
- Migration/upgrade notes.

If a release has no user-facing API changes, state that explicitly.

## Release Checklist

1. Ensure branch is green in CI:
   - `swift test`
   - contract tests
   - E2E approve/deny/resume tests
   - security tests
2. Run `EXPECTED_SWARM_VERSION=<tag> scripts/ci/check-dependency-policy.sh` locally.
3. Run `EXPECTED_SWARM_VERSION=<tag> scripts/ci/verify-remote-release.sh`.
4. Update `CHANGELOG.md` and upgrade notes.
5. Create a version tag matching SemVer.
6. Publish release notes aligned with changelog entries.

## GA Criteria

Before Colony reaches 1.0 GA, the following must be complete:

### API Stability
- [ ] No public API surface requires importing `HiveCore` to use baseline runtime
- [ ] All public IDs use `ColonyID<Domain>` or typealiases (no raw String IDs)
- [ ] No `@unchecked Sendable` in public runtime classes without documented proof
- [ ] All test-only implementations demoted to `package` access

### Testing & Validation
- [ ] `swift test` passes with 80%+ coverage
- [ ] Contract tests pass (`scripts/ci/run-contract-tests.sh`)
- [ ] E2E approve/deny/resume tests pass (`scripts/ci/run-e2e-tests.sh`)
- [ ] Security tests pass (`scripts/ci/run-security-tests.sh`)

### Documentation
- [ ] CHANGELOG.md updated with all breaking changes and migration notes
- [ ] API reference docs regenerated (`docs/reference/`)
- [ ] Migration guide published for any breaking changes

### Release Infrastructure
- [ ] Version set to non-placeholder SemVer in `Colony.swift`
- [ ] CI green on protected release branch
- [ ] Dependency lockfile reproducibility verified
- [ ] Colony pins the exact released `Swarm` tag

## Non-Goals

- Floating dependency versions on a release branch.
- Branch-based dependency references for released code.
- Manual release steps without changelog and CI evidence.
- Releasing Colony before the dependent Swarm tag exists.
