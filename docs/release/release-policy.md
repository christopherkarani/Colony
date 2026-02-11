# Release Policy

Last updated: 2026-02-10

## Scope

This policy defines how Colony is versioned, released, and consumed safely in CI.

## Semantic Versioning

Colony follows SemVer (`MAJOR.MINOR.PATCH`).

- `MAJOR`: breaking API or behavior changes.
- `MINOR`: backward-compatible features.
- `PATCH`: backward-compatible fixes/documentation/test-only hardening.

## Dependency Policy

- Legacy sibling path dependencies (for example `../hive/...`) are forbidden.
- Hive is pinned through `HIVE_DEPENDENCY.lock` (URL, tag, revision) and a matching remote pin in `Package.swift`.
- Local fallback (`COLONY_USE_LOCAL_HIVE_PATH=1`) is allowed only for offline/dev workflows and must resolve from `.deps/Hive/Sources/Hive`.
- `Package.resolved` is required and must be reproducible after `swift package resolve`.
- Dependency policy is enforced by `scripts/ci/check-dependency-policy.sh` and CI.

## Hive Tag Assumption

Task F required removing the ad-hoc `../hive` dependency and enforcing pinned dependency sourcing for Hive.

Assumption used on 2026-02-10:
- Hive remote URL: `https://github.com/christopherkarani/Hive.git`
- Pinned tag: `0.1.2`
- Pinned revision: `3074a0e24d6ab9db1f454dc072fa5caba1461310`

Rationale:
- `0.1.2` is the pinned stable semver tag used for reproducible builds.
- Remote SwiftPM pinning removes local checkout drift and aligns dependency checks across developer machines and CI.

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
2. Run `scripts/ci/check-dependency-policy.sh` locally.
3. Update `CHANGELOG.md` and upgrade notes.
4. Create a version tag matching SemVer.
5. Publish release notes aligned with changelog entries.

## Non-Goals

- Floating dependency versions.
- Branch-based dependency references for released code.
- Manual release steps without changelog and CI evidence.
