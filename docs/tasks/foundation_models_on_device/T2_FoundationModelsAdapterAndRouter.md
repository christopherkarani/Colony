Prompt:
Add an opt-in Apple Foundation Models `HiveModelClient` adapter and an optional router that prefers on-device execution when privacy/offline hints require it.

Goal:
Enable on-device execution via Foundation Models without changing Colony’s tool execution semantics.

Task Breakdown:
1. Add `ColonyFoundationModelsClient` (guarded by `#if canImport(FoundationModels)`):
   - `HiveModelClient` conformance (`complete` and `stream`)
   - mapping: Hive system prompt + messages + tools → Foundation Models instructions/prompt
   - streaming via `LanguageModelSession.ResponseStream` snapshot diffs → Hive token chunks
2. Add `ColonyOnDeviceModelRouter` (or similar) implementing `HiveModelRouter`:
   - prefers Foundation Models when `privacyRequired == true` or network is offline/metered (configurable)
   - supports fallback to a secondary model client when Foundation Models are unavailable
3. Add compilation-only tests for router determinism (skip if `canImport(FoundationModels)` is false).

Expected Output:
- New adapter/router code in `Sources/Colony`.
- Tests compile and pass across environments (Foundation Models availability gated via `canImport`).

