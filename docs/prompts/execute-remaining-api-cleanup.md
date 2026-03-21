# Colony API Cleanup — Remaining Work Execution Prompt

## System Prompt

```
You are a senior Swift 6.2 framework architect completing an API cleanup for the Colony Swift package at /Users/chriskarani/CodingProjects/AIStack/Agents/Colony.

Prior work has already completed 10 of 15 findings:
- ColonyID<Domain> generic IDs (Sources/ColonyCore/ColonyID.swift)
- ColonyToolName strong wrapper (Sources/ColonyCore/ColonyToolName.swift)
- ColonyProviderID strong wrapper (Sources/Colony/ColonyPublicAPI.swift:51-65)
- ColonyArtifactKind strong wrapper (Sources/Colony/ColonyArtifactStore.swift)
- ColonyEventName strong wrapper (Sources/Colony/ColonyObservability.swift)
- ColonyConfiguration 3-tier nested init (Sources/ColonyCore/ColonyConfiguration.swift)
- Colony.agent() entry point (Sources/Colony/ColonyEntryPoint.swift)
- ColonyServiceBuilder result builder (Sources/Colony/ColonyServiceBuilder.swift)
- @_exported import Swarm removed (Sources/Colony/Colony.swift)
- AnyColonyModelClient/Router/Registry type erasers removed
- ColonyModelRouter.route() returns any ColonyModelClient
- ColonyProvider.client uses any ColonyModelClient

DO NOT recreate or modify any of these. They are done and tested.

Your execution model is phase-gated. Complete one phase, verify it passes the gate, commit, then proceed. If a gate fails twice, stop and report.
```

## User Prompt

```
Execute the remaining 4 phases of the Colony API cleanup. Read docs/reference/api-improvement-report.md for full context — the Progress Tracker and Implementation Roadmap sections describe what is done and what remains.

## Execution Protocol

For each phase:
1. Read every source file listed before writing code
2. Write tests FIRST (TDD)
3. Implement changes
4. Run gate command
5. If pass: commit as `api-cleanup(phase-X): <description>` and proceed
6. If fail twice: stop and report

---

## Phase A: Preflight & Graph Fixes

### A1. Fix ColonyControlPlane target dependencies

Read Package.swift lines 82-89. The ColonyControlPlane target currently depends on "Colony", "ColonyCore", and HiveCore.

Read every file in Sources/ColonyControlPlane/:
- ColonyControlPlaneDomain.swift imports ColonyCore (for ColonyID typealiases at lines 7-10)
- ColonyControlPlaneService.swift imports Foundation only
- ColonyControlPlaneTransport.swift imports Foundation only
- ColonyProjectStore.swift imports Foundation only
- ColonySessionStore.swift imports Foundation only

The Colony and HiveCore dependencies are unused. Change Package.swift from:
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
```swift
import Testing
import Colony

@Test("Colony public API surface is accessible without @testable")
func colonyPublicAPISurface() {
    // Namespace
    _ = Colony.version

    // Construction
    _ = ColonyBootstrap.self
    _ = ColonyModel.self
    _ = ColonyRuntime.self
    _ = ColonyConfiguration.self
    _ = ColonyRunOptions.self
    _ = ColonyRuntimeCreationOptions.self
    _ = ColonyBootstrapOptions.self

    // IDs
    let _: ColonyThreadID = "test"
    let _: ColonyInterruptID = "test"

    // Strong strings
    _ = ColonyToolName.readFile
    _ = ColonyProviderID.anthropic

    // Service builder
    _ = ColonyService.self
    _ = ColonyServiceBuilder.self
}
```

Create Tests/ColonyControlPlaneTests/ColonyControlPlaneAPIAuditTests.swift:
```swift
import Testing
import ColonyControlPlane
import ColonyCore

@Test("ColonyControlPlane public API surface is accessible")
func controlPlaneAPISurface() {
    _ = ColonyControlPlaneService.self
    let _: ColonyProjectID = "proj-1"
    let _: ColonyProductSessionID = "sess-1"
    let _: ColonySessionShareToken = "tok-1"
    _ = ColonyProjectRecord.self
    _ = ColonyProductSessionRecord.self
}
```

Create Tests/ColonyControlPlaneTests/ColonyControlPlaneCodableCompatibilityTests.swift:
```swift
import Testing
import Foundation
import ColonyControlPlane
import ColonyCore

@Test("ColonyProjectRecord round-trips through JSON")
func projectRecordCodable() throws {
    let record = ColonyProjectRecord(
        projectID: "p1",
        name: "Test",
        metadata: ["key": "value"],
        createdAt: Date(timeIntervalSince1970: 1000),
        updatedAt: Date(timeIntervalSince1970: 2000)
    )
    let data = try JSONEncoder().encode(record)
    let decoded = try JSONDecoder().decode(ColonyProjectRecord.self, from: data)
    #expect(decoded == record)
}

@Test("ColonyProductSessionRecord round-trips through JSON")
func sessionRecordCodable() throws {
    let version = ColonyProductSessionVersionRecord(
        versionID: "v1",
        createdAt: Date(timeIntervalSince1970: 1000),
        metadata: [:]
    )
    let record = ColonyProductSessionRecord(
        sessionID: "s1",
        projectID: "p1",
        metadata: ["k": "v"],
        createdAt: Date(timeIntervalSince1970: 1000),
        updatedAt: Date(timeIntervalSince1970: 2000),
        versionLineage: [version],
        activeVersionID: "v1",
        shareRecord: nil
    )
    let data = try JSONEncoder().encode(record)
    let decoded = try JSONDecoder().decode(ColonyProductSessionRecord.self, from: data)
    #expect(decoded == record)
}

@Test("ColonyProductSessionShareRecord round-trips through JSON")
func shareRecordCodable() throws {
    let record = ColonyProductSessionShareRecord(
        token: "tok-1",
        createdAt: Date(timeIntervalSince1970: 1000),
        updatedAt: Date(timeIntervalSince1970: 2000),
        metadata: ["shared": "true"]
    )
    let data = try JSONEncoder().encode(record)
    let decoded = try JSONDecoder().decode(ColonyProductSessionShareRecord.self, from: data)
    #expect(decoded == record)
}
```

### A3. Fix blocking() concurrency antipattern

Read Sources/Colony/ColonyAgentFactory.swift.

The `blocking()` method at line 659 uses DispatchSemaphore to bridge async→sync. `BlockingResultBox` at line 682 and `ColonyBlockingMissingResult` at line 699 support it.

The only caller is `makeDurableCheckpointStore(at:)` at line 634 (private static, synchronous) which is called by `makeRuntime(_:)` at line 293 (public).

Fix:
1. Make `makeDurableCheckpointStore(at:)` call `makeDurableCheckpointStoreAsync(at:)` directly — it already exists at line 642 as the async version
2. Make `makeRuntime(_ options: ColonyRuntimeCreationOptions)` at line 293 `async throws` instead of `throws`
3. Remove:
   - `blocking()` method (lines 659-679)
   - `BlockingResultBox` class (lines 682-697)
   - `ColonyBlockingMissingResult` struct (line 699)
4. Update callers in ColonyBootstrap.swift (lines 75, 141, 202) — these are already in async contexts, just add `await`:
   - Line 75: `return try await ColonyAgentFactory().makeRuntime(runtimeOptions)`
   - Line 141: `return try await ColonyAgentFactory().makeRuntime(`
   - Line 202: `let runtime = try await ColonyAgentFactory().makeRuntime(runtimeOptions)`

### A-Gate

```bash
swift build 2>&1 && swift test --filter ColonyPublicAPIAudit 2>&1 && swift test --filter ColonyControlPlaneAPIAudit 2>&1 && swift test --filter ColonyControlPlaneCodableCompatibility 2>&1 && swift test 2>&1
```

Commit: `api-cleanup(phase-a): fix target graph, add audit tests, remove blocking() antipattern`

---

## Phase B: Factory Extraction & Deprecation

### B1. Extract types from ColonyAgentFactory.swift

Read Sources/Colony/ColonyAgentFactory.swift.

Move these types to standalone files:

**Sources/Colony/ColonyProfile.swift** — move `ColonyProfile` enum (line 8-13):
```swift
public enum ColonyProfile: Sendable {
    case onDevice4k
    case cloud
}
```

**Sources/Colony/ColonyLane.swift** — move `ColonyLane` enum (line 15-20) and relocate routing/preset logic as static methods:
```swift
public enum ColonyLane: String, Sendable, CaseIterable {
    case general
    case coding
    case research
    case memory
}

extension ColonyLane {
    // Move from ColonyAgentFactory.routeLane(forIntent:)
    public static func route(forIntent intent: String) -> ColonyLane { ... }

    // Move from ColonyAgentFactory.configurationPreset(for:)
    public static func configurationPreset(for lane: ColonyLane) -> ColonyLaneConfigurationPreset { ... }

    // Move from ColonyAgentFactory.applyConfigurationPreset(_:to:)
    public static func applyPreset(_ preset: ColonyLaneConfigurationPreset, to configuration: inout ColonyConfiguration) { ... }
}
```

**Sources/Colony/ColonyLaneConfigurationPreset.swift** — move struct (line 22-36).

After moving, update ColonyAgentFactory to call the relocated methods:
- Line 79 `configuration(profile:modelName:)` should call `ColonyLane.configurationPreset(for:)` and `ColonyLane.applyPreset(_:to:)` instead of local methods
- Delete the now-empty original methods from ColonyAgentFactory (keep the `configuration` methods as deprecated forwarding shims)

Update Sources/Colony/ColonyDefaultSubagentRegistry.swift line 83:
```swift
// FROM:
var configuration = ColonyAgentFactory.configuration(profile: profile, modelName: modelName)
// TO — call the factory's configuration method directly (it still exists, just deprecated)
// OR call a new static on ColonyProfile/ColonyLane
```

### B2. Deprecate ColonyAgentFactory public surface

Add to Sources/Colony/ColonyAgentFactory.swift:
```swift
@available(*, deprecated, message: "Use ColonyBootstrap directly")
```
to these declarations:
- `public struct ColonyAgentFactory` (line 76)
- OR to individual public methods: `configuration(profile:modelName:)` (line 79), `configuration(profile:modelName:lane:)` (line 166), `makeRuntime(_:)` (line 293), `runOptions(profile:)` (line 276)

### B3. Deprecate ColonyRuntimeServices

In Sources/Colony/ColonyPublicAPI.swift, add to the struct at line 189:
```swift
@available(*, deprecated, message: "Use @ColonyServiceBuilder DSL via Colony.agent(model:services:)")
public struct ColonyRuntimeServices: Sendable {
```

### B4. Migrate test files off ColonyAgentFactory

Update each test file to use ColonyBootstrap or relocated static methods. The key patterns:

**Pattern 1: Replace `ColonyAgentFactory().makeRuntime(...)`**
```swift
// FROM:
let runtime = try ColonyAgentFactory().makeRuntime(profile: ..., modelName: ..., model: ..., ...)
// TO:
let runtime = try await ColonyBootstrap().makeRuntime(profile: ..., modelName: ..., model: ..., ...)
```

Files using this pattern (replace every occurrence):
- Tests/ColonyTests/SwarmIntegrationTests.swift: lines 243, 270, 665
- Tests/ColonyTests/TaskEPersistenceProviderObservabilityTests.swift: line 449
- Tests/ColonyTests/ColonyToolApprovalRuleStoreTests.swift: lines 82, 119, 158
- Tests/ColonyTests/ColonyHarnessSessionTests.swift: lines 191, 275
- Tests/ColonyTests/ColonyRunControlTests.swift: line 191
- Tests/ColonyTests/ScratchbookPromptInjectionTests.swift: lines 523, 559, 594, 620

**Pattern 2: Replace `ColonyAgentFactory.configuration(...)`**
```swift
// FROM:
let config = ColonyAgentFactory.configuration(profile: .onDevice4k, modelName: "test-model")
// TO:
let config = ColonyConfiguration(modelName: "test-model")
// OR for profile-specific defaults, use the still-available (deprecated) factory method
```

Files using this pattern:
- Tests/ColonyTests/ColonyContextBudgetTests.swift: lines 256, 287
- Tests/ColonyTests/ColonyLaneAndMemoryTests.swift: lines 122, 129
- Tests/ColonyTests/ScratchbookToolsTests.swift: line 583
- Tests/ColonyTests/ScratchbookPromptInjectionTests.swift: lines 437, 438
- Tests/ColonyTests/ColonyScratchbookOffloadCompactorTests.swift: lines 130, 176

**Pattern 3: Replace `ColonyAgentFactory.routeLane(forIntent:)`**
```swift
// FROM:
ColonyAgentFactory.routeLane(forIntent: "Fix this Swift build error")
// TO:
ColonyLane.route(forIntent: "Fix this Swift build error")
```

Files: Tests/ColonyTests/ColonyLaneAndMemoryTests.swift: lines 115-117

**Pattern 4: Replace `ColonyAgentFactory()` + `ColonyRuntimeServices()`**
```swift
// FROM:
let factory = ColonyAgentFactory()
let runtime = try factory.makeRuntime(.init(..., services: ColonyRuntimeServices(filesystem: fs), ...))
// TO:
let runtime = try await ColonyBootstrap().makeRuntime(options: .init(..., services: ColonyRuntimeServices(filesystem: fs), ...))
// Note: ColonyRuntimeServices is deprecated but still compiles — tests can migrate to builder DSL later
```

Files:
- Tests/ColonyTests/ColonyContextBudgetTests.swift: line 255
- Tests/ColonyResearchAssistantExampleTests/MockResearchModelIntegrationTests.swift: lines 13, 18

### B5. Migrate example apps

Sources/DeepResearchApp/ViewModels/ChatViewModel.swift line 139 — already uses ColonyBootstrap, just uses deprecated ColonyRuntimeServices. Leave as-is (it compiles with the deprecation warning).

Sources/ColonyResearchAssistantExample/ResearchAssistantApp.swift line 43 — same pattern, leave as-is.

### B-Gate

```bash
swift test 2>&1
```

Verify no non-deprecated references remain:
```bash
grep -rn "ColonyAgentFactory()\|ColonyAgentFactory\.configuration\|ColonyAgentFactory\.routeLane\|ColonyAgentFactory\.runOptions" Tests/ Sources/Colony/ColonyDefaultSubagentRegistry.swift --include="*.swift" | grep -v "release-worktrees\|@available\|deprecated\|// FROM\|// TO"
```
This must return empty. Commit: `api-cleanup(phase-b): extract profile/lane, deprecate factory, migrate callers`

---

## Phase C: Target Split

### C1. Create new targets

Add to Package.swift products:
```swift
.library(name: "ColonyAdapters", targets: ["ColonyAdapters"]),
.library(name: "ColonySupport", targets: ["ColonySupport"]),
```

Add to Package.swift targets:
```swift
.target(
    name: "ColonyAdapters",
    dependencies: [
        "Colony",
        "ColonyCore",
        .product(name: "HiveCore", package: "Hive"),
        .product(name: "HiveCheckpointWax", package: "Hive"),
        .product(name: "Swarm", package: "Swarm"),
        .product(name: "Membrane", package: "Membrane"),
        .product(name: "MembraneWax", package: "Membrane"),
    ]
),
.target(
    name: "ColonySupport",
    dependencies: [
        "Colony",
        "ColonyCore",
        .product(name: "HiveCore", package: "Hive"),
    ]
),
.testTarget(
    name: "ColonyAdaptersTests",
    dependencies: [
        "ColonyAdapters",
        "Colony",
        .product(name: "Swarm", package: "Swarm"),
        .product(name: "Membrane", package: "Membrane"),
    ]
),
```

Create directories: Sources/ColonyAdapters/, Sources/ColonySupport/, Tests/ColonyAdaptersTests/

### C2. Move adapter files

Move from Sources/Colony/ to Sources/ColonyAdapters/:
- SwarmToolBridge.swift
- SwarmMemoryAdapter.swift
- SwarmSubagentAdapter.swift
- ColonyWaxMemoryBackend.swift
- ColonyModelCapabilityReporting.swift

Update import statements in moved files — add `import Colony` and `import ColonyCore` if not already present.

### C3. Move support files

Move from Sources/Colony/ to Sources/ColonySupport/:
- ColonyArtifactStore.swift
- ColonyDurableRunStateStore.swift
- ColonyObservability.swift
- ColonyDefaultSubagentRegistry.swift

Update import statements in moved files.

### C4. Move SwarmIntegrationTests

Move Tests/ColonyTests/SwarmIntegrationTests.swift to Tests/ColonyAdaptersTests/SwarmIntegrationTests.swift.
Update imports to add `import ColonyAdapters`.

### C5. Demote ColonyBootstrapResult internals (F8)

In Sources/Colony/ColonyBootstrap.swift lines 11-25, change:
```swift
public struct ColonyBootstrapResult: Sendable {
    public let runtime: ColonyRuntime
    public let membraneEnvironment: MembraneEnvironment      // ← change to package
    public let memoryBackend: any ColonyMemoryBackend          // ← change to package
```
to:
```swift
public struct ColonyBootstrapResult: Sendable {
    public let runtime: ColonyRuntime
    package let membraneEnvironment: MembraneEnvironment
    package let memoryBackend: any ColonyMemoryBackend
```

Update the public init to package init.

### C6. Remove swarmTools from ColonyRuntimeServices

In Sources/Colony/ColonyPublicAPI.swift, remove the `swarmTools: SwarmToolBridge?` field from `ColonyRuntimeServices` (line 191) and its init parameter (line 207). Also remove the `.swarmTools(SwarmToolBridge)` case from `ColonyService` enum in Sources/Colony/ColonyServiceBuilder.swift (line 27) and its handler (line 78).

Swarm tools should be registered via ColonyAdapters, not the default Colony surface.

### C-Gate

```bash
swift build 2>&1 && swift test 2>&1
```

Commit: `api-cleanup(phase-c): target split — ColonyAdapters and ColonySupport`

---

## Phase D: Remaining Polish

### D1. Adopt ColonyToolName as map key type

In Sources/ColonyCore/ColonyConfiguration.swift, the SafetyConfiguration (line 59) still uses String keys:
```swift
public var toolRiskLevelOverrides: [String: ColonyToolRiskLevel]
public var toolPolicyMetadataByName: [String: ColonyToolPolicyMetadata]
```

Change to:
```swift
public var toolRiskLevelOverrides: [ColonyToolName: ColonyToolRiskLevel]
public var toolPolicyMetadataByName: [ColonyToolName: ColonyToolPolicyMetadata]
```

Update all callers that populate these maps (grep for `toolRiskLevelOverrides\[` and `toolPolicyMetadataByName\[`).

In Sources/ColonyCore/ColonyToolApproval.swift line 115, change `.allowList(Set<String>)` to `.allowList(Set<ColonyToolName>)` and update the factory method at line 117:
```swift
public static func allowList(_ allowed: [ColonyToolName]) -> ColonyToolApprovalPolicy {
    .allowList(Set(allowed))
}
// Backward compat:
public static func allowList(_ allowed: [String]) -> ColonyToolApprovalPolicy {
    .allowList(Set(allowed.map { ColonyToolName(rawValue: $0) }))
}
```

### D2. Rename allowList to autoApprove

In Sources/ColonyCore/ColonyToolApproval.swift:
```swift
// Rename the enum case:
case autoApprove(Set<ColonyToolName>)

// Add deprecated shim:
@available(*, deprecated, renamed: "autoApprove")
public static func allowList(_ allowed: [String]) -> ColonyToolApprovalPolicy {
    .autoApprove(Set(allowed.map { ColonyToolName(rawValue: $0) }))
}
```

Update all callers:
- Sources/ColonyCore/ColonyConfiguration.swift line 19 and 71: `.allowList(...)` → `.autoApprove(...)`
- Sources/Colony/ColonyAgentFactory.swift line 91: `.allowList(...)` → `.autoApprove(...)`
- Sources/ColonyResearchAssistantExample/ResearchAssistantApp.swift: `.allowList(...)` → `.autoApprove(...)`
- Sources/ColonyCore/ColonyToolSafetyPolicy.swift: `case .allowList:` → `case .autoApprove:`

### D3. Replace boolean blindness in ColonyOnDeviceModelPolicy

In Sources/Colony/ColonyPublicAPI.swift lines 29-47, replace:
```swift
public var preferOnDeviceWhenOffline: Bool
public var preferOnDeviceWhenMetered: Bool
```
with:
```swift
public struct NetworkFallbackPolicy: OptionSet, Sendable, Equatable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let preferWhenOffline = NetworkFallbackPolicy(rawValue: 1 << 0)
    public static let preferWhenMetered = NetworkFallbackPolicy(rawValue: 1 << 1)
    public static let `default`: NetworkFallbackPolicy = [.preferWhenOffline, .preferWhenMetered]
}
public var networkFallback: NetworkFallbackPolicy
```

Update callers:
- Sources/Colony/ColonyOnDeviceModelRouter.swift lines 26-27, 31-36, 83, 85, 116, 118
- Sources/Colony/ColonyAgentFactory.swift lines 574-575

### D4. Extract ColonySessionStoring protocol (F13)

Read Sources/ColonyControlPlane/ColonySessionStore.swift. It is a concrete actor. Extract a protocol:
```swift
public protocol ColonySessionStoring: Sendable {
    func createSession(_ input: ColonySessionCreateInput) async throws -> ColonyProductSessionRecord
    func getSession(id: ColonyProductSessionID) async -> ColonyProductSessionRecord?
    func listSessions(projectID: ColonyProjectID?) async -> [ColonyProductSessionRecord]
    func deleteSession(id: ColonyProductSessionID) async -> Bool
    func forkSession(_ input: ColonySessionForkInput) async throws -> ColonyProductSessionRecord
    func revertSession(sessionID: ColonyProductSessionID) async throws -> ColonyProductSessionRecord
    func shareSession(_ input: ColonySessionShareInput) async throws -> ColonyProductSessionShareRecord
}
```

Make `ColonySessionStore` conform to `ColonySessionStoring`. Update `ColonyControlPlaneService` to accept `any ColonySessionStoring` instead of concrete `ColonySessionStore`.

### D-Gate

```bash
swift test 2>&1
```

Commit: `api-cleanup(phase-d): adopt ColonyToolName keys, rename allowList, fix boolean blindness, extract session protocol`

---

## Constraints

- DO NOT recreate or modify: ColonyID.swift, ColonyToolName.swift, ColonyConfiguration.swift nested init, ColonyEntryPoint.swift, ColonyServiceBuilder.swift, Colony.swift — these are done
- Never delete a public type without adding a deprecated shim that survives at least one phase
- Keep @_exported import ColonyCore in Colony.swift
- Write tests BEFORE implementation for every new file
- Run swift test after every phase, not just swift build
- Commit after each phase gate passes — do not batch phases
- Ignore .release-worktrees/ in all grep operations
- If ColonyBootstrap.swift imports change due to file moves in Phase C, update them — ColonyBootstrap still needs to access adapter types internally via import ColonyAdapters
```
