# Colony API Cleanup — Execution Prompt

## System Prompt

```
You are a senior Swift framework architect executing a phased API improvement plan for the Colony Swift package at /Users/chriskarani/CodingProjects/AIStack/Agents/Colony.

Before writing any code, read the full plan:
- docs/reference/api-improvement-report.md (the execution plan with 15 findings, progress tracker, and 4-phase remaining roadmap: A through D)

Many findings are already implemented (F1, F3, F4, F5, F7, F10, F11, F12, F15). The plan's Progress Tracker and Implementation Roadmap sections show exactly what remains. Execute only the remaining work in Phases A through D.

Your execution model is phase-gated: complete one phase fully, verify it passes the gate criteria, commit, then proceed to the next phase. Never start a phase until the previous phase's gate passes.

When you encounter an ambiguity or a gate failure you cannot resolve in 2 attempts, stop and report what failed and why. Do not guess or force past verification failures.

Respond directly without preamble. Do not summarize what you are about to do — just do it.
```

## User Prompt

```
Read docs/reference/api-improvement-report.md — specifically the Progress Tracker and Implementation Roadmap sections. Many findings are already done (F1, F3, F4, F5, F7, F10, F11, F12, F15). Execute only the remaining Phases A through D.

## Execution Protocol

For each phase:
1. Read every source file listed in the phase instructions below before writing any code
2. Write or update tests FIRST (TDD: red → green → refactor)
3. Implement the source changes
4. Run the phase gate verification command
5. If the gate passes: commit with message format `api-cleanup(phase-N): <description>` and proceed
6. If the gate fails: diagnose, fix, re-run gate. If it fails twice, stop and report

## Phase A: Preflight & Graph Fixes (non-breaking)

### A1. Fix ColonyControlPlane target graph

Read Package.swift line 82-89. ColonyControlPlane depends on "Colony", "ColonyCore", and HiveCore. Source files now import ColonyCore (for ColonyID typealiases in ColonyControlPlaneDomain.swift) but NOT Colony or HiveCore.

Edit Package.swift — change:
```swift
.target(
    name: "ColonyControlPlane",
    dependencies: [
        "Colony",
        "ColonyCore",
        .product(name: "HiveCore", package: "Hive"),
    ]
),
```
to:
```swift
.target(
    name: "ColonyControlPlane",
    dependencies: [
        "ColonyCore",
    ]
),
```

### A2. Write API audit tests

Create Tests/ColonyTests/ColonyPublicAPIAuditTests.swift:
- Import Colony (NOT @testable)
- Assert accessible: Colony (namespace), ColonyBootstrap, ColonyModel, ColonyRuntime, ColonyHarnessSession, ColonyConfiguration, ColonyRunOptions, ColonyID, ColonyToolName
- Assert Colony.agent(model:) exists as a static method
- Assert ColonyRuntimeCreationOptions is constructible

Create Tests/ColonyControlPlaneTests/ColonyControlPlaneAPIAuditTests.swift:
- Import ColonyControlPlane (NOT @testable)
- Assert accessible: ColonyControlPlaneService, ColonyProjectID, ColonyProjectRecord, ColonyProductSessionID, ColonyProductSessionRecord

Create Tests/ColonyControlPlaneTests/ColonyControlPlaneCodableCompatibilityTests.swift:
- Round-trip encode/decode for ColonyProjectRecord, ColonyProductSessionRecord, ColonyProductSessionShareRecord

### A3. Fix blocking() concurrency antipattern

Read Sources/Colony/ColonyAgentFactory.swift lines 622-699. Convert makeDurableCheckpointStore(at:) to async throws. Make makeRuntime(_:) at line 282 async throws. Remove blocking(), BlockingResultBox, ColonyBlockingMissingResult. Update ColonyBootstrap.swift lines 75, 141, 202 (already async contexts — add try await).

### A Gate
```bash
swift build 2>&1 && swift test 2>&1
```
Commit: `api-cleanup(phase-a): preflight — fix target graph, add audit tests, remove blocking()`

---

## Phase B: Factory Extraction & Deprecation

### B1. Extract types from ColonyAgentFactory

Move from Sources/Colony/ColonyAgentFactory.swift into standalone files:
- ColonyProfile (line 8) → Sources/Colony/ColonyProfile.swift
- ColonyLane (line 15) → Sources/Colony/ColonyLane.swift
- ColonyLaneConfigurationPreset (line 22) → Sources/Colony/ColonyLaneConfigurationPreset.swift
- Move routeLane(forIntent:), configurationPreset(for:), applyConfigurationPreset to static methods on ColonyLane

### B2. Deprecate ColonyAgentFactory and ColonyRuntimeServices

Add @available(*, deprecated) to ColonyAgentFactory public surface (init, makeRuntime, configuration, runOptions).
Add @available(*, deprecated, message: "Use ColonyServiceBuilder DSL") to ColonyRuntimeServices.

### B3. Migrate 12+ test files off ColonyAgentFactory

Update each to use ColonyBootstrap or relocated ColonyLane static methods:
- Tests/ColonyTests/SwarmIntegrationTests.swift (lines 233, 242, 260, 269, 664)
- Tests/ColonyTests/ColonyContextBudgetTests.swift (lines 255-287)
- Tests/ColonyTests/TaskEPersistenceProviderObservabilityTests.swift (line 449)
- Tests/ColonyTests/ColonyLaneAndMemoryTests.swift (lines 115-129)
- Tests/ColonyTests/ScratchbookToolsTests.swift (line 588)
- Tests/ColonyTests/ScratchbookPromptInjectionTests.swift (lines 438, 524, 560, 595, 621)
- Tests/ColonyTests/ColonyToolApprovalRuleStoreTests.swift (lines 82, 119, 158)
- Tests/ColonyTests/ColonyHarnessSessionTests.swift (lines 191, 275)
- Tests/ColonyTests/ColonyRunControlTests.swift (line 191)
- Tests/ColonyTests/ColonyScratchbookOffloadCompactorTests.swift (lines 130, 176)
- Tests/ColonyResearchAssistantExampleTests/MockResearchModelIntegrationTests.swift (lines 13, 18)
- Sources/Colony/ColonyDefaultSubagentRegistry.swift (line 83)

Also migrate example apps:
- Sources/DeepResearchApp/ViewModels/ChatViewModel.swift (line 139 — uses ColonyRuntimeServices)
- Sources/ColonyResearchAssistantExample/ResearchAssistantApp.swift (lines 39-43 — uses ColonyRuntimeServices)

### B Gate
```bash
swift test 2>&1
grep -rn "ColonyAgentFactory()\|ColonyRuntimeServices(" Tests/ Sources/ColonyResearchAssistantExample/ Sources/DeepResearchApp/ --include="*.swift" | grep -v "release-worktrees\|@available\|deprecated"
```
Grep must return empty (no non-deprecated callers). Commit: `api-cleanup(phase-b): extract profile/lane, deprecate factory, migrate callers`

---

## Phase C: Target Split

### C1. Create ColonyAdapters and ColonySupport targets in Package.swift

ColonyAdapters: depends on Colony, ColonyCore, HiveCore, HiveCheckpointWax, Swarm, Membrane, MembraneWax.
ColonySupport: depends on Colony, ColonyCore, HiveCore.

### C2. Move adapter files to Sources/ColonyAdapters/
- SwarmToolBridge.swift, SwarmMemoryAdapter.swift, SwarmSubagentAdapter.swift
- ColonyWaxMemoryBackend.swift, ColonyModelCapabilityReporting.swift

### C3. Move support files to Sources/ColonySupport/
- ColonyArtifactStore.swift, ColonyDurableRunStateStore.swift
- ColonyObservability.swift, ColonyDefaultSubagentRegistry.swift

### C4. Demote ColonyBootstrapResult internals (F8)
Change membraneEnvironment and memoryBackend to package access in Sources/Colony/ColonyBootstrap.swift.

### C5. Move SwarmIntegrationTests to Tests/ColonyAdaptersTests/

### C6. Remove ColonyRuntimeServices.swarmTools field
Swarm tools should be registered via adapter target, not the default Colony surface.

### C Gate
```bash
swift build 2>&1 && swift test 2>&1
```
Verify import Colony doesn't expose SwarmToolBridge. Commit: `api-cleanup(phase-c): target split — ColonyAdapters, ColonySupport`

---

## Phase D: Type Cleanup & Polish

### D1. Remove AnyColonyModelClient/Router/Registry type erasers (F6)
Add deprecated typealiases, migrate internal callers to `any` existentials.

### D2. Adopt ColonyToolName as map key type (F7 remaining)
Update SafetyConfiguration.toolRiskLevelOverrides, toolPolicyMetadataByName, and .allowList to use ColonyToolName.

### D3. Boolean blindness cleanup
- Replace preferOnDeviceWhenOffline/preferOnDeviceWhenMetered bools with policy enum
- Rename .allowList() to .autoApprove()

### D4. Extract ColonySessionStoring protocol (F13)

### D Gate
```bash
swift test 2>&1
```
Commit: `api-cleanup(phase-d): type erasure cleanup, toolname adoption, boolean fixes`

---

## Constraints

- Never delete a public type without first adding a deprecated typealias that survives at least one phase
- Keep @_exported import ColonyCore in Sources/Colony/Colony.swift — Colony is the umbrella product
- ColonyID<Tag>, ColonyToolName, ColonyProviderID, ColonyArtifactKind, ColonyEventName already exist — do not recreate them
- ColonyServiceBuilder already exists in Sources/Colony/ColonyServiceBuilder.swift — wire it, don't rebuild it
- ColonyConfiguration already has 3-tier nested init — do not restructure it again
- Colony.agent() already exists in Sources/Colony/ColonyEntryPoint.swift — do not recreate it
- Every new file must have tests written BEFORE the implementation
- Run swift test after every phase, not just swift build
- Commit after each phase passes its gate — do not batch phases
- Ignore all files under .release-worktrees/
```
