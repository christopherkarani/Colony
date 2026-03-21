# Colony API Audit Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all 8 critical, 13 medium, and 9 low issues from `docs/reference/api-final-audit.md` to raise Agent DX from 69/100 to 90+.

**Architecture:** Six sequential phases ordered by dependency — quick wins first, then type safety completion, cross-module isolation, Swarm interop cleanup, the `@_exported` removal, and finally Sendable/naming fixes. Each phase produces a compilable state.

**Tech Stack:** Swift 6.2, phantom-type generics (`ColonyID<Domain>`), `some`/`any` existentials, `@resultBuilder`, `ExpressibleByStringLiteral` newtypes.

**Spec Reference:** `docs/reference/api-final-audit.md`

---

## Phase 1: Quick Wins (non-breaking, access control)

Covers: M1, M8, M11, M12, L2, L7/L9

### Task 1: Demote in-memory test doubles to `package` access

**Files:**
- Modify: `Sources/Colony/ColonyObservability.swift:58`
- Modify: `Sources/ColonyCore/ColonyMemory.swift:72`
- Modify: `Sources/ColonyCore/ColonyFileSystem.swift:110`
- Modify: `Sources/ColonyCore/ColonyToolApprovalRules.swift:77`
- Modify: `Sources/ColonyCore/ColonyToolAudit.swift:116`
- Modify: `Sources/ColonyCore/ColonyTokenizer.swift:12`
- Modify: `Sources/ColonyControlPlane/ColonyProjectStore.swift:10`
- Modify: `Sources/ColonyControlPlane/ColonySessionStore.swift:3`
- Modify: `Tests/ColonyTests/*.swift` (update any test files that reference these types)

**Issues Fixed:** M1 (8 test doubles), M11 (ColonyDefaultSubagentRegistry demoted in Task 2)

- [ ] **Step 1: Demote `ColonyInMemoryObservabilitySink` to `package`**

In `Sources/Colony/ColonyObservability.swift:58`, change:
```swift
// BEFORE
public actor ColonyInMemoryObservabilitySink: ColonyObservabilitySink {
// AFTER
package actor ColonyInMemoryObservabilitySink: ColonyObservabilitySink {
```
Also change all `public` members on this actor to `package`.

- [ ] **Step 2: Demote `ColonyInMemoryMemoryBackend` to `package`**

In `Sources/ColonyCore/ColonyMemory.swift:72`, change:
```swift
// BEFORE
public actor ColonyInMemoryMemoryBackend: ColonyMemoryBackend {
// AFTER
package actor ColonyInMemoryMemoryBackend: ColonyMemoryBackend {
```
Also change `public init(...)`, `public func recall(...)`, `public func remember(...)` to `package`.

- [ ] **Step 3: Demote `ColonyInMemoryFileSystemBackend` to `package`**

In `Sources/ColonyCore/ColonyFileSystem.swift:110`, change:
```swift
// BEFORE
public actor ColonyInMemoryFileSystemBackend: ColonyFileSystemBackend {
// AFTER
package actor ColonyInMemoryFileSystemBackend: ColonyFileSystemBackend {
```
Change all `public` members to `package`.

- [ ] **Step 4: Demote `ColonyInMemoryToolApprovalRuleStore` to `package`**

In `Sources/ColonyCore/ColonyToolApprovalRules.swift:77`, change:
```swift
// BEFORE
public actor ColonyInMemoryToolApprovalRuleStore: ColonyToolApprovalRuleStore {
// AFTER
package actor ColonyInMemoryToolApprovalRuleStore: ColonyToolApprovalRuleStore {
```
Change all `public` members to `package`.

- [ ] **Step 5: Demote `ColonyInMemoryToolAuditLogStore` to `package`**

In `Sources/ColonyCore/ColonyToolAudit.swift:116`, change:
```swift
// BEFORE
public actor ColonyInMemoryToolAuditLogStore: ColonyImmutableToolAuditLogStore {
// AFTER
package actor ColonyInMemoryToolAuditLogStore: ColonyImmutableToolAuditLogStore {
```
Change all `public` members to `package`.

- [ ] **Step 6: Demote `ColonyApproximateTokenizer` to `package`**

In `Sources/ColonyCore/ColonyTokenizer.swift:12`, change:
```swift
// BEFORE
public struct ColonyApproximateTokenizer: ColonyTokenizer, Sendable {
// AFTER
package struct ColonyApproximateTokenizer: ColonyTokenizer, Sendable {
```
Change all `public` members to `package`.

- [ ] **Step 7: Demote `InMemoryColonyProjectStore` to `package`**

In `Sources/ColonyControlPlane/ColonyProjectStore.swift:10`, change:
```swift
// BEFORE
public actor InMemoryColonyProjectStore: ColonyProjectStore {
// AFTER
package actor InMemoryColonyProjectStore: ColonyProjectStore {
```
Change all `public` members to `package`.

- [ ] **Step 8: Demote `ColonySessionStore` to `package`**

In `Sources/ColonyControlPlane/ColonySessionStore.swift:3`, change:
```swift
// BEFORE
public actor ColonySessionStore {
// AFTER
package actor ColonySessionStore {
```
Change all `public` members to `package`.

- [ ] **Step 9: Update test files that reference demoted types**

Search all test files for references to the 8 demoted types. Since tests are in the same package, `package` access should work. If any tests use `@testable import`, they already have access.

Run: `swift build --target ColonyTests 2>&1 | head -50`
Expected: No new errors related to access control.

- [ ] **Step 10: Build verify all 3 targets**

Run: `swift build 2>&1 | grep -c error`
Expected: 0 new errors (pre-existing Conduit errors OK).

- [ ] **Step 11: Commit**

```bash
git add -A Sources/Colony/ColonyObservability.swift Sources/ColonyCore/ColonyMemory.swift \
  Sources/ColonyCore/ColonyFileSystem.swift Sources/ColonyCore/ColonyToolApprovalRules.swift \
  Sources/ColonyCore/ColonyToolAudit.swift Sources/ColonyCore/ColonyTokenizer.swift \
  Sources/ColonyControlPlane/ColonyProjectStore.swift Sources/ColonyControlPlane/ColonySessionStore.swift
git commit -m "refactor: demote 8 in-memory test doubles to package access (M1)"
```

---

### Task 2: Demote `ColonyDefaultSubagentRegistry` and `ColonyDurableRunStateStore` to `package`

**Files:**
- Modify: `Sources/Colony/ColonyDefaultSubagentRegistry.swift:5,29,46,62,75`
- Modify: `Sources/Colony/ColonyDurableRunStateStore.swift:37,43,59,86,94,122,147,158`

**Issues Fixed:** C3, M11, M12

- [ ] **Step 1: Demote `ColonyDefaultSubagentRegistry` to `package`**

In `Sources/Colony/ColonyDefaultSubagentRegistry.swift:5`, change:
```swift
// BEFORE
public struct ColonyDefaultSubagentRegistry: ColonySubagentRegistry {
// AFTER
package struct ColonyDefaultSubagentRegistry: ColonySubagentRegistry {
```
Change both `public init(...)` (lines 29, 46) and `public func listSubagents()` (line 62) and `public func run(...)` (line 75) to `package`.

- [ ] **Step 2: Demote `ColonyDurableRunStateStore` to `package`**

In `Sources/Colony/ColonyDurableRunStateStore.swift:37`, change:
```swift
// BEFORE
public actor ColonyDurableRunStateStore {
// AFTER
package actor ColonyDurableRunStateStore {
```
Change all `public` members (`init`, `appendEvent`, `loadRunState`, `listRunStates`, `loadEvents`, `latestInterruptedRun`, `latestRunState`) to `package`.

Also demote `ColonyRunPhase` (line 5) and `ColonyRunStateSnapshot` (line 12) to `package` since they're only used with this store.

- [ ] **Step 3: Build verify**

Run: `swift build 2>&1 | grep -c error`

- [ ] **Step 4: Commit**

```bash
git add Sources/Colony/ColonyDefaultSubagentRegistry.swift Sources/Colony/ColonyDurableRunStateStore.swift
git commit -m "refactor: demote ColonyDefaultSubagentRegistry and ColonyDurableRunStateStore to package (C3, M11, M12)"
```

---

### Task 3: Fix visibility inconsistency and add missing defaults

**Files:**
- Modify: `Sources/Colony/ColonyHarnessSession.swift:118`
- Modify: `Sources/ColonyCore/ColonyInferenceSurface.swift:225-236`

**Issues Fixed:** L2, M8

- [ ] **Step 1: Fix `ColonyHarnessSession.stop()` visibility**

In `Sources/Colony/ColonyHarnessSession.swift:118`, change:
```swift
// BEFORE
public func stop() {
// AFTER
package func stop() {
```

- [ ] **Step 2: Add defaults to `ColonyInferenceHints.init`**

In `Sources/ColonyCore/ColonyInferenceSurface.swift:225-236`, change:
```swift
// BEFORE
public init(
    latencyTier: ColonyLatencyTier,
    privacyRequired: Bool,
    tokenBudget: Int?,
    networkState: ColonyNetworkState
) {
// AFTER
public init(
    latencyTier: ColonyLatencyTier = .interactive,
    privacyRequired: Bool = false,
    tokenBudget: Int? = nil,
    networkState: ColonyNetworkState = .online
) {
```

- [ ] **Step 3: Build verify and commit**

```bash
git add Sources/Colony/ColonyHarnessSession.swift Sources/ColonyCore/ColonyInferenceSurface.swift
git commit -m "fix: fix stop() visibility (L2), add ColonyInferenceHints defaults (M8)"
```

---

### Task 4: Nest phantom domain types under `ColonyID`

**Files:**
- Modify: `Sources/ColonyCore/ColonyID.swift:43-56`

**Issues Fixed:** L7/L9

- [ ] **Step 1: Nest domain types and update typealiases**

In `Sources/ColonyCore/ColonyID.swift`, replace lines 41-56:
```swift
// BEFORE
// MARK: - Phantom Domain Types

public enum ThreadDomain: Sendable {}
public enum InterruptDomain: Sendable {}
public enum HarnessSessionDomain: Sendable {}
public enum ProjectDomain: Sendable {}
public enum ProductSessionDomain: Sendable {}
public enum ProductSessionVersionDomain: Sendable {}
public enum ShareTokenDomain: Sendable {}

// MARK: - Backward-Compatible Type Aliases

public typealias ColonyThreadID = ColonyID<ThreadDomain>
public typealias ColonyInterruptID = ColonyID<InterruptDomain>
public typealias ColonyHarnessSessionID = ColonyID<HarnessSessionDomain>

// AFTER
// MARK: - Phantom Domain Types

extension ColonyID {
    public enum Thread: Sendable {}
    public enum Interrupt: Sendable {}
    public enum HarnessSession: Sendable {}
    public enum Project: Sendable {}
    public enum ProductSession: Sendable {}
    public enum ProductSessionVersion: Sendable {}
    public enum ShareToken: Sendable {}
}

// MARK: - Backward-Compatible Type Aliases

public typealias ColonyThreadID = ColonyID<ColonyID.Thread>
public typealias ColonyInterruptID = ColonyID<ColonyID.Interrupt>
public typealias ColonyHarnessSessionID = ColonyID<ColonyID.HarnessSession>

// Keep old names as deprecated typealiases for migration
@available(*, deprecated, renamed: "ColonyID.Thread")
public typealias ThreadDomain = ColonyID.Thread
@available(*, deprecated, renamed: "ColonyID.Interrupt")
public typealias InterruptDomain = ColonyID.Interrupt
@available(*, deprecated, renamed: "ColonyID.HarnessSession")
public typealias HarnessSessionDomain = ColonyID.HarnessSession
@available(*, deprecated, renamed: "ColonyID.Project")
public typealias ProjectDomain = ColonyID.Project
@available(*, deprecated, renamed: "ColonyID.ProductSession")
public typealias ProductSessionDomain = ColonyID.ProductSession
@available(*, deprecated, renamed: "ColonyID.ProductSessionVersion")
public typealias ProductSessionVersionDomain = ColonyID.ProductSessionVersion
@available(*, deprecated, renamed: "ColonyID.ShareToken")
public typealias ShareTokenDomain = ColonyID.ShareToken
```

- [ ] **Step 2: Update control plane domain typealiases**

In `Sources/ColonyControlPlane/ColonyControlPlaneDomain.swift:7-10`, update:
```swift
// BEFORE
public typealias ColonyProjectID = ColonyID<ProjectDomain>
public typealias ColonyProductSessionID = ColonyID<ProductSessionDomain>
public typealias ColonyProductSessionVersionID = ColonyID<ProductSessionVersionDomain>
public typealias ColonySessionShareToken = ColonyID<ShareTokenDomain>

// AFTER
public typealias ColonyProjectID = ColonyID<ColonyID.Project>
public typealias ColonyProductSessionID = ColonyID<ColonyID.ProductSession>
public typealias ColonyProductSessionVersionID = ColonyID<ColonyID.ProductSessionVersion>
public typealias ColonySessionShareToken = ColonyID<ColonyID.ShareToken>
```

- [ ] **Step 3: Update `ColonyHiveAdapters.swift` domain references**

In `Sources/Colony/ColonyHiveAdapters.swift:5,16`, update:
```swift
// BEFORE
extension ColonyID where Domain == ThreadDomain {
// AFTER
extension ColonyID where Domain == ColonyID.Thread {
```
And:
```swift
// BEFORE
extension ColonyID where Domain == InterruptDomain {
// AFTER
extension ColonyID where Domain == ColonyID.Interrupt {
```

- [ ] **Step 4: Build verify and commit**

```bash
swift build 2>&1 | grep -c error
git add Sources/ColonyCore/ColonyID.swift Sources/ColonyControlPlane/ColonyControlPlaneDomain.swift Sources/Colony/ColonyHiveAdapters.swift
git commit -m "refactor: nest phantom domain types under ColonyID extension (L7/L9)"
```

---

## Phase 2: Type Safety Completion (breaking — ColonyID adoption)

Covers: M2, M3, M4, M5, M6, M7, L3

### Task 5: Add new phantom domain types for incomplete ID adoption

**Files:**
- Modify: `Sources/ColonyCore/ColonyID.swift`

**Issues Fixed:** Foundation for M2-M4, M7, L3

- [ ] **Step 1: Add `Artifact`, `Checkpoint`, `ToolCall` domains and `ColonySubagentType` newtype**

In `Sources/ColonyCore/ColonyID.swift`, add to the `extension ColonyID` block:
```swift
extension ColonyID {
    // ... existing domains ...
    public enum Artifact: Sendable {}
    public enum Checkpoint: Sendable {}
}

// ... existing typealiases ...
public typealias ColonyArtifactID = ColonyID<ColonyID.Artifact>
public typealias ColonyCheckpointID = ColonyID<ColonyID.Checkpoint>
```

Also create a `ColonySubagentType` newtype. Add to the end of the file:
```swift
/// Type-safe subagent type identifier.
public struct ColonySubagentType: Hashable, Codable, Sendable,
                                   ExpressibleByStringLiteral,
                                   CustomStringConvertible {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(value) }
    public var description: String { rawValue }

    public static let generalPurpose: ColonySubagentType = "general-purpose"
    public static let compactor: ColonySubagentType = "compactor"
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/ColonyCore/ColonyID.swift
git commit -m "feat: add Artifact, Checkpoint phantom domains and ColonySubagentType newtype (M3, M7, L3)"
```

---

### Task 6: Adopt `ColonyToolName` in `ColonyToolCall` and `ColonyToolDefinition`

**Files:**
- Modify: `Sources/ColonyCore/ColonyInferenceSurface.swift:19,33`
- Modify: `Sources/ColonyCore/ColonyToolSafetyPolicy.swift:76`
- Modify: `Sources/Colony/ColonyHiveAdapters.swift` (adapter conversions)
- Modify: `Sources/Colony/SwarmToolBridge.swift` (tool name conversions)
- Modify: `Sources/Colony/ColonyDefaultSubagentRegistry.swift`
- Modify: Test files that construct `ColonyToolCall` or `ColonyToolDefinition`

**Issues Fixed:** M5, M6

- [ ] **Step 1: Change `ColonyToolDefinition.name` to `ColonyToolName`**

In `Sources/ColonyCore/ColonyInferenceSurface.swift:18-27`:
```swift
// BEFORE
public struct ColonyToolDefinition: Codable, Sendable, Equatable {
    public let name: String
    public let description: String
    public let parametersJSONSchema: String

    public init(name: String, description: String, parametersJSONSchema: String) {
        self.name = name
// AFTER
public struct ColonyToolDefinition: Codable, Sendable, Equatable {
    public let name: ColonyToolName
    public let description: String
    public let parametersJSONSchema: String

    public init(name: ColonyToolName, description: String, parametersJSONSchema: String) {
        self.name = name
```

- [ ] **Step 2: Change `ColonyToolCall.name` to `ColonyToolName`**

In `Sources/ColonyCore/ColonyInferenceSurface.swift:30-39`:
```swift
// BEFORE
public struct ColonyToolCall: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let argumentsJSON: String

    public init(id: String, name: String, argumentsJSON: String) {
// AFTER
public struct ColonyToolCall: Codable, Sendable, Equatable {
    public let id: String
    public let name: ColonyToolName
    public let argumentsJSON: String

    public init(id: String, name: ColonyToolName, argumentsJSON: String) {
```

- [ ] **Step 3: Change `ColonyToolSafetyAssessment.toolName` to `ColonyToolName`**

In `Sources/ColonyCore/ColonyToolSafetyPolicy.swift:76`:
```swift
// BEFORE
public var toolName: String
// AFTER
public var toolName: ColonyToolName
```
And update the `init` parameter at line 85:
```swift
// BEFORE
toolName: String,
// AFTER
toolName: ColonyToolName,
```

- [ ] **Step 4: Update `ColonyHiveAdapters.swift` conversions**

In `Sources/Colony/ColonyHiveAdapters.swift`, update the `ColonyToolDefinition` adapter (around line 74):
```swift
extension ColonyToolDefinition {
    package init(_ hive: HiveToolDefinition) {
        self.init(
            name: ColonyToolName(rawValue: hive.name),
            description: hive.description,
            parametersJSONSchema: hive.parametersJSONSchema
        )
    }

    package var hive: HiveToolDefinition {
        HiveToolDefinition(
            name: name.rawValue,
            description: description,
            parametersJSONSchema: parametersJSONSchema
        )
    }
}
```

Update the `ColonyToolCall` adapter (around line 92):
```swift
extension ColonyToolCall {
    package init(_ hive: HiveToolCall) {
        self.init(
            id: hive.id,
            name: ColonyToolName(rawValue: hive.name),
            argumentsJSON: hive.argumentsJSON
        )
    }

    package var hive: HiveToolCall {
        HiveToolCall(
            id: id,
            name: name.rawValue,
            argumentsJSON: argumentsJSON
        )
    }
}
```

- [ ] **Step 5: Update `ColonyToolSafetyPolicyEngine.assess`**

In `Sources/ColonyCore/ColonyToolSafetyPolicy.swift:139`, the `assess` method creates `ColonyToolName(rawValue: call.name)` — but now `call.name` is already `ColonyToolName`, so change:
```swift
// BEFORE
let toolName = ColonyToolName(rawValue: call.name)
// AFTER
let toolName = call.name
```

- [ ] **Step 6: Update `SwarmToolBridge` and `ColonyFoundationModelsClient`**

In `Sources/Colony/SwarmToolBridge.swift`, wherever `ColonyToolCall` or `ColonyToolDefinition` is constructed with a raw string name, wrap it:
```swift
// e.g., in ColonySwarmToolRegistry.makeToolDefinition (private, around line 289)
ColonyToolDefinition(
    name: ColonyToolName(rawValue: schema.name),
    description: schema.description,
    parametersJSONSchema: json
)
```

In `Sources/Colony/ColonyFoundationModelsClient.swift`, update `makeResponse` (around line 115):
```swift
// Tool call construction already uses String - wrap with ColonyToolName
ColonyToolCall(
    id: id ?? toolCallID(name: name, argumentsJSON: argumentsJSON, index: index),
    name: ColonyToolName(rawValue: name),
    argumentsJSON: argumentsJSON
)
```

- [ ] **Step 7: Update all test files**

Search for `ColonyToolCall(id:` and `ColonyToolDefinition(name:` in test files and wrap the `name:` parameter with `ColonyToolName(rawValue:)` or use a static member like `.readFile`.

- [ ] **Step 8: Build verify and commit**

```bash
swift build 2>&1 | grep "error:" | grep -v "Conduit"
git add -A
git commit -m "feat: adopt ColonyToolName in ColonyToolCall.name and ColonyToolDefinition.name (M5, M6)"
```

---

### Task 7: Replace raw `String` IDs with typed IDs in observability and artifacts

**Files:**
- Modify: `Sources/Colony/ColonyObservability.swift:29-50`
- Modify: `Sources/Colony/ColonyArtifactStore.swift:31-57,96-131`

**Issues Fixed:** M2, M3

- [ ] **Step 1: Update `ColonyObservabilityEvent` to use typed IDs**

In `Sources/Colony/ColonyObservability.swift:29-50`:
```swift
// BEFORE
public struct ColonyObservabilityEvent: Codable, Sendable, Equatable {
    public let name: ColonyEventName
    public let timestamp: Date
    public let runID: UUID?
    public let sessionID: String?
    public let threadID: String?
    public let attributes: [String: String]

    public init(
        name: ColonyEventName,
        timestamp: Date,
        runID: UUID? = nil,
        sessionID: String? = nil,
        threadID: String? = nil,
        attributes: [String: String] = [:]
    ) {

// AFTER
public struct ColonyObservabilityEvent: Codable, Sendable, Equatable {
    public let name: ColonyEventName
    public let timestamp: Date
    public let runID: UUID?
    public let sessionID: ColonyHarnessSessionID?
    public let threadID: ColonyThreadID?
    public let attributes: [String: String]

    public init(
        name: ColonyEventName,
        timestamp: Date,
        runID: UUID? = nil,
        sessionID: ColonyHarnessSessionID? = nil,
        threadID: ColonyThreadID? = nil,
        attributes: [String: String] = [:]
    ) {
```

- [ ] **Step 2: Update `ColonyObservabilityEmitter.emitHarnessEnvelope` callsite**

In `Sources/Colony/ColonyObservability.swift:99-117`, update the method to accept/convert:
```swift
// The sessionID from envelope is already ColonyHarnessSessionID, just pass it through
let event = ColonyObservabilityEvent(
    name: ColonyEventName("colony.harness.\(envelope.eventType.rawValue)"),
    timestamp: envelope.timestamp,
    runID: envelope.runID,
    sessionID: envelope.sessionID,
    threadID: threadID,
    attributes: attributes
)
```

- [ ] **Step 3: Update `ColonyArtifactRecord` to use typed IDs**

In `Sources/Colony/ColonyArtifactStore.swift:31-57`:
```swift
// BEFORE
public struct ColonyArtifactRecord: Codable, Sendable, Equatable {
    public let id: String
    public let threadID: String
    public let runID: UUID?
    // ...
    public init(
        id: String,
        threadID: String,
        runID: UUID?,

// AFTER
public struct ColonyArtifactRecord: Codable, Sendable, Equatable {
    public let id: ColonyArtifactID
    public let threadID: ColonyThreadID
    public let runID: UUID?
    // ...
    public init(
        id: ColonyArtifactID = ColonyArtifactID(UUID().uuidString),
        threadID: ColonyThreadID,
        runID: UUID?,
```
Note: `id` now has a default, and `redacted` and `metadata` should also get defaults:
```swift
    public init(
        id: ColonyArtifactID = ColonyArtifactID(UUID().uuidString),
        threadID: ColonyThreadID,
        runID: UUID?,
        kind: ColonyArtifactKind,
        createdAt: Date = Date(),
        redacted: Bool = true,
        metadata: [String: String] = [:]
    ) {
```

- [ ] **Step 4: Update `ColonyArtifactStore.put()` and `.list()` to use Colony types (also fixes C2)**

In `Sources/Colony/ColonyArtifactStore.swift:96-131`:
```swift
// BEFORE
public func put(
    threadID: HiveThreadID,
    runID: HiveRunID?,
    ...
) async throws -> ColonyArtifactRecord {
    let record = ColonyArtifactRecord(
        id: artifactID,
        threadID: threadID.rawValue,
        runID: runID?.rawValue,

// AFTER
public func put(
    threadID: ColonyThreadID,
    runID: UUID?,
    ...
) async throws -> ColonyArtifactRecord {
    let record = ColonyArtifactRecord(
        id: ColonyArtifactID(artifactID),
        threadID: threadID,
        runID: runID,
```

Update `list()`:
```swift
// BEFORE
public func list(
    threadID: HiveThreadID? = nil,
    runID: HiveRunID? = nil,
// AFTER
public func list(
    threadID: ColonyThreadID? = nil,
    runID: UUID? = nil,
```

Update the filter logic:
```swift
// BEFORE
if let threadID, record.threadID != threadID.rawValue { return false }
if let runID, record.runID != runID.rawValue { return false }
// AFTER
if let threadID, record.threadID != threadID { return false }
if let runID, record.runID != runID { return false }
```

- [ ] **Step 5: Build verify and commit**

```bash
swift build 2>&1 | grep "error:" | grep -v "Conduit"
git add -A
git commit -m "feat: adopt typed IDs in ColonyObservabilityEvent and ColonyArtifactRecord (C2, M2, M3, L5)"
```

---

### Task 8: Adopt typed IDs in remaining types and adopt `ColonySubagentType`

**Files:**
- Modify: `Sources/ColonyCore/ColonyRuntimeSurface.swift:62-76`
- Modify: `Sources/ColonyCore/ColonySubagents.swift:70-87`
- Modify: `Sources/Colony/ColonyDefaultSubagentRegistry.swift`

**Issues Fixed:** M4 (via Task 2 — already `package`), M7, L3

- [ ] **Step 1: Add `ColonyCheckpointID` to `ColonyRunInterruption`**

In `Sources/ColonyCore/ColonyRuntimeSurface.swift:62-76`:
```swift
// BEFORE
public struct ColonyRunInterruption: Sendable, Equatable {
    public let interruptID: ColonyInterruptID
    public let toolCalls: [ColonyToolCall]
    public let checkpointID: String

    public init(
        interruptID: ColonyInterruptID,
        toolCalls: [ColonyToolCall],
        checkpointID: String
    ) {

// AFTER
public struct ColonyRunInterruption: Sendable, Equatable {
    public let interruptID: ColonyInterruptID
    public let toolCalls: [ColonyToolCall]
    public let checkpointID: ColonyCheckpointID

    public init(
        interruptID: ColonyInterruptID,
        toolCalls: [ColonyToolCall],
        checkpointID: ColonyCheckpointID
    ) {
```

Also update `ColonyRunOutcome` cases that use `checkpointID: String?` to `checkpointID: ColonyCheckpointID?`:
```swift
public enum ColonyRunOutcome: Sendable, Equatable {
    case finished(transcript: ColonyTranscript, checkpointID: ColonyCheckpointID?)
    case interrupted(ColonyRunInterruption)
    case cancelled(transcript: ColonyTranscript, checkpointID: ColonyCheckpointID?)
    case outOfSteps(maxSteps: Int, transcript: ColonyTranscript, checkpointID: ColonyCheckpointID?)
}
```

- [ ] **Step 2: Update `ColonyRuntime.mapOutcome` to wrap checkpoint IDs**

In `Sources/Colony/ColonyRuntime.swift:89-121`, update `mapOutcome` to wrap checkpoint IDs:
```swift
// Where checkpointID is used:
checkpointID: checkpointID.map { ColonyCheckpointID($0.rawValue) }
```

- [ ] **Step 3: Adopt `ColonySubagentType` in `ColonySubagentRequest`**

In `Sources/ColonyCore/ColonySubagents.swift:70-87`:
```swift
// BEFORE
public struct ColonySubagentRequest: Sendable, Equatable {
    public var prompt: String
    public var subagentType: String
    // ...
    public init(
        prompt: String,
        subagentType: String,

// AFTER
public struct ColonySubagentRequest: Sendable, Equatable {
    public var prompt: String
    public var subagentType: ColonySubagentType
    // ...
    public init(
        prompt: String,
        subagentType: ColonySubagentType,
```

- [ ] **Step 4: Update `ColonyDefaultSubagentRegistry` to use `ColonySubagentType`**

In `Sources/Colony/ColonyDefaultSubagentRegistry.swift:76`:
```swift
// BEFORE
let type = request.subagentType.trimmingCharacters(in: .whitespacesAndNewlines)
guard type == "general-purpose" || type == "compactor" else {
// AFTER
let type = request.subagentType
guard type == .generalPurpose || type == .compactor else {
```

- [ ] **Step 5: Build verify and commit**

```bash
swift build 2>&1 | grep "error:" | grep -v "Conduit"
git add -A
git commit -m "feat: adopt ColonyCheckpointID, ColonySubagentType typed IDs (M7, L3)"
```

---

## Phase 3: Cross-Module Isolation

Covers: C6 (C2 was fixed in Task 7, C3 in Task 2)

### Task 9: Replace `HiveThreadID` in `ColonyDurableRunStateStore.appendEvent`

**Files:**
- Modify: `Sources/Colony/ColonyDurableRunStateStore.swift:60`
- Modify: `Sources/Colony/ColonyHarnessSession.swift:280`

**Issues Fixed:** C6

- [ ] **Step 1: Change `appendEvent` parameter to `ColonyThreadID`**

In `Sources/Colony/ColonyDurableRunStateStore.swift:59-61`:
```swift
// BEFORE
package func appendEvent(
    _ envelope: ColonyHarnessEventEnvelope,
    threadID: HiveThreadID
) async throws {
// AFTER
package func appendEvent(
    _ envelope: ColonyHarnessEventEnvelope,
    threadID: ColonyThreadID
) async throws {
```

Update internal usage of `threadID.rawValue` — since `ColonyThreadID.rawValue` is the same pattern, no change needed.

- [ ] **Step 2: Update callsite in `ColonyHarnessSession`**

In `Sources/Colony/ColonyHarnessSession.swift:280`:
```swift
// BEFORE
try? await runStateStore.appendEvent(envelope, threadID: runtime.threadID.hive)
// AFTER
try? await runStateStore.appendEvent(envelope, threadID: runtime.threadID)
```

- [ ] **Step 3: Build verify and commit**

```bash
swift build 2>&1 | grep "error:" | grep -v "Conduit"
git add Sources/Colony/ColonyDurableRunStateStore.swift Sources/Colony/ColonyHarnessSession.swift
git commit -m "fix: replace HiveThreadID with ColonyThreadID in DurableRunStateStore (C6)"
```

---

## Phase 4: Deprecate Backward-Compatible Typealiases

Covers: M9

### Task 10: Deprecate backward-compatible typealiases in `ColonyPublicAPI.swift`

**Files:**
- Modify: `Sources/Colony/ColonyPublicAPI.swift:196-202`

**Issues Fixed:** M9

- [ ] **Step 1: Add deprecation annotations**

In `Sources/Colony/ColonyPublicAPI.swift:196-202`:
```swift
// BEFORE
public typealias ColonyFoundationModelConfiguration = ColonyModel.FoundationModelConfiguration
public typealias ColonyOnDeviceModelPolicy = ColonyModel.OnDevicePolicy
public typealias ColonyProviderID = ColonyModel.ProviderID
public typealias ColonyProvider = ColonyModel.Provider
public typealias ColonyProviderRoutingPolicy = ColonyModel.RoutingPolicy

// AFTER
@available(*, deprecated, renamed: "ColonyModel.FoundationModelConfiguration")
public typealias ColonyFoundationModelConfiguration = ColonyModel.FoundationModelConfiguration
@available(*, deprecated, renamed: "ColonyModel.OnDevicePolicy")
public typealias ColonyOnDeviceModelPolicy = ColonyModel.OnDevicePolicy
@available(*, deprecated, renamed: "ColonyModel.ProviderID")
public typealias ColonyProviderID = ColonyModel.ProviderID
@available(*, deprecated, renamed: "ColonyModel.Provider")
public typealias ColonyProvider = ColonyModel.Provider
@available(*, deprecated, renamed: "ColonyModel.RoutingPolicy")
public typealias ColonyProviderRoutingPolicy = ColonyModel.RoutingPolicy
```

- [ ] **Step 2: Build verify and commit**

```bash
git add Sources/Colony/ColonyPublicAPI.swift
git commit -m "chore: deprecate backward-compatible typealiases (M9)"
```

---

## Phase 5: Remove `@_exported import ColonyCore`

Covers: C1

### Task 11: Remove `@_exported import ColonyCore`

**Files:**
- Modify: `Sources/Colony/Colony.swift:1`
- Modify: ALL test files and example apps that use `import Colony` and depend on ColonyCore types
- Modify: `Sources/ColonyResearchAssistantExample/ResearchAssistantApp.swift`
- Modify: `Sources/DeepResearchApp/ViewModels/ChatViewModel.swift`

**Issues Fixed:** C1

- [ ] **Step 1: Change `@_exported import ColonyCore` to `import ColonyCore`**

In `Sources/Colony/Colony.swift:1`:
```swift
// BEFORE
@_exported import ColonyCore

// AFTER
import ColonyCore
```

- [ ] **Step 2: Add `import ColonyCore` to all Colony source files that use ColonyCore types**

Every file in `Sources/Colony/` that references ColonyCore types already has `import ColonyCore` — verify this with:
```bash
grep -rL "import ColonyCore" Sources/Colony/*.swift | grep -v Colony.swift
```
Any file missing it needs `import ColonyCore` added.

- [ ] **Step 3: Add `import ColonyCore` to test files**

Search test files for ColonyCore type usage:
```bash
grep -rl "ColonyConfiguration\|ColonyCapabilities\|ColonyToolCall\|ColonyRunOptions\|ColonyToolName\|ColonyThreadID" Tests/ | sort -u
```
Add `import ColonyCore` to each file that uses these types alongside `import Colony`.

- [ ] **Step 4: Add `import ColonyCore` to example apps**

Check and update:
- `Sources/ColonyResearchAssistantExample/ResearchAssistantApp.swift`
- `Sources/DeepResearchApp/ViewModels/ChatViewModel.swift`

- [ ] **Step 5: Build verify all targets**

```bash
swift build 2>&1 | grep "error:" | grep -v "Conduit" | head -30
```

Fix any remaining "cannot find type" errors by adding `import ColonyCore` to the affected files.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: remove @_exported import ColonyCore — agents now see only Colony types (C1)"
```

---

## Phase 6: Sendable Fix and Swarm Interop Naming

Covers: C4, C5, C7, C8, L1

### Task 12: Rename Swarm bridge types for clarity

**Files:**
- Modify: `Sources/Colony/SwarmToolBridge.swift`
- Modify: `Sources/Colony/SwarmMemoryAdapter.swift`
- Modify: `Sources/Colony/SwarmSubagentAdapter.swift`

**Issues Fixed:** C4, C5, C7

- [ ] **Step 1: Add `Colony` prefix to Swarm bridge types**

These are intentional interop types, but naming should make clear they require Swarm:

In `Sources/Colony/SwarmToolBridge.swift:11`:
```swift
// Add deprecated typealias for migration
public typealias SwarmToolRegistration = ColonySwarmToolRegistration

public struct ColonySwarmToolRegistration: Sendable {
```

In `Sources/Colony/SwarmToolBridge.swift:61`:
```swift
public typealias SwarmToolBridge = ColonySwarmToolBridge

public struct ColonySwarmToolBridge: ColonyToolRegistry, Sendable {
```

In `Sources/Colony/SwarmMemoryAdapter.swift:32`:
```swift
public typealias SwarmMemoryAdapter = ColonySwarmMemoryAdapter

public struct ColonySwarmMemoryAdapter: ColonyMemoryBackend, Sendable {
```

In `Sources/Colony/SwarmSubagentAdapter.swift:34`:
```swift
public typealias SwarmSubagentAdapter = ColonySwarmSubagentAdapter

public struct ColonySwarmSubagentAdapter: ColonySubagentRegistry, Sendable {
```

- [ ] **Step 2: Update internal references**

Search for `SwarmToolBridge` usage in `Sources/Colony/` and update to `ColonySwarmToolBridge`. Key files:
- `Sources/Colony/ColonyAgentFactory.swift` (uses `SwarmToolBridge`)
- `Sources/Colony/ColonyPublicAPI.swift` (uses `SwarmToolBridge?`)

- [ ] **Step 3: Build verify and commit**

```bash
swift build 2>&1 | grep "error:" | grep -v "Conduit"
git add -A
git commit -m "refactor: rename Swarm bridge types with Colony prefix for clarity (C4, C5, C7)"
```

---

### Task 13: Fix `@unchecked Sendable` on `ColonyHardenedShellBackend`

**Files:**
- Modify: `Sources/ColonyCore/ColonyHardenedShellBackend.swift:5`

**Issues Fixed:** C8

- [ ] **Step 1: Evaluate the class for actor conversion**

Read `Sources/ColonyCore/ColonyHardenedShellBackend.swift` fully. If `sessionManager` is the only mutable state and it's already an actor or thread-safe, document why `@unchecked Sendable` is correct. If it's not provably safe, convert to an actor.

The class uses `ColonyShellSessionManager()` (private). If this is already an actor, the `@unchecked Sendable` is justified — add a `// SAFETY:` comment:

```swift
// SAFETY: All mutable state is isolated to ColonyShellSessionManager (an actor).
// Immutable stored properties (confinement, defaultTimeoutNanoseconds, etc.) are all Sendable.
public final class ColonyHardenedShellBackend: ColonyShellBackend, @unchecked Sendable {
```

If `ColonyShellSessionManager` is NOT an actor, convert the class:
```swift
public actor ColonyHardenedShellBackend: ColonyShellBackend {
```

- [ ] **Step 2: Build verify and commit**

```bash
swift build 2>&1 | grep "error:" | grep -v "Conduit"
git add Sources/ColonyCore/ColonyHardenedShellBackend.swift
git commit -m "fix: document @unchecked Sendable safety invariant on ColonyHardenedShellBackend (C8)"
```

---

### Task 14: Rename `ColonyCapabilities` to reduce naming ambiguity

**Files:**
- Modify: `Sources/ColonyCore/ColonyCapabilities.swift`
- Modify: ALL files that reference `ColonyCapabilities`

**Issues Fixed:** L1

- [ ] **Step 1: Evaluate scope of rename**

Search for `ColonyCapabilities` usage:
```bash
grep -r "ColonyCapabilities" Sources/ | wc -l
```

If the count is large (30+), this rename is high-effort. Consider adding a deprecated typealias instead:
```swift
// In ColonyCapabilities.swift
public struct ColonyRuntimeCapabilities: OptionSet, Sendable { ... }

@available(*, deprecated, renamed: "ColonyRuntimeCapabilities")
public typealias ColonyCapabilities = ColonyRuntimeCapabilities
```

- [ ] **Step 2: Execute rename with `replace_all`**

Use the Edit tool with `replace_all: true` on each file.

- [ ] **Step 3: Build verify and commit**

```bash
swift build 2>&1 | grep "error:" | grep -v "Conduit"
git add -A
git commit -m "refactor: rename ColonyCapabilities to ColonyRuntimeCapabilities (L1)"
```

---

## Phase 7: Final Verification

### Task 15: Full build and audit re-run

- [ ] **Step 1: Full build**

```bash
AISTACK_USE_LOCAL_DEPS=1 swift build 2>&1 | grep "error:" | grep -v "Conduit"
```

- [ ] **Step 2: Run tests**

```bash
swift test --filter ColonyTests 2>&1 | tail -20
```

- [ ] **Step 3: Re-run API audit**

Run the swift-api-sculptor skill again to verify the DX score improved from 69/100 to 90+.

- [ ] **Step 4: Update tasks/todo.md with results**

- [ ] **Step 5: Final commit**

```bash
git add tasks/todo.md
git commit -m "docs: update todo with audit fix results"
```
