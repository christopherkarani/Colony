# Colony PicoClaw Runtime Migration Notes

## API Design Summary

Colony now includes a PicoClaw-oriented runtime surface under `ColonyGateway*` types:

- Providers:
  - `ColonyProviderProfile`
  - `ColonyProviderSelection` (per-run override + fallback chain + model override)
  - `ColonyProviderRegistry` / `ColonyInMemoryProviderRegistry`
  - `ColonyProviderError` (typed failure categories)
  - `ColonyConduitProviderFactory`
  - `ColonyGatewayRuntime.makeBatteriesIncludedConduitRuntime(...)`
- Tools:
  - `ColonyToolDefinition` (typed schema + risk + timeout + async capability)
  - `ColonyToolResultEnvelope` (success, payload, error, artifacts, attempts, duration, request id)
  - `ColonyRuntimeToolRegistry` (stable registration extension point)
  - `ColonyStandardToolCatalog` (filesystem/shell/web/messaging/cron/state-memory categories)
- Execution policy:
  - `ColonyExecutionPolicy`
  - `ColonyDeterministicCommandValidator`
  - `ColonyPolicyAwareFileSystemBackend`
  - `ColonyPolicyAwareShellBackend`
- Persistence:
  - `ColonyRuntimeSessionStore` + durable/in-memory implementations
  - `ColonyRuntimeCheckpointStore` + durable/in-memory adapters
  - `ColonyRuntimeStateMigrator` schema migration contract
- Runtime orchestration:
  - `ColonyGatewayRuntime`, `ColonyGatewayRunRequest`, `ColonyGatewayRunHandle`
  - `ColonyRuntimeEventBus` + ordered structured `ColonyRuntimeEvent`
  - `ColonySpawnRequest`, `ColonySpawnResult`, `ColonySubagentHandle`
  - `ColonyMessageSink` routing abstraction
  - `ColonySchedulerBridge` (optional scheduling module)

## Minimal PicoClaw-Style Initialization

```swift
import Colony

let runtime = try await ColonyGatewayRuntime.makeBatteriesIncludedConduitRuntime(
    providerProfiles: [
        ColonyProviderProfile(
            name: "openai",
            model: "gpt-5-mini",
            apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
            metadata: ["provider": "openai"]
        ),
        ColonyProviderProfile(
            name: "openrouter",
            model: "openai/gpt-5-mini",
            apiKey: ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"],
            metadata: ["provider": "openrouter"]
        ),
    ],
    defaultProviderName: "openai",
    fallbackProviderNames: ["openrouter"],
    executionPolicy: ColonyExecutionPolicy(
        restrictToWorkspace: true,
        workspaceRoot: try ColonyVirtualPath("/workspace"),
        blockedCommandRules: [.regex(#"(^|\\s)rm\\s+-rf"#)],
        maxStdoutBytes: 64 * 1024,
        maxRuntimeMilliseconds: 30_000
    ),
    sessionStore: try ColonyJSONRuntimeSessionStore(
        baseURL: URL(fileURLWithPath: "/tmp/colony/sessions")
    ),
    checkpointStore: try ColonyDurableRuntimeCheckpointStoreAdapter(
        baseURL: URL(fileURLWithPath: "/tmp/colony/checkpoints")
    ),
    messageSink: ColonyInMemoryMessageSink(),
    backends: ColonyGatewayBackends(
        filesystem: ColonyDiskFileSystemBackend(root: URL(fileURLWithPath: "/workspace")),
        shell: try ColonyHardenedShellBackend(
            confinement: ColonyShellConfinementPolicy(allowedRoot: URL(fileURLWithPath: "/workspace"))
        )
    )
)

let handle = try await runtime.startRun(
    ColonyGatewayRunRequest(
        sessionID: ColonyRuntimeSessionID(rawValue: "session:demo"),
        input: "Summarize the latest TODOs and propose next steps.",
        providerOverride: ColonyProviderSelection(
            preferredProviderName: "openrouter",
            fallbackProviderNames: ["openai"]
        )
    )
)
let result = await handle.awaitResult()
```

## Compatibility

Current `ColonyRuntime` and `ColonyAgentFactory` entrypoints are preserved.
No removals were made in this milestone.

## Migration Note: Conduit in Colony

`Colony` now directly depends on Conduit (in addition to Hive). This gives a batteries-included provider path for app runtimes like PicoClaw, Hive, and Swarm without requiring each app to build provider clients manually.
