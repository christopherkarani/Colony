# Colony Release Policy

**Effective**: 2026-03-22
**Versioning**: Semantic Versioning (SemVer)

---

## Versioning Strategy

Colony follows **Semantic Versioning** (`MAJOR.MINOR.PATCH`):

| Increment | When |
|----------|------|
| **MAJOR** | Breaking changes to public API |
| **MINOR** | New backward-compatible public API |
| **PATCH** | Backward-compatible bug fixes |

### Current Status

Colony is currently in **pre-1.0** (`0.x.y`). Until 1.0.0:
- MINOR versions may include breaking changes
- The API is not yet considered stable

### Stability Guarantee

After 1.0.0:
- MAJOR version = no breaking API changes
- MINOR version = new APIs, deprecated APIs with migration path
- PATCH version = bug fixes only

---

## Breaking Change Policy

A **breaking change** is any change that causes existing code to fail to compile or produce different behavior without modification.

### Examples of Breaking Changes

**Breaking:**
- Removing a public type, method, or property
- Changing a method signature (parameters, return type)
- Renaming a public type or function
- Changing enum case names or associated values
- Changing default values of public parameters
- Removing or changing `Sendable` conformance
- Changing protocol requirement signatures

**NOT Breaking:**
- Adding new optional parameters with defaults
- Adding new methods to protocols (if default implementations exist)
- Adding new enum cases (if exhaustiveness is not required)
- Adding new typealias
- Internal implementation changes

---

## Deprecation Policy

### Deprecation Timeline

When a public API is deprecated:

1. **Deprecation announcement** — API marked with `@available(*, deprecated, message: "...")`
   - Message includes migration instructions
   - Message includes target replacement API

2. **Minimum grace period** — 2 minor versions
   - e.g., deprecated in 1.3 → removed no earlier than 1.5

3. **Removal** — In specified minor version

### Deprecation Format

```swift
@available(*, deprecated, renamed: "NewAPI")
public typealias OldAPI = NewAPI

// Or for methods:
@available(*, deprecated, message: "Use newMethod() instead. Removed in 2.0.")
public func oldMethod() { ... }
```

---

## Hive Dependency Policy

Colony pins to a specific **Hive revision**, not a version tag.

### Why Revision Pinning?

Hive's Swift Package Manager manifest is nested under `Sources/Hive/Package.swift` rather than at the repository root. This prevents standard SwiftPM remote pinning. Colony uses a two-file approach:

1. `HIVE_DEPENDENCY.lock` — stores the pinned revision
2. `scripts/ci/bootstrap-hive.sh` — checks out Hive at the pinned revision

### Updating Hive

When updating Hive dependency:

1. **Always update both files together**:
   ```bash
   # Update the revision in HIVE_DEPENDENCY.lock
   # Then run bootstrap
   ./scripts/ci/bootstrap-hive.sh
   ```

2. **Test before committing**:
   ```bash
   swift test
   ```

3. **Document the change** in CHANGELOG.md under `### Changed`:
   ```
   - Hive: updated pin from `OLD_REVISION` to `NEW_REVISION`
   ```

### Hive Release Cadence

- Hive uses its own versioning (independent of Colony)
- Colony pins to specific revisions, not versions
- Check `HIVE_DEPENDENCY.lock` for current pin

---

## Public API Definition

The **public API** consists of:

- Types marked `public` in `Sources/Colony/`, `Sources/ColonyCore/`, `Sources/ColonyControlPlane/`, `Sources/ColonySwarmInterop/`
- `import Colony` and `import ColonyCore` symbols
- Protocol requirements
- Public typealiases

**NOT part of public API:**
- `package` access types (internal)
- `internal` access types
- Test code in `Tests/` directories
- Private types and functions

---

## Module Structure

Colony consists of 4 products:

| Product | Import | Public API Surface |
|--------|--------|-------------------|
| Colony | `import Colony` | Runtime, entry points, `ColonyRuntime` |
| ColonyCore | `import ColonyCore` | Protocols, policies, types |
| ColonySwarmInterop | `import ColonySwarmInterop` | Swarm bridge types |
| ColonyControlPlane | `import ColonyControlPlane` | Session/project management |

> **Note**: `import Colony` does NOT automatically expose ColonyCore types. You must `import ColonyCore` separately.

---

## Release Process

### Release Checklist

1. Update `CHANGELOG.md` with all changes since last release
2. Update version in `Colony.swift`: `public static let version = "X.Y.Z"`
3. Run full test suite: `swift test`
4. Update `HIVE_DEPENDENCY.lock` if Hive was updated
5. Tag the release: `git tag -a vX.Y.Z -m "Release X.Y.Z"`
6. Push tags: `git push --tags`

### Pre-Release Testing

Before any release (especially major):

- [ ] Full test suite passes
- [ ] API compatibility verified (no breaking changes without version bump)
- [ ] CHANGELOG.md updated
- [ ] Documentation updated if needed
- [ ] Migration guide created for breaking changes

---

## Experimental APIs

APIs marked `@_experimental` may change at any time without notice. Do not use experimental APIs in production code.

```swift
@_experimental public func experimentalFeature() { ... }
```

---

## Contact

For questions about this policy, open an issue on the Colony GitHub repository.
