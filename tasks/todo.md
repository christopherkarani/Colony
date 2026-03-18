# Swarm/Wax Compatibility Recovery

- [x] Commit the current dirty tree as a baseline checkpoint.
- [x] Run focused Swarm integration tests and capture the concrete failures.
- [x] Fix `ColonyAgentFactory` capability wiring for `swarmTools`.
- [x] Harden `SwarmToolBridge` and expose the bridge capability union needed by the factory.
- [x] Harden `SwarmMemoryAdapter` for generic memory backends and add a persistent-backend convenience initializer.
- [x] Update Swarm integration fixtures/tests to the current Swarm API.
- [x] Run full verification: focused Swarm tests, full `swift test`, and explicit executable builds.

## Review

- Swarm was pinned to `0.4.0` to restore Wax compatibility while keeping the newer `SwarmHive` era API surface.
- `SwarmToolBridge`, `SwarmMemoryAdapter`, and factory capability normalization now match current Swarm/Hive expectations and preserve explicit user capability removals.
- `ColonyToolApprovalDecision.cancelled` was restored end-to-end because Colony runtime/tests still depend on distinct cancellation semantics.
- `DeepResearchApp` structured insights extraction now uses JSON decoding from `LanguageModelSession.respond(to:)`, avoiding the `FoundationModels`/`Conduit` `@Generable` collision.
- Verification completed successfully with `swift test`, `swift build --target ColonyResearchAssistantExample`, and `swift build --target DeepResearchApp`.
