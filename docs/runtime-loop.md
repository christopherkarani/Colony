# Colony Runtime Loop

**Source**: `ColonyAgent.swift:169-191` (BSP superstep execution)

Colony executes agentic tasks using a **Bulk Synchronous Parallel (BSP)** superstep loop. Each superstep progresses from pre-model preparation through model inference to tool execution, with optional interrupt points for human approval or subagent delegation.

---

## Loop Stages

```
┌─────────────────────────────────────────────────────────────────────┐
│                        BSP Superstep Loop                              │
│                                                                      │
│  ┌──────────┐    ┌──────┐    ┌────────────────┐    ┌─────┐        │
│  │ preModel │───▶│ model │───▶│ routeAfterModel│───▶│tools│        │
│  └──────────┘    └──────┘    └────────────────┘    └──┬──┘        │
│                                                          │           │
│                    ┌─────────────────────────────────────▼─────────┐  │
│                    │              toolExecute                   │  │
│                    │  ┌─────────┐  ┌──────────┐  ┌────────┐   │  │
│                    │  │ Execute  │  │  Risk    │  │ Human │   │  │
│                    │  │ approved │  │ assessment│  │Approval│   │  │
│                    │  │  tools   │  │          │  │Interrupt│   │  │
│                    │  └────┬─────┘  └────┬─────┘  └───┬────┘   │  │
│                    └───────┼─────────────┼─────────────┼────────┘  │
│                            │             │             │             │
│                            └─────────────▼─────────────┘             │
│                                        │                             │
│                              ┌─────────▼─────────┐                  │
│                              │  Loop: preModel    │                  │
│                              │  (with results)    │                  │
│                              └────────────────────┘                  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Stage 1: preModel

**What happens:**
- System prompt is injected with capability-filtered tool definitions
- Conversation history is managed (summarization, offload)
- Context window budget is enforced (4k on-device profile)
- Scratchpad/scratchbook state is prepared

**When the loop reaches this stage:**
- Start of a new superstep
- After tool execution completes (tools return results)
- After an interrupt is resolved (human approval given)

**Agent use case:** Hook into `ColonyConfiguration.prompt` to customize system prompt, inject instructions, or set agent personality.

---

## Stage 2: model

**What happens:**
- LLM is called with the prepared message context
- Model decides: generate text OR request tool calls OR finish
- Model output is parsed into `ColonyModel.Output`

**When the loop reaches this stage:**
- After preModel prepares context
- After interrupt resolution (resume)

**Agent use case:**
- Configure model via `ColonyModel.foundationModels()`, `.onDevice()`, or `.providerRouting()`
- Set temperature, token budget via `FoundationModelConfiguration`
- Use `.providerRouting()` for multi-provider fallback (e.g., Ollama on-device)

---

## Stage 3: routeAfterModel

**What happens:**
- Parsed model output is classified into one of:
  - `.text(Message)` — plain text response to return to user
  - `.toolCalls([Call])` — agent requested tool execution
  - `.finished` — task complete

**When the loop reaches this stage:**
- After model returns output

**Agent use case:** Implement `ColonyModelRouter` to customize routing logic (rare — default is usually correct).

---

## Stage 4: tools

**What happens:**
- Each requested tool call is validated:
  - Tool name exists in registry
  - Required capability is enabled
  - Parameters match JSON schema
- Risk assessment: each tool is evaluated against `ColonyToolSafetyPolicyEngine`
- Tools requiring approval are held; auto-approved tools proceed

**When the loop reaches this stage:**
- After routeAfterModel classifies output as `.toolCalls`

**Agent use case:**
- Configure `ColonyConfiguration.safety.toolApprovalPolicy`
- Override per-tool risk levels: `config.safety.toolRiskLevelOverrides = [.execute: .always]`
- Register backend implementations that actually execute tools

---

## Stage 5: toolExecute

**What happens:**
- Approved tools are executed concurrently via their backend implementations
- Results are collected as `ColonyTool.Result`
- Risk level determines behavior:
  - `.readOnly` — auto-executed
  - `.stateMutation` — may require approval
  - `.mutation` — requires approval
  - `.execution` — always requires approval (shell, exec)

**Interrupt Points:**

### Human Tool Approval

When a tool requires human approval:
1. Loop pauses at `toolExecute`
2. `ColonyRun.Interrupt` is returned with `.toolApprovalRequired` payload
3. Agent waits for human decision via `ColonyRuntime.resumeToolApproval()`
4. On approval: tool executes, loop continues
5. On rejection: tool is skipped, agent handles gracefully

```swift
if case let .interrupted(interrupt) = outcome,
   case let .toolApprovalRequired(calls) = interrupt.interrupt.payload {
    let resumed = await agent.resumeToolApproval(
        interruptID: interrupt.interrupt.id,
        decision: .approved  // or .rejected
    )
}
```

### Subagent Delegation

When agent requests `.task` (subagent spawn):
1. Loop pauses
2. `ColonyRun.Interrupt` returned with `.subagentRequired` payload
3. `ColonySubagentRegistry.run()` is called
4. Results merged back into parent agent context

### Checkpoint Creation

Checkpoints are created:
- On tool approval interrupt (state checkpointed before waiting)
- Periodically every N supersteps (configurable)
- On explicit request

Resume after checkpoint restores full conversation state.

---

## Loop Summary

| Stage | Input | Output | Interrupt? |
|-------|-------|--------|-----------|
| **preModel** | Previous results | Prepared context | — |
| **model** | Context | Text or tool calls | — |
| **routeAfterModel** | Model output | Route decision | — |
| **tools** | Tool calls | Validated calls + risk | — |
| **toolExecute** | Approved tools | Tool results | YES: human approval, subagent, checkpoint |

---

## Configuration

### Checkpoint Policy

```swift
Colony.agent(
    model: .foundationModels(),
    checkpointing: .every(10)  // Checkpoint every 10 supersteps
) { ... }
```

Options:
- `.inMemory` — No persistence (default for tests)
- `.every(N)` — Checkpoint every N supersteps
- `.onInterrupt` — Only checkpoint on interrupt

### Tool Approval Policy

```swift
// Default: risk-based
config.safety.toolApprovalPolicy = .riskBased

// Always require approval for all tools
config.safety.toolApprovalPolicy = .always

// Only specific tools
config.safety.toolApprovalPolicy = .allowList([.writeFile, .execute])

// Never (not recommended)
config.safety.toolApprovalPolicy = .never
```

### Risk Level Overrides

```swift
config.safety.toolRiskLevelOverrides = [
    .execute: .always,     // Shell execution always needs approval
    .readFile: .automatic, // Reading files auto-approved
    .writeFile: .always,  // Writing files always needs approval
]
```

---

## Debugging the Loop

To trace loop execution:

```swift
let agent = try await Colony.agent(
    model: .foundationModels(),
    capabilities: [.filesystem]
) {
    .filesystem(ColonyFileSystem.DiskBackend(root: projectURL))
} configure: { config in
    // Enable observability
    config.observability.sink = ColonyObservability.ConsoleSink()
}
```

The console sink will print each superstep stage transitions.

---

## Source Reference

- Loop implementation: `Sources/Colony/ColonyAgent.swift:169-191`
- Interrupt types: `ColonyCore/ColonyRuntimeSurface.swift`
- Tool approval: `ColonyCore/ColonyToolApproval.swift`
- Safety policy: `ColonyCore/ColonyToolSafetyPolicy.swift`
