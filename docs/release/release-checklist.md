# Colony Release Checklist

## Goal

Publish a `Colony` GitHub tag that resolves only from published GitHub dependencies, especially the newly released `Swarm` tag.

## Hard Requirement

`Swarm` must be released first. `Colony` should then pin to that exact released `Swarm` version before the Colony tag is cut.

## Agent-Owned Steps

1. Update `Colony/Package.swift` to the exact released `Swarm` tag.
2. Update `Package.resolved`.
3. Run dependency policy validation:
   - `EXPECTED_SWARM_VERSION=<tag> scripts/ci/check-dependency-policy.sh`
4. Run full remote-only verification:
   - `EXPECTED_SWARM_VERSION=<tag> scripts/ci/verify-remote-release.sh`
5. Update changelog and migration notes.

## User-Owned Steps

1. Confirm the final `Swarm` release tag to pin.
2. Push the Colony release branch to GitHub.
3. Create and push the Colony SemVer tag.
4. Publish the GitHub release entry and release notes.

## Pre-Tag Gate

- `Swarm` release is already public.
- `Colony/Package.swift` pins `Swarm` with `exact:`.
- `EXPECTED_SWARM_VERSION=<tag> scripts/ci/check-dependency-policy.sh` passes.
- `EXPECTED_SWARM_VERSION=<tag> scripts/ci/verify-remote-release.sh` passes.
- `swift build` passes.
- `swift test` passes.
- No local path dependency is used unless explicitly opted in for development.

## Tagging Sequence

1. Release `Swarm`.
2. Patch `Colony` to that exact `Swarm` tag.
3. Run remote-only verification.
4. Tag `Colony`.
5. Publish the GitHub release.
