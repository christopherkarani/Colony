## Prompt for Coding Agent

```text
You are helping me onboard to Colony (Swift 6.2). Explain the Colony + ColonyCore architecture, the runtime loop (preModel -> model -> routeAfterModel -> tools -> toolExecute -> preModel), and how to run it on iOS/macOS 26+ with a local ../hive dependency. Include proof-backed behavior for tool approval interrupts/resume, on-device 4k budgeting, summarization with /conversation_history offload, large tool result eviction to /large_tool_results, scratchbook workflows, and isolated subagents. End with a minimal runnable Swift snippet using ColonyAgentFactory + ColonyRuntime.sendUserMessage and a human-in-the-loop resume example.
```

# Colony

Local-first Deep Agents-style runtime in Swift. If this project helps you ship better agent workflows, please star it.

## Why Colony

- Fast to embed: create a `ColonyRuntime`, send a user message, handle finished or interrupted outcomes.
- Safety by design: capability-gated tools and human-in-the-loop approval for risky calls.
- Practical on-device defaults: a strict 4k-safe profile with compaction, summarization/history offload, and tool-result eviction.

## Architecture (Colony + ColonyCore)

- `Colony`: graph/runtime orchestration and execution.
- `ColonyCore`: pure contracts and policies (capabilities, tool approval, interrupts/resume payloads, scratchbook, configuration).
- Runtime loop: `preModel -> model -> routeAfterModel -> tools -> toolExecute -> preModel`.

Built-in tool families (all capability-gated, backend-gated):
- Planning: `write_todos`, `read_todos`
- Filesystem: `ls`, `read_file`, `write_file`, `edit_file`, `glob`, `grep`
- Shell: `execute` (requires `ColonyShellBackend`)
- Scratchbook: `scratch_read`, `scratch_add`, `scratch_update`, `scratch_complete`, `scratch_pin`, `scratch_unpin`
- Subagents: `task` (requires `ColonySubagentRegistry`)

## Proven Behaviors (Backed by Tests)

- Tool approval interrupts + resume (approve/reject) are exercised end-to-end in `Tests/ColonyTests/ColonyAgentTests.swift`.
- On-device profile enforces a hard 4k request budget (`requestHardTokenLimit == 4_000`) in `Tests/ColonyTests/ColonyContextBudgetTests.swift`.
- Summarization offloads history to `/conversation_history/{thread}.md` in `Tests/ColonyTests/ColonySummarizationTests.swift`.
- Large tool outputs are evicted to `/large_tool_results/{tool_call_id}` with deterministic preview trimming in `Tests/ColonyTests/ColonyToolResultEvictionTests.swift`.
- Scratchbook tooling is capability-gated, thread-scoped, and persisted deterministically in `Tests/ColonyTests/ScratchbookToolsTests.swift` and `Tests/ColonyTests/ColonyScratchbookCoreAndStorageTests.swift`.
- Subagents run in isolated runtimes, block recursive delegation by default, and keep on-device budget posture in `Tests/ColonyTests/DefaultSubagentRegistryTests.swift`.

## Requirements

- Swift 6.2 (`swift-tools-version: 6.2`)
- iOS 26+ or macOS 26+
- A local Hive checkout at `../hive` (current `Package.swift` uses `.package(path: "../hive")`)

## Quickstart

1. Ensure a sibling Hive checkout exists at `../hive` (local SwiftPM dependency path used by `Package.swift`).
2. Build and run tests.
3. Create a runtime and send a message.

```bash
cd /path/to/Colony
test -f ../hive/Package.swift || echo "Missing ../hive (required local dependency)"
swift package resolve
swift test
```

```swift
import Colony

@main
struct Demo {
    static func main() async throws {
        guard ColonyFoundationModelsClient.isAvailable else {
            fatalError("Foundation Models unavailable on this device. Provide another HiveModelClient.")
        }

        let factory = ColonyAgentFactory()
        let runtime = try factory.makeRuntime(
            profile: .onDevice4k,
            modelName: "test-model",
            model: AnyHiveModelClient(ColonyFoundationModelsClient())
        )

        let handle = await runtime.sendUserMessage("Inspect this project and propose next steps.")
        let outcome = try await handle.outcome.value
        print(outcome)
    }
}
```

## Human-In-The-Loop Approval (Interrupt + Resume)

```swift
import Colony

let factory = ColonyAgentFactory()
let runtime = try factory.makeRuntime(
    profile: .onDevice4k,
    modelName: "test-model",
    model: AnyHiveModelClient(ColonyFoundationModelsClient()),
    configure: { config in
        config.toolApprovalPolicy = .always
    }
)

let handle = await runtime.sendUserMessage("Create /note.md with a deployment checklist.")
let outcome = try await handle.outcome.value

if case let .interrupted(interruption) = outcome,
   case let .toolApprovalRequired(toolCalls) = interruption.interrupt.payload {
    print("Approval required for:", toolCalls.map(\.name))

    let resumed = await runtime.resumeToolApproval(
        interruptID: interruption.interrupt.id,
        decision: .approved // or .rejected
    )
    _ = try await resumed.outcome.value
}
```

## Troubleshooting

- `swift package resolve` fails: verify `../hive` exists and is a valid Hive package checkout.
- `foundationModelsUnavailable`: on-device Foundation Models are not available on this device/configuration. Inject another `HiveModelClient` or use a router.
- Missing tools in prompts: check both capabilities and backend wiring (for example, `shell` needs `ColonyShellBackend`; `subagents` needs `ColonySubagentRegistry`).
- SDK/platform errors: this package targets Swift 6.2 with iOS/macOS 26+.

## Current Limitations

- Dependency is local-path only today: `.package(path: "../hive")`.
- Platform availability is currently iOS 26+ and macOS 26+.
- On-device profile is intentionally strict (~4k posture): older context and large outputs are compacted/offloaded by design.
