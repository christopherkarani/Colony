# Colony

Colony is a Deep Agents-style harness built on top of `HiveCore`.

## Current architecture

- `Colony` target: graph orchestration (`preModel -> model -> routeAfterModel -> tools -> toolExecute -> preModel`)
- `ColonyCore` target: pure data contracts and capability protocols
- Built-in tools:
  - planning: `write_todos`, `read_todos`
  - filesystem: `ls`, `read_file`, `write_file`, `edit_file`, `glob`, `grep`
  - shell: `execute` (requires a `ColonyShellBackend`)
  - subagents: `task` (requires a `ColonySubagentRegistry`)
- Parity audit: `docs/DEEP_AGENTS_PARITY.md`

## On-device defaults

- Tool surface is capability-gated and backend-gated.
- `ColonyContext` can omit shell/subagents on iOS to keep execution local and constrained.
- Human approval interrupt flow is built in for risky tool calls (`ColonyToolApprovalPolicy`).
- Use `ColonyAgentFactory(profile: .onDevice4k)` to keep inputs within a ~4k token window (compaction + tool output eviction + history offload).

## Minimal setup

```swift
let factory = ColonyAgentFactory()
let runtime = try factory.makeRuntime(
    profile: .onDevice4k,
    modelName: "your-model",
    model: AnyHiveModelClient(myModelClient)
)

let handle = await runtime.sendUserMessage("Research Hive and summarize it.")
_ = try await handle.outcome.value
```
