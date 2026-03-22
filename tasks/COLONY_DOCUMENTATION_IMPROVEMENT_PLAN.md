# Colony Documentation Improvement Plan
## Comprehensive Master Plan for Agent-Onboarding Excellence

**Generated**: 2026-03-22
**Framework**: Colony (Swift 6.2 Agent Runtime)
**Goal**: Make Colony perfectly usable by AI coding agents with zero prior knowledge

---

## Executive Summary

Colony is a local-first agent runtime in Swift with strong foundations but documentation that was written before the API was fully stabilized. The existing docs have significant gaps, inconsistencies, and outdated examples that would mislead AI agents attempting to use Colony.

**Current State**:
- Existing API audit docs are thorough but focused on API structure, not usage
- README.md has correct examples but lacks depth
- No cohesive "Agent Onboarding Guide"
- Missing release/upgrade docs (referenced in CHANGELOG but don't exist)
- No skills or agents specific to Colony for AI-assisted development
- Test coverage exists but tests don't serve as documentation

**Target State**: Every public API has doc comments, every workflow has runnable examples, every concept has clear explanation, and AI agents can onboard without human guidance.

---

## Critical Audit Findings (Verified Against Source)

The following issues were discovered by agent audit teams verifying source code against existing documentation. **These must be fixed before any other documentation work:**

### CRITICAL DISCREPANCIES (Must Fix First)

| # | Issue | Impact |
|---|-------|--------|
| C1 | **`import Colony` does NOT expose ColonyCore types** — Colony.swift has NO `@_exported import ColonyCore`. Users must `import ColonyCore` separately. The api-surface-catalog incorrectly claims ~95 ColonyCore types are available via `import Colony`. | HIGH — Agents will fail to access ColonyCore types |
| C2 | **`ColonyTool.PromptStrategy` enum cases WRONG in catalog** — Catalog says `.verbose` and `.minimal` but actual source has `.includeInSystemPrompt` and `.omitFromSystemPrompt` | HIGH — Any agent using wrong enum cases will get compile errors |
| C3 | **`ColonyToolSafetyPolicyEngine` and `ColonyToolSafetyAssessment` are `package` not `public`** — The catalog lists them as public API but they cannot be accessed externally | HIGH — Safety policy customization is not actually possible |
| C4 | **`SwarmSubagentAdapterError` leaks unprefixed through public API** — `enum SwarmSubagentAdapterError` (not `ColonySwarmSubagentAdapterError`) is visible in the `run()` error path | MEDIUM — Pollutes Colony namespace with Swarm names |

### MISSING FROM CATALOG (Not Listed At All)

These public types exist in source but are NOT in the api-surface-catalog:

| Type | File | Importance |
|------|------|------------|
| `ColonyCost`, `ColonyTokenCount` | ColonyModelValueTypes.swift | MEDIUM — User-facing value types |
| `ColonyModelName` | ColonyModelName.swift | MEDIUM — Key model config type |
| `ColonyToolAudit` namespace (9 types) | ColonyToolAudit.swift | HIGH — Audit/trail system |
| `ColonyPatch` namespace | ColonyCodingBackends.swift | MEDIUM — Plugin system |
| `ColonyWebSearch` namespace | ColonyCodingBackends.swift | MEDIUM |
| `ColonyCodeSearch` namespace | ColonyCodingBackends.swift | MEDIUM |
| `ColonyMCP` namespace | ColonyCodingBackends.swift | MEDIUM |
| `ColonyFileSystem.DiskBackend` | ColonyFileSystem.swift | MEDIUM — Concrete file backend |
| `ColonyToolApprovalRule*` types | ColonyToolApprovalRules.swift | MEDIUM — Approval rules system |
| `ColonyScratchItem`, `ColonyScratchbook` | ColonyScratchbook.swift | MEDIUM — Scratchbook rendering |

### WRONG ATTRIBUTION IN CATALOG

- `ColonyTool.PromptStrategy` attributed to `ColonyPrompts.swift` but actually defined in `ColonyModelCapabilities.swift`

### DEPRECATED TYPEALIAS ISSUES

- `SwarmToolRegistration`, `SwarmToolBridge`, `SwarmMemoryAdapter`, `SwarmSubagentAdapter` — old unprefixed names still public via typealias
- `ColonyControlPlaneRESTTransport`, `ColonyControlPlaneSSETransport`, `ColonyControlPlaneWebSocketTransport` — claim distinct types but all alias to `ControlPlaneTransport`

### Missing Documentation (Verified by Source Audit)

These concepts exist in source but have ZERO documentation:

| Missing Doc | Source Evidence | Importance |
|------------|-----------------|------------|
| `@ColonyServiceBuilder` DSL usage | `ColonyServiceBuilder.swift` — no doc comments | HIGH |
| `ColonyProfile` vs `ColonyLane` distinction | Both exist in ColonyAgentFactory.swift, relationship undocumented | HIGH |
| Scratchbook operations reference | 6 operations in ColonyBuiltInToolDefinitions, no doc | MEDIUM |
| Tool approval interrupt/resume flow | `ColonyRun.Interruption.toolApprovalRequired` + `ColonyRuntime.resumeToolApproval()` — no doc | HIGH |
| Runtime lifecycle diagram | ColonyAgent.swift:169-191 confirms loop, no diagram | MEDIUM |
| Migration guide from pre-cleanup API | `ColonyCapabilities`→`ColonyRuntimeCapabilities`, Swarm renames — no migration doc | HIGH |
| CHANGELOG entry for API changes | CHANGELOG.md has zero API change entries | HIGH |

### README Issues (Verified by Documentation Audit)

| Issue | Impact | Status |
|-------|--------|--------|
| Primary code example uses `package` access types (`ColonyBootstrap`, `ColonyBootstrapOptions`) | CRITICAL | **FIXED** ✅ |
| Tool constants use wrong names (`read_todos` instead of `.readTodos`) | MEDIUM | **FIXED** ✅ |
| References `Hive` module (now `HiveCore`) | LOW | **FIXED** ✅ |
| No `Colony.agent()` usage shown | HIGH | **FIXED** ✅ |
| No `@ColonyServiceBuilder` DSL example | MEDIUM | **FIXED** ✅ |

---

## Part 1: Critical Documentation Gaps (Must Fix Immediately)

### P0: README.md is Completely Non-Runnable (CRITICAL) — FIXED ✅

**Status**: FIXED (2026-03-22)

**Changes Made**:
- Replaced non-runnable `ColonyBootstrap()` example with `Colony.agent(model:)` entry point
- Added 3 runnable quickstart examples: minimal agent, with services, on-device 4k profile
- Fixed tool names: `.readTodos`, `.writeTodos`, `.ls`, `.execute` etc. (was `read_todos`, `write_todos`, etc.)
- Fixed `ColonyFoundationModelsClient.isAvailable` → `.foundationModels()` factory
- Added `@ColonyServiceBuilder` DSL examples
- Added "How Tool Approval Works" explanation section
- Fixed troubleshooting section to reference correct `.foundationModels()` API and service registration pattern

### 1.1 Missing Release Documentation

**Status**: CHANGELOG.md references `docs/release/release-policy.md` and `docs/release/upgrade-flow.md` but these don't exist.

**Impact**: HIGH — Users upgrading Hive or Colony have no guidance

**Required Docs**:
```
docs/release/
├── release-policy.md      # Versioning strategy, deprecation policy, breaking change process
└── upgrade-flow.md       # Step-by-step upgrade instructions between versions
```

**Content for `release-policy.md`**:
- Semantic versioning policy
- What constitutes a breaking change
- Deprecation timeline (how long deprecated APIs live)
- How to pin Hive dependency
- Migration path for major versions

**Content for `upgrade-flow.md`**:
- How to update Hive pin
- What changed in each recent version
- Known issues and workarounds

### 1.2 Runtime Loop Documentation Missing

**Status**: README.md mentions `preModel -> model -> routeAfterModel -> tools -> toolExecute -> preModel` but never explains what each stage does or when/why an agent would use each.

**Required Doc**: `docs/runtime-loop.md`

**Content**:
```markdown
## Colony Runtime Loop

### Stage 1: preModel
What happens: [explanation]
Agent use case: [when to hook in here]

### Stage 2: model
What happens: [explanation]
Agent use case: [when to hook in here]

### Stage 3: routeAfterModel
What happens: [explanation]
Agent use case: [when to hook in here]

### Stage 4: tools
What happens: [explanation]
Agent use case: [when to hook in here]

### Stage 5: toolExecute
What happens: [explanation]
Agent use case: [when to hook in here]

### Interrupt Points
When the loop can pause for:
- Human tool approval
- Subagent delegation
- Checkpoint creation
```

### 1.3 Tool Approval Flow Documentation Incomplete

**Status**: README.md shows interrupt + resume code but doesn't explain:
- When tool approval is triggered
- How to configure approval policies
- How to handle partial approvals
- What happens to state on rejection

**Required Doc**: `docs/tool-approval.md`

**Content**:
```markdown
## Tool Approval System

### Approval Triggers
- Risk level thresholds
- Capability-based gating
- Policy-based rules

### Configuration
```swift
// Per-tool approval
config.safety.toolApprovalPolicy = .always

// Risk-based approval
config.safety.toolRiskLevelOverrides = [
    .execute: .always,  // Shell execution always needs approval
    .readFile: .automatic,  // Reading files auto-approved
]

// Allow-list approach
config.safety.toolApprovalPolicy = .allowList([.writeFile, .editFile])
```

### Resume Behavior
When tool approval is interrupted:
1. State is checkpointed
2. Agent waits for human decision
3. On approval: tool executes, loop continues
4. On rejection: tool skipped, agent handles gracefully

### Partial Approvals
[Explain if supported, or clarify not supported]
```

---

## Session Summary (2026-03-22 — P2 Continuation)

This session added comprehensive doc comments to the following ColonyCore files:

- **ColonyToolName.swift** — Added full namespace doc + per-tool doc comments (39 tools with risk level, capability, and usage context)
- **ColonyToolApproval.swift** — Added doc comments to `ColonyToolApproval` namespace, `Decision`, `Policy`, `PerToolDecision`, `PerToolEntry`
- **ColonyToolSafetyPolicy.swift** — Added doc comments to `RiskLevel` (5 cases), `RequirementReason`, `Disposition`, `RetryDisposition`, `ResultDurability`, `PolicyMetadata`
- **ColonyConfiguration.swift** — Added doc comments to top-level struct and all 4 nested configuration groups (`ModelConfiguration`, `SafetyConfiguration`, `ContextConfiguration`, `PromptConfiguration`)
- **ColonyInferenceSurface.swift** — Added doc comments to `ColonyChatRole`, `ColonyChatMessageOperation`, `ColonyTool.Definition/Call/Result`, `ColonyStructuredOutput/Payload`, `ColonyChatMessage`, `ColonyModelRequest/Response`, `ColonyModelStreamChunk`, `ColonyModelClient`, `ColonyToolRegistry`, `ColonyModelRouter`, `ColonyLatencyTier`, `ColonyNetworkState`, `ColonyInferenceHints`
- **ColonyID.swift** — Added doc comments to all 14 type aliases (`ColonyThreadID`, `ColonyInterruptID`, etc.)
- **ColonyTodo.swift** — Added doc comments to struct and `Status` enum
- **ColonyToolAudit.swift** — Added doc comments to full namespace doc, `DecisionKind`, `Event`, `RecordPayload`, `SignedRecord`, `AuditError`, `ColonyToolAuditSigner`, `ColonyImmutableToolAuditLogStore`, `FileSystemLogStore`, `Recorder`
- **ColonyToolApprovalRules.swift** — Added doc comments to `ColonyToolApprovalRuleDecision`, `ColonyToolApprovalPattern`, `ColonyToolApprovalRule`, `ColonyMatchedToolApprovalRule`, `ColonyToolApprovalRuleStore`
- **ColonyBudgetError.swift** — Added doc comments to enum
- **ColonyPrompts.swift** — Added namespace doc comment
- **ColonyShell.swift** — Added doc comments to `TerminalMode`, `ExecutionRequest`, `ExecutionResult`, `SessionOpenRequest`, `SessionReadResult`, `SessionSnapshot`, `ConfinementPolicy`, `ExecutionError`
- **ColonyFileSystem.swift** — Added doc comments to `VirtualPath`, `FileInfo`, `GrepMatch`, `Error`, `ColonyFileSystemBackend`, `DiskBackend`, `InMemoryBackend`

All files pass `swiftc -parse` verification. **P2 (Doc Comments) — COMPLETE ✅**

---

## Part 2: API Documentation Gaps

### 2.1 ColonyCore Types Need Doc Comments

**Audit Finding**: ~55 types in ColonyCore, many lack doc comments or have incomplete ones.

**Priority Types Needing Documentation**:

| Type | File | Gap | Status |
|------|------|-----|--------|
| `ColonyID<Domain>` | ColonyID.swift | Has doc but doesn't explain phantom domain pattern | **FIXED** ✅ |
| `ColonyTool.Name` + 39 constants | ColonyToolName.swift | Static constants not documented | **FIXED** ✅ |
| `ColonyTool.RiskLevel` | ColonyToolSafetyPolicy.swift | Enum cases not documented | **FIXED** ✅ |
| `ColonyTool.PolicyMetadata` | ColonyToolSafetyPolicy.swift | Struct fields not documented | **FIXED** ✅ |
| `ColonyModelClient` | ColonyInferenceSurface.swift | Protocol not documented | **FIXED** ✅ |
| `ColonyModelRouter` | ColonyInferenceSurface.swift | Protocol not documented | **FIXED** ✅ |
| `ColonyToolRegistry` | ColonyInferenceSurface.swift | Protocol not documented | **FIXED** ✅ |
| `ColonyConfiguration` + nested | ColonyConfiguration.swift | Nested structs not individually documented | **FIXED** ✅ |
| `ColonyArtifactKind` | ColonyArtifactStore.swift | Cases not documented | **FIXED** ✅ |
| `ColonyRun.Interrupt` | ColonyRuntimeSurface.swift | Fields not documented | **FIXED** ✅ |
| `ColonyTodo` | ColonyTodo.swift | Struct fields not documented | **FIXED** ✅ |
| `ColonyChatRole`, `ColonyChatMessage`, `ColonyModelRequest/Response`, `ColonyModelStreamChunk` | ColonyInferenceSurface.swift | Types not documented | **FIXED** ✅ |
| `ColonyTool.Definition/Call/Result` | ColonyInferenceSurface.swift | Types not documented | **FIXED** ✅ |
| `ColonyStructuredOutput`, `ColonyStructuredOutputPayload` | ColonyInferenceSurface.swift | Types not documented | **FIXED** ✅ |
| `ColonyLatencyTier`, `ColonyNetworkState`, `ColonyInferenceHints` | ColonyInferenceSurface.swift | Types not documented | **FIXED** ✅ |
| `ColonyToolApproval.Decision/Policy/PerToolDecision/PerToolEntry` | ColonyToolApproval.swift | Types not documented | **FIXED** ✅ |
| `ColonyToolApproval.RequirementReason/Disposition/RetryDisposition/ResultDurability` | ColonyToolSafetyPolicy.swift | Types not documented | **FIXED** ✅ |
| `ColonyToolAudit` namespace + 9 types | ColonyToolAudit.swift | Namespace and types not documented | **FIXED** ✅ |
| `ColonyToolApprovalRule/Pattern/Decision + ColonyToolApprovalRuleStore` | ColonyToolApprovalRules.swift | Types not documented | **FIXED** ✅ |
| `ColonyBudgetError` | ColonyBudgetError.swift | Type not documented | **FIXED** ✅ |
| `ColonyPrompts` | ColonyPrompts.swift | Namespace not documented | **FIXED** ✅ |

**Action**: Add doc comments to ALL public types per Swift documentation standards:
```swift
/// A type-safe identifier for [purpose].
///
/// Use `ColonyID<Domain>` when you want to prevent accidentally mixing
/// different kinds of IDs (e.g., thread IDs vs interrupt IDs).
///
/// ## Example
/// ```swift
/// let threadID = ColonyID<ColonyID.Thread>("my-thread")
/// let interruptID = ColonyID<ColonyID.Interrupt>("my-interrupt")
/// // These are different types — can't mix them
/// ```
public struct ColonyID<Domain>: Hashable, Codable, Sendable {
    // ...
}
```

### 2.2 Backend Protocols Need Usage Examples

**Status**: ColonyFileSystemBackend, ColonyShellBackend, ColonyGitBackend, ColonyLSPBackend, ColonyMemoryBackend, ColonySubagentRegistry all have protocol definitions but no usage documentation.

**Required Doc**: `docs/backends/`

```
docs/backends/
├── filesystem-backend.md     # How to implement ColonyFileSystemBackend
├── shell-backend.md         # How to implement ColonyShellBackend
├── git-backend.md           # How to implement ColonyGitBackend
├── memory-backend.md        # How to implement ColonyMemoryBackend
└── subagent-registry.md    # How to implement ColonySubagentRegistry
```

**Each doc should contain**:
1. Protocol requirements (what methods to implement)
2. Minimal implementation example
3. Production implementation tips
4. Testing strategy

### 2.3 Scratchbook Documentation Incomplete

**Status**: README.md lists scratchbook operations but doesn't explain:
- When scratchbook data persists
- How thread scoping works
- Pin behavior
- Offload and compaction policies

**Required Doc**: `docs/scratchbook.md`

---

## Part 3: Missing Conceptual Documentation

### 3.1 Architecture Overview

**Status**: No high-level architecture doc exists.

**Required Doc**: `docs/architecture.md`

**Content**:
```markdown
## Colony Architecture

### Products
- **Colony** — Primary product, umbrella for agent runtime
- **ColonyCore** — Pure protocols and policies
- **ColonySwarmInterop** — Swarm framework bridge
- **ColonyControlPlane** — Session and project management

### Dependency Graph
Colony → ColonyCore + Hive + Swarm + Membrane + Conduit
ColonySwarmInterop → Colony + Swarm
ColonyControlPlane → ColonyCore

### Key Abstractions
1. **ColonyRuntime** — The main agent runtime
2. **ColonyModelClient** — Model inference interface
3. **ColonyToolRegistry** — Tool definition and invocation
4. **ColonyMemoryBackend** — Memory/persistence interface
5. **ColonySubagentRegistry** — Subagent management

### Execution Model
[BSP superstep explanation]
```

### 3.2 Checkpoint and Resume System

**Status**: No documentation on checkpoint behavior.

**Required Doc**: `docs/checkpoint-resume.md`

**Content**:
```markdown
## Checkpoint and Resume

### When Checkpoints Are Created
- On tool approval interrupt
- Every N steps (configurable)
- On explicit request

### Checkpoint Contents
- Full conversation state
- Scratchbook state
- Pending tool calls
- Model context window

### Resume Process
1. Load checkpoint
2. Restore conversation state
3. Continue from interrupt point
4. Handle approval decision
```

### 3.3 Capability System

**Status**: ColonyAgentCapabilities exists but not documented.

**Required Doc**: `docs/capabilities.md`

**Content**:
```markdown
## Capability System

### Built-in Capabilities
- `.filesystem` — File operations
- `.shell` — Shell execution
- `.git` — Git operations
- `.lsp` — Language server protocol
- `.memory` — Memory operations
- `.subagents` — Subagent spawning
- `.webSearch` — Web search
- `.codeSearch` — Code search
- `.mcp` — Model Context Protocol
- `.plugins` — Plugin tools
- `.planning` — Planning tools
- `.conversationHistory` — History access
- `.largeToolResults` — Large output handling

### How Capabilities Gate Tools
Tools are only injected into prompts when their required capability is enabled.

### Configuring Capabilities
```swift
let config = ColonyConfiguration(
    modelName: "test-model",
    capabilities: [.filesystem, .shell, .git]
)
```
```

---

## Part 4: Example Documentation Gaps

### 4.1 Runnable Examples Needed

**Status**: README.md has snippets but not complete runnable examples.

**Required**: Complete, runnable examples for each major use case:

```
Examples/
├── 01-minimal-runtime.swift      # Just send a message, get a response
├── 02-with-filesystem.swift      # Enable file operations
├── 03-with-shell.swift           # Enable shell execution
├── 04-with-human-approval.swift  # Tool approval flow
├── 05-with-subagents.swift       # Spawning subagents
├── 06-with-memory.swift          # Using memory backend
├── 07-checkpoint-resume.swift    # Interrupt and resume
├── 08-on-device-4k.swift        # iOS/macOS on-device profile
├── 09-provider-routing.swift     # Multi-provider routing
└── 10-complete-agent.swift       # Full featured agent
```

### 4.2 DeepResearchApp Should Be Documented

**Status**: DeepResearchApp is a complete example but has no documentation.

**Required Doc**: `docs/apps/deep-research-app.md`

**Content**:
```markdown
## DeepResearchApp

A complete research assistant using Colony with:
- Ollama integration
- Conversation persistence
- Research phase tracking
- Insight extraction

### Architecture
[Explain the app structure]

### Customization Points
[How to adapt for different use cases]
```

---

## Part 5: Agent-Specific Documentation

### 5.1 AI Coding Agent Onboarding Guide

**Status**: Does not exist.

**Required Doc**: `docs/AGENTS.md` (primary onboarding doc for AI agents)

**Content**:
```markdown
# Colony — Prompt for Coding Agent

## What is Colony?

Colony is a local-first agent runtime in Swift. It provides:
- Deterministic agent execution with checkpoint/resume
- Capability-gated tools with human approval
- On-device 4k context budget enforcement
- Subagent orchestration
- Memory persistence via Wax

## Quick Start

### Minimal Example
```swift
import Colony

let runtime = try await Colony.agent(
    model: .foundationModels(),
    modelName: "your-model"
)

let outcome = try await runtime.sendUserMessage("Hello, agent!")
print(outcome)
```

### With Filesystem Access
```swift
import Colony

let runtime = try await Colony.agent(
    model: .foundationModels(),
    modelName: "your-model",
    capabilities: [.filesystem, .shell],
    services: ColonyServiceBuilder {
        .filesystem(ColonyDiskFileSystemBackend(root: projectURL))
    }
)
```

## Key Concepts

### ColonyRuntime
The main runtime. Methods:
- `sendUserMessage(_:)` — Send a message, get outcome
- `resumeToolApproval(interruptID:decision:)` — Resume after approval

### ColonyModel
Configures the AI model. Factories:
- `.foundationModels()` — Use Apple Foundation Models
- `.onDevice()` — Use on-device model with fallback
- `.providerRouting()` — Route between multiple providers

### ColonyConfiguration
3-tier configuration:
1. Just `modelName` — Minimal
2. Add `capabilities` and `toolApprovalPolicy` — Standard
3. Full control with nested config structs — Advanced

### Tool Approval
```swift
let handle = await runtime.sendUserMessage("Create a file")

if case let .interrupted(interrupt) = handle.outcome {
    if case let .toolApprovalRequired(calls) = interrupt.interrupt.payload {
        // Show to human for approval
        let resumed = await runtime.resumeToolApproval(
            interruptID: interrupt.interrupt.id,
            decision: .approved
        )
    }
}
```

## Common Patterns

### Pattern 1: Simple Agent
[Runnable code]

### Pattern 2: Agent with Tool Approval
[Runnable code]

### Pattern 3: Agent with Checkpointing
[Runnable code]

### Pattern 4: Multi-Agent Orchestration
[Runnable code]

## Troubleshooting

### "foundationModelsUnavailable"
On-device Foundation Models not available. Use `.providerRouting()` with Ollama or other provider.

### "tool not found"
Check that the required capability is enabled and backend is registered.

### Swift 6.2 Required
Colony requires Swift 6.2 and iOS/macOS 26+.

## API Reference

See [API docs link] for full type documentation.
```

### 5.2 Colony Skills for Claude Code

**Status**: No skills exist for using Colony with Claude Code.

**Required Files**:
```
.skills/
├── colony-expert/
│   └── SKILL.md              # Main skill definition
└── references/
    ├── quick-start.md        # 5-minute getting started
    ├── patterns.md           # Common usage patterns
    ├── troubleshooting.md    # FAQ and solutions
    └── api-reference.md      # Type-level documentation
```

**Content for `SKILL.md`**:
```markdown
# Colony Expert Skill

## Description
Guide for developing with Colony, a Swift 6.2 agent runtime framework.

## Triggers
- Questions about Colony APIs
- Issues with Colony runtime
- Tool approval flow
- Checkpoint/resume
- Subagent orchestration

## Instructions

When user asks about Colony:
1. Check if question matches patterns below
2. Provide runnable Swift code examples
3. Link to relevant docs

## Patterns

### "How do I create a runtime?"
```swift
let runtime = try await Colony.agent(
    model: .foundationModels(),
    modelName: "model-name"
)
```

### "How do I handle tool approval?"
[See tool-approval.md for full pattern]

### "How do I enable filesystem access?"
```swift
let runtime = try await Colony.agent(
    model: .foundationModels(),
    capabilities: [.filesystem],
    services: ColonyServiceBuilder {
        .filesystem(ColonyDiskFileSystemBackend(root: projectURL))
    }
)
```

## References
See references/ directory for detailed docs.
```

---

## Part 6: Test Documentation

### 6.1 Tests Should Serve as Documentation

**Status**: ColonyTests exist but test names don't fully explain behavior, and test files aren't organized as examples.

**Required Changes**:

1. **Organize tests by documentation topic**:
```
Tests/ColonyTests/
├── Documentation/
│   ├── ToolApprovalTests/
│   │   ├── tool_approval_basic.swift
│   │   ├── tool_approval_interrupt_resume.swift
│   │   └── tool_approval_rejection_handling.swift
│   ├── CheckpointResumeTests/
│   │   ├── checkpoint_creation.swift
│   │   ├── checkpoint_restoration.swift
│   │   └── interrupt_during_checkpoint.swift
│   └── ScratchbookTests/
│       ├── scratch_basic_operations.swift
│       ├── scratch_thread_scoping.swift
│       └── scratch_offload_policy.swift
```

2. **Add doc comments to test classes**:
```swift
/// Tests the tool approval interrupt and resume flow.
///
/// This test documents the complete lifecycle:
/// 1. Agent requests a risky tool
/// 2. Runtime interrupts with toolApprovalRequired
/// 3. Human approves
/// 4. Tool executes
/// 5. Agent receives result and continues
///
/// Related documentation:
/// - docs/tool-approval.md
/// - docs/checkpoint-resume.md
class ToolApprovalInterruptResumeTests: XCTestCase {
    // ...
}
```

### 6.2 Example-Based Tests

**Status**: Tests use mocking but don't show real usage patterns.

**Required**: Add example-based tests that serve as living documentation:
```swift
/// Example: Creating a minimal agent and sending a message
///
/// This is a minimal end-to-end test that documents the simplest
/// possible Colony usage:
///
/// ```swift
/// let runtime = try await Colony.agent(
///     model: .foundationModels(),
///     modelName: "test-model"
/// )
/// let outcome = try await runtime.sendUserMessage("Hello")
/// ```
func testMinimalAgentCreation() async throws {
    // Test implementation
}
```

---

## Part 7: Doc Infrastructure

### 7.1 Doc Generation Setup

**Status**: No doc generation pipeline exists.

**Required**:
1. Add SwiftDoc or similar for API documentation generation
2. Set up docs/ directory structure
3. Configure CI to build and publish docs

### 7.2 Doc Preview for PRs

**Status**: No way to preview docs before merging.

**Required**:
1. Add doc preview step to CI
2. Configure GitHub Pages deployment
3. Add preview link to PR comments

---

## Implementation Phases

### Phase 1: Critical Docs (Week 1)
- [x] P0: README.md non-runnable code examples — FIXED ✅ (2026-03-22)
- [x] `docs/AGENTS.md` (AI onboarding guide) — CREATED ✅ (2026-03-22)
- [x] `docs/runtime-loop.md` — CREATED ✅ (2026-03-22)
- [x] `docs/release/release-policy.md` — CREATED ✅ (2026-03-22)
- [x] `docs/release/upgrade-flow.md` — CREATED ✅ (2026-03-22)
- [ ] Add doc comments to top-20 most-used public types

### Phase 2: Conceptual Docs (Week 2)
- [ ] Create `docs/architecture.md`
- [ ] Create `docs/checkpoint-resume.md`
- [ ] Create `docs/capabilities.md`
- [ ] Create `docs/scratchbook.md`
- [ ] Create `docs/tool-approval.md`

### Phase 3: Backend Docs (Week 3)
- [ ] Create `docs/backends/` directory with all backend protocols
- [ ] Add doc comments to remaining ColonyCore types
- [ ] Add doc comments to Colony types

### Phase 4: Examples and Skills (Week 4)
- [ ] Create `Examples/` directory with 10 runnable examples
- [ ] Create `docs/apps/deep-research-app.md`
- [ ] Create `.skills/colony-expert/` with skill definition
- [ ] Create reference docs for skills

### Phase 5: Test Documentation (Week 5)
- [ ] Reorganize tests by documentation topic
- [ ] Add doc comments to all test classes
- [ ] Add example-based tests
- [ ] Document test patterns

### Phase 6: Infrastructure (Week 6)
- [ ] Set up SwiftDoc generation
- [ ] Configure doc preview in CI
- [ ] Set up GitHub Pages deployment
- [ ] Create doc contribution guidelines

---

## Verification

After each phase:
1. Run all examples to verify they compile and produce expected output
2. Have AI agent try to use Colony from the new documentation alone
3. Review doc coverage against full public API surface
4. Get feedback from developers who try the onboarding guide

---

## Success Metrics

- [ ] Every public type has doc comments
- [ ] Every workflow has runnable code example
- [ ] AI agent can create and use Colony runtime from docs alone
- [ ] New contributor can implement a backend protocol from docs alone
- [ ] Upgrade guide exists for each version
- [ ] Examples directory covers 90% of common use cases
- [ ] Skill exists for Colony in Claude Code
