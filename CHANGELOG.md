# Changelog

All notable changes to this project are documented in this file.

The format is based on Keep a Changelog and this project follows Semantic Versioning.

## [Unreleased]

### Added
- Agent onboarding guide: `docs/AGENTS.md`
- Runtime loop documentation: `docs/runtime-loop.md`
- `README.md` quickstart: added 3 runnable examples (minimal agent, with services, on-device 4k profile)
- `README.md`: added "How Tool Approval Works" explanation section
- `README.md` troubleshooting: clarified `.foundationModels()` availability and service registration
- Release documentation: `docs/release/release-policy.md`, `docs/release/upgrade-flow.md`

### Fixed
- `README.md`: corrected all code examples to use public `Colony.agent(model:)` entry point (was using `package`-internal `ColonyBootstrap`)
- `README.md`: fixed tool name constants (`.readTodos`, `.writeTodos` etc. — was using incorrect snake_case string names)
- `README.md`: fixed model factory call (`.foundationModels()` — was using non-existent `ColonyFoundationModelsClient.isAvailable`)

### Changed
- **API Surface**: Major cleanup reducing public API surface by ~33% and improving type safety
- **Removed `@_exported import ColonyCore`**: ColonyCore types now require explicit `import ColonyCore` (was leaking ~162 types via `import Colony`)
- **Removed `@_exported import Swarm`**: Swarm bridge types moved to separate `ColonySwarmInterop` product
- **`ColonyCapabilities` renamed to `ColonyRuntimeCapabilities`**: Distinguishes from `ColonyModelCapabilities`
- **Swarm bridge types renamed**: `SwarmToolBridge` → `ColonySwarmToolBridge`, `SwarmMemoryAdapter` → `ColonySwarmMemoryAdapter`, etc.
- **ColonySwarmInterop product created**: Swarm bridge types isolated in separate product with proper `ColonySwarm*` prefix
- **Adopted `ColonyToolName`**: `ColonyToolCall.name` and `ColonyToolDefinition.name` now use `ColonyTool.Name` type (was raw `String`)
- **Adopted typed IDs**: `ColonyObservabilityEvent` uses `ColonyHarnessSessionID`/`ColonyThreadID`, `ColonyArtifactRecord` uses `ColonyArtifactID`/`ColonyThreadID`
- **Added `ColonyCheckpointID` and `ColonySubagentType`**: Newtype identifiers for checkpoints and subagent types
- **Nested phantom domains**: `ThreadDomain`, `InterruptDomain` etc. nested under `ColonyID` extension
- **Demoted test doubles to `package`**: 8 in-memory implementations (e.g., `ColonyInMemoryMemoryBackend`) no longer pollute public API
- **Demoted `ColonyDefaultSubagentRegistry` and `ColonyDurableRunStateStore`**: Now `package` access, not public
- **Added `Colony.agent(model:)` entry point**: Public factory method replacing `package`-internal `ColonyBootstrap`
- **Added `@ColonyServiceBuilder` DSL**: Declarative service registration with result builder pattern
- **Added `ColonyInferenceHints` defaults**: `tokenBudget`, `temperature` now have sensible defaults
- **`ColonyRunStateSnapshot.threadID`**: Changed from `String` to typed ID (breaking change)
- **`stop()` visibility fixed**: `ColonyHarnessSession.stop()` changed from `public` to `package`
- `Package.swift`: removed legacy lowercase sibling path (`../hive`) and standardized pinned Hive checkout path via `HIVE_DEPENDENCY.lock` + `scripts/ci/bootstrap-hive.sh`:
  - path now: `.package(path: ".deps/Hive/Sources/Hive")`
- `README.md`: updated setup guidance for pinned Hive checkout bootstrap flow and release/upgrade doc links.
- CI workflow at `.github/workflows/ci.yml` with explicit quality gates
- Dependency policy scripts under `scripts/ci/`

### Notes
- Hive tag `0.1.2` / revision `3074a0e24d6ab9db1f454dc072fa5caba1461310` is pinned in `HIVE_DEPENDENCY.lock`.
- Direct SwiftPM remote pinning is blocked today because Hive's manifest is nested under `Sources/Hive/Package.swift` instead of repository root.
