# Tool Approval System

Colony includes a safety system that requires human approval before executing risky tools. This document explains how the approval system works, how to configure it, and how to handle interrupts.

---

## Overview

When an agent requests a tool that is deemed risky (e.g., shell execution, file writing), Colony can interrupt the runtime loop and wait for human approval before proceeding.

```
Agent requests risky tool
         │
         ▼
┌────────────────────────┐
│  Risk Assessment       │
│  (ColonyToolSafety    │
│   PolicyEngine)       │
└───────────┬────────────┘
            │
    ┌──────┴──────┐
    │             │
 auto-approved   requires approval
            │
            ▼
┌────────────────────────┐
│  Tool Approval         │
│  Interrupt            │
│  (checkpoint state)   │
└───────────┬────────────┘
            │
            ▼
    Wait for human decision
            │
     ┌──────┴──────┐
     │             │
  approved      rejected
     │             │
     ▼             ▼
 Execute     Skip tool,
 tool      continue agent
```

---

## Configuration

### Tool Approval Policy

Configure globally via `ColonyConfiguration`:

```swift
let agent = try await Colony.agent(
    model: .foundationModels(),
    capabilities: [.filesystem, .shell]
) {
    .filesystem(ColonyFileSystem.DiskBackend(root: projectURL))
    .shell(ColonyHardenedShellBackend())
} configure: { config in
    // Options: .riskBased (default), .always, .never, .allowList([...])
    config.safety.toolApprovalPolicy = .always
}
```

### Policy Options

| Policy | Behavior |
|--------|----------|
| `.riskBased` | Each tool's risk level determines if approval is needed (default) |
| `.always` | Every tool requires approval |
| `.never` | No approval required (not recommended) |
| `.allowList([...])` | Only specified tools require approval |

### Risk Levels

Each tool has a `ColonyTool.RiskLevel`:

| Level | Meaning | Default Approval |
|--------|---------|----------------|
| `.readOnly` | Safe read operations | Auto-approved |
| `.stateMutation` | Modifies state but safe | Auto-approved |
| `.mutation` | Changes files or system state | May require approval |
| `.execution` | Executes code/shell commands | Always requires approval |

### Per-Tool Risk Overrides

Override the default risk level for specific tools:

```swift
config.safety.toolRiskLevelOverrides = [
    .writeFile: .always,      // Writing files always needs approval
    .execute: .always,        // Shell execution always needs approval
    .readFile: .automatic,    // Reading files auto-approved
]
```

---

## Handling Approval Interrupts

When a tool requires approval, `ColonyRuntime.send()` returns an interrupted outcome:

```swift
let handle = await agent.send("Write a deployment script to /tmp/deploy.sh")
let outcome = try await handle.outcome.value

if case let .interrupted(interrupt) = outcome,
   case let .toolApprovalRequired(calls) = interrupt.interrupt.payload {
    // interrupt.interrupt.id — use this to resume
    // calls — the tools awaiting approval

    print("Waiting for approval: \(calls.map { $0.name })")
}
```

### Resuming After Decision

```swift
// Resume with approval
let resumed = await agent.resumeToolApproval(
    interruptID: interrupt.interrupt.id,
    decision: .approved
)

// Or reject
let resumed = await agent.resumeToolApproval(
    interruptID: interrupt.interrupt.id,
    decision: .rejected
)

let finalOutcome = try await resumed.outcome.value
```

### Decision Types

| Decision | Effect |
|----------|--------|
| `.approved` | Tool executes, agent continues with result |
| `.rejected` | Tool is skipped, agent receives empty result |
| `.cancelled` | Agent task is cancelled |

---

## Interrupt Payload

The `ColonyRun.Interrupt` contains:

```swift
public struct Interrupt {
    public let id: ColonyInterruptID    // Unique interrupt ID for resume
    public let payload: Payload        // What type of interrupt
    public let checkpointID: String?   // Checkpoint for resume
    public let timestamp: Date
}
```

### Payload Types

| Payload | Meaning |
|---------|---------|
| `.toolApprovalRequired([Call])` | Tools pending human approval |
| `.subagentRequired(SubagentRequest)` | Subagent needs to be spawned |
| `.checkpointCreated(id:)` | Periodic checkpoint created |
| `.humanInputRequired(reason:)` | Agent needs text input from human |

### Tool Call Details

The `ColonyTool.Call` pending approval:

```swift
public struct Call {
    public let id: ColonyToolCallID
    public let name: ColonyTool.Name
    public let argumentsJSON: String
}
```

---

## Checkpoint and Resume

When an interrupt occurs:

1. **State is checkpointed** — full conversation context is saved
2. **Runtime waits** — agent loop is paused
3. **Human decides** — approve or reject
4. **Resume** — state is restored, execution continues

The checkpoint allows:
- Resume after approval with exact state
- No work is lost during approval wait
- Agent can continue even if the app was restarted

### Checkpoint Configuration

```swift
Colony.agent(
    model: .foundationModels(),
    checkpointing: .onInterrupt  // Default: checkpoint on interrupts
) { ... }
```

Options:
- `.inMemory` — No checkpointing (default for tests)
- `.onInterrupt` — Checkpoint on every interrupt (default for production)
- `.every(N)` — Checkpoint every N supersteps

---

## Risk Assessment

The `ColonyToolSafetyPolicyEngine` evaluates tools:

```swift
public struct ColonyToolSafetyAssessment {
    public let tool: ColonyTool.Name
    public let riskLevel: ColonyTool.RiskLevel
    public let approvalRequired: Bool
    public let reason: String
}
```

Built-in risk levels by tool:

| Tool | Risk Level |
|------|-----------|
| `.ls`, `.readFile`, `.readTodos` | `.readOnly` |
| `.writeFile`, `.editFile`, `.writeTodos` | `.stateMutation` |
| `.execute`, `.gitCommit`, `.gitPush` | `.execution` |
| `.glob`, `.grep` | `.readOnly` |

---

## Backend Requirements

Some backends always require approval regardless of policy:

```swift
// Shell execution is inherently risky
config.safety.toolRiskLevelOverrides[.execute] = .always

// Git push can modify remote state
config.safety.toolRiskLevelOverrides[.gitPush] = .always
```

---

## Testing Approval Flows

The approval system is tested in `Tests/ColonyTests/ColonyAgentTests.swift`:

```swift
@Test func toolApprovalInterruptsAndResumes() async throws {
    // Agent requests risky tool
    let handle = await runtime.sendUserMessage("Write secret key to /tmp/key")

    // Should be interrupted
    try await Task.sleep(nanoseconds: 100_000_000)
    let outcome = try await handle.outcome.value

    if case let .interrupted(interrupt) = outcome,
       case let .toolApprovalRequired(calls) = interrupt.interrupt.payload {
        // Approve
        let resumed = await runtime.resumeToolApproval(
            interruptID: interrupt.interrupt.id,
            decision: .approved
        )
        // Should complete successfully
    }
}
```

---

## Source Reference

| Type | File |
|------|------|
| `ColonyToolApproval` | `ColonyCore/ColonyToolApproval.swift` |
| `ColonyToolSafetyPolicy` | `ColonyCore/ColonyToolSafetyPolicy.swift` |
| `ColonyRun.Interrupt` | `ColonyCore/ColonyRuntimeSurface.swift` |
| `ColonyRuntime.resumeToolApproval` | `ColonyRuntime.swift` |
| Tests | `Tests/ColonyTests/ColonyAgentTests.swift` |
