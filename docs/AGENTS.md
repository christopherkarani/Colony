# Colony — AI Coding Agent Onboarding Guide

**For**: Coding agents using Colony framework (Swift 6.2, iOS/macOS 26+)
**Goal**: Use Colony to build agentic applications without prior knowledge

---

## What is Colony?

Colony is a **local-first agent runtime** in pure Swift. It provides:

- Deterministic execution with checkpoint/resume
- Capability-gated tools with human approval
- On-device 4k context budget enforcement
- Subagent orchestration
- Memory persistence via Wax

### Products

| Product | Purpose |
|---------|---------|
| **Colony** | Primary runtime — graph orchestration and execution |
| **ColonyCore** | Pure protocols and policies — capability gating, tool approval, configuration |
| **ColonySwarmInterop** | Bridge between Colony and Swarm frameworks |
| **ColonyControlPlane** | Session and project management |

### Dependencies

```
Colony → ColonyCore + Hive + Swarm + Membrane + Conduit + Wax
```

> **Important**: `import Colony` does NOT expose ColonyCore types. You must:
> ```swift
> import Colony        // Colony runtime types
> import ColonyCore    // Protocol definitions (ColonyTool, ColonyID, ColonyConfiguration, etc.)
> ```

---

## Quick Start

### The Only Public Entry Point

```swift
import Colony

// Minimal agent — zero config
let agent = try await Colony.agent(model: .foundationModels())
let handle = await agent.send("Hello, agent!")
let outcome = try await handle.outcome.value
```

### With Filesystem Access

```swift
import Colony
import ColonyCore

let agent = try await Colony.agent(
    model: .foundationModels(),
    capabilities: [.filesystem, .shell]
) {
    .filesystem(ColonyFileSystem.DiskBackend(root: projectURL))
    .shell(ColonyHardenedShellBackend())
}
```

### With Human Approval for Risky Tools

```swift
let agent = try await Colony.agent(
    model: .foundationModels(),
    capabilities: [.filesystem]
) {
    .filesystem(ColonyFileSystem.DiskBackend(root: projectURL))
} configure: { config in
    config.safety.toolApprovalPolicy = .always
}

// When agent requests a risky tool:
let handle = await agent.send("Write a deployment script")
let outcome = try await handle.outcome.value

if case let .interrupted(interrupt) = outcome,
   case let .toolApprovalRequired(calls) = interrupt.interrupt.payload {
    // Show to human
    let resumed = await agent.resumeToolApproval(
        interruptID: interrupt.interrupt.id,
        decision: .approved  // or .rejected
    )
    _ = try await resumed.outcome.value
}
```

---

## Key Concepts

### ColonyRuntime

The main runtime handle. Created via `Colony.agent()`.

| Method | Purpose |
|--------|---------|
| `send(_:optionsOverride:)` | Send a message, get a `ColonyRun.Handle` |
| `sendUserMessage(_:optionsOverride:)` | Alias for `send()` |
| `resumeToolApproval(interruptID:decision:)` | Resume after human approval |

### ColonyModel

Configures the AI model. Factory methods:

| Factory | Use Case |
|---------|----------|
| `.foundationModels()` | Apple Foundation Models (on-device) |
| `.onDevice(configuration:)` | On-device model with custom config |
| `.providerRouting([...])` | Route between multiple providers (e.g., Ollama fallback) |

### ColonyConfiguration

3-tier progressive disclosure:

```swift
// Tier 1: Just model + modelName — minimal
Colony.agent(model: .foundationModels())

// Tier 2: Add capabilities + services — standard
Colony.agent(model: .foundationModels(), capabilities: [.filesystem]) { ... }

// Tier 3: Full control via configure closure — advanced
Colony.agent(model: .foundationModels(), profile: .onDevice4k) { ... }
    configure: { config in
        config.safety.toolApprovalPolicy = .always
        config.model.capabilities = [.filesystem, .shell, .git]
    }
```

### ColonyAgentCapabilities

Gates which tools are available to the agent:

| Capability | Enables Tools |
|------------|--------------|
| `.planning` | `.writeTodos`, `.readTodos` |
| `.filesystem` | `.ls`, `.readFile`, `.writeFile`, `.editFile`, `.glob`, `.grep` |
| `.shell` | `.execute`, `.shellOpen`, `.shellWrite`, `.shellRead`, `.shellClose` |
| `.git` | `.gitStatus`, `.gitDiff`, `.gitCommit`, `.gitBranch`, `.gitPush`, `.gitPreparePR` |
| `.lsp` | `.lspSymbols`, `.lspDiagnostics`, `.lspReferences`, `.lspApplyEdit` |
| `.memory` | `.memoryRecall`, `.memoryRemember` |
| `.subagents` | `.task` |
| `.webSearch` | `.webSearch` |
| `.codeSearch` | `.codeSearch` |
| `.mcp` | `.mcpListResources`, `.mcpReadResource` |
| `.plugins` | `.pluginListTools`, `.pluginInvoke` |
| `.largeToolResults` | Large output handling |
| `.conversationHistory` | History access |

### ColonyTool.Name — All 39 Built-in Tools

**Planning:**
- `.writeTodos` — Write task list
- `.readTodos` — Read task list

**Filesystem** (requires `.filesystem` capability):
- `.ls` — List directory contents
- `.readFile` — Read file contents
- `.writeFile` — Write file contents
- `.editFile` — Edit file with targeted changes
- `.glob` — Glob pattern matching
- `.grep` — Search file contents

**Shell** (requires `.shell` capability):
- `.execute` — Execute shell command
- `.shellOpen`, `.shellWrite`, `.shellRead`, `.shellClose` — Interactive shell sessions

**Git** (requires `.git` capability):
- `.gitStatus`, `.gitDiff`, `.gitCommit`, `.gitBranch`, `.gitPush`, `.gitPreparePR`

**LSP** (requires `.lsp` capability):
- `.lspSymbols`, `.lspDiagnostics`, `.lspReferences`, `.lspApplyEdit`

**Memory** (requires `.memory` capability):
- `.memoryRecall` — Recall from persistent memory
- `.memoryRemember` — Store to persistent memory

**Scratchbook** (always available, thread-scoped):
- `.scratchRead`, `.scratchAdd`, `.scratchUpdate`, `.scratchComplete`, `.scratchPin`, `.scratchUnpin`

**Subagents** (requires `.subagents` capability):
- `.task` — Spawn isolated subagent

**Web/Code Search**:
- `.webSearch` (requires `.webSearch`)
- `.codeSearch` (requires `.codeSearch`)

**MCP** (requires `.mcp` capability):
- `.mcpListResources`, `.mcpReadResource`

**Plugins** (requires `.plugins` capability):
- `.pluginListTools`, `.pluginInvoke`

**Patching**:
- `.applyPatch` — Apply unified diff patches

---

## Runtime Loop

The Colony runtime executes a BSP-style superstep loop:

```
preModel → model → routeAfterModel → tools → toolExecute → preModel
```

| Stage | What Happens | Agent Hook Point |
|-------|--------------|------------------|
| **preModel** | Prepare context, inject system prompt, capability filtering | `ColonyConfiguration.prompt` |
| **model** | Call LLM with messages | `ColonyModelClient` |
| **routeAfterModel** | Route based on model output (tool calls vs text) | `ColonyModelRouter` |
| **tools** | Validate tool calls against registry | `ColonyToolRegistry` |
| **toolExecute** | Execute tools, collect results | Backend implementations |
| **preModel** | Loop back with tool results | — |

### Interrupt Points

The loop can pause at **tool execution** for:
- **Human approval**: `toolApprovalRequired` interrupt — requires human decision
- **Subagent delegation**: `subagentRequired` interrupt — spawn subagent
- **Checkpoint**: Periodic checkpoint for resumability

---

## Service Backends

Tools require backend implementations registered via `@ColonyServiceBuilder`:

### Filesystem

```swift
import ColonyCore

// In-memory (for testing)
let inMemory = ColonyFileSystem.InMemoryBackend()

// Disk-based
let disk = ColonyFileSystem.DiskBackend(root: projectURL)

// Register
Colony.agent(model: .foundationModels()) {
    .filesystem(disk)
}
```

### Shell

```swift
import ColonyCore

// Hardened shell (safe defaults)
let shell = ColonyHardenedShellBackend()

Colony.agent(model: .foundationModels()) {
    .shell(shell)
}
```

### Git

```swift
import ColonyCore

let git = MyGitBackend()  // Implement ColonyGitBackend protocol

Colony.agent(model: .foundationModels()) {
    .git(git)
}
```

### Memory (Wax)

```swift
import ColonyCore

let memory: ColonyMemoryBackend =  // Implement ColonyMemoryBackend

Colony.agent(model: .foundationModels()) {
    .memory(memory)
}
```

### Subagents

```swift
import ColonyCore

let subagents: ColonySubagentRegistry =  // Implement ColonySubagentRegistry

Colony.agent(model: .foundationModels()) {
    .subagents(subagents)
}
```

---

## Profiles

Pre-configured runtime profiles:

| Profile | Token Budget | Use Case |
|---------|-------------|----------|
| `.onDevice4k` | 4k context + 500 reserve | iOS/macOS on-device, strict |
| `.cloud` | Large context | Cloud inference |

```swift
Colony.agent(
    model: .foundationModels(),
    profile: .onDevice4k,
    capabilities: [.filesystem]
) { ... }
```

---

## Common Patterns

### Pattern 1: Minimal Agent

```swift
let agent = try await Colony.agent(model: .foundationModels())
let handle = await agent.send("What files are in this project?")
let outcome = try await handle.outcome.value
```

### Pattern 2: Agent with Tool Approval

```swift
let agent = try await Colony.agent(
    model: .foundationModels(),
    capabilities: [.filesystem]
) {
    .filesystem(ColonyFileSystem.DiskBackend(root: projectURL))
} configure: { config in
    config.safety.toolApprovalPolicy = .always
}

let handle = await agent.send("Write /tmp/test.txt")
let outcome = try await handle.outcome.value

if case let .interrupted(interrupt) = outcome,
   case let .toolApprovalRequired(calls) = interrupt.interrupt.payload {
    let resumed = await agent.resumeToolApproval(
        interruptID: interrupt.interrupt.id,
        decision: .approved
    )
    let final = try await resumed.outcome.value
}
```

### Pattern 3: Multi-Provider Routing

```swift
let agent = try await Colony.agent(
    model: .providerRouting([
        .foundationModels(),        // Primary
        .onDevice(configuration: .init(temperature: 0.3)),  // Fallback
    ])
)
```

---

## Troubleshooting

### "foundationModelsUnavailable"

On-device Foundation Models not available on this device. Use `.providerRouting()` with Ollama or another provider as fallback.

```swift
model: .providerRouting([
    .foundationModels(),
    .onDevice(),  // Will use on-device if available
])
```

### "tool not found"

Check that:
1. The required capability is enabled: `capabilities: [.filesystem]`
2. The backend is registered: `{ .filesystem(myBackend) }`

### Compile errors accessing ColonyCore types

You need `import ColonyCore` separately from `import Colony`.

### "ColonyBootstrap is not accessible"

Use `Colony.agent(model:)` — `ColonyBootstrap` is `package`-internal. The public API is `Colony.agent()`.

---

## Important Notes

- **Swift 6.2 required** — Colony uses Swift 6.2 features
- **iOS/macOS 26+** — Platform requirement
- **Two-module import** — `import Colony` for runtime, `import ColonyCore` for protocols
- **Capability gating** — Tools only available if both capability flag AND backend are present
- **@ColonyServiceBuilder** — Use the DSL closure syntax to register services, not direct construction

---

## File Locations

| Type | File |
|------|------|
| Entry point | `ColonyEntryPoint.swift` |
| Runtime | `ColonyRuntime.swift` |
| Configuration | `ColonyConfiguration.swift` |
| Tool names | `ColonyCore/ColonyToolName.swift` |
| Capabilities | `ColonyCore/ColonyCapabilities.swift` |
| Service builder | `ColonyServiceBuilder.swift` |
| Runtime loop | `ColonyAgent.swift:169-191` |
