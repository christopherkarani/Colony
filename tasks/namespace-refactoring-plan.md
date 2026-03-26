# Colony Namespace Refactoring Plan

## Context

Main had a namespace refactoring that nested top-level types under namespace enums (e.g., `ColonyVirtualPath` → `ColonyFileSystem.VirtualPath`). During the develop→main merge, these changes were lost because they conflicted with develop's codebase. This plan re-applies them incrementally.

## Benefits

- **Cleaner API surface**: Related types grouped under namespaces instead of polluting top-level
- **Discoverability**: `ColonyFileSystem.` autocomplete shows all file-system types
- **Safety**: Phantom-typed IDs prevent accidental ID mixing at compile time
- **Encapsulation**: Package-level access for test doubles hides internals from library consumers

## Approach

Each phase = one namespace family. After each phase: `swift build` + `swift test` must pass. Commit per phase.

---

## Phase 1: ColonyFileSystem Namespace

**Goal**: Nest file-system types under `public enum ColonyFileSystem {}`.

### Types to nest:
| Current Name | New Name | File |
|---|---|---|
| `ColonyVirtualPath` | `ColonyFileSystem.VirtualPath` | ColonyFileSystem.swift |
| `ColonyFileInfo` | `ColonyFileSystem.FileInfo` | ColonyFileSystem.swift |
| `ColonyGrepMatch` | `ColonyFileSystem.GrepMatch` | ColonyFileSystem.swift |
| `ColonyFileSystemError` | `ColonyFileSystem.Error` | ColonyFileSystem.swift |
| `ColonyFileSystemBackend` | `ColonyFileSystem.Backend` | ColonyFileSystem.swift |
| `ColonyCompositeFileSystemBackend` | `ColonyFileSystem.CompositeBackend` | ColonyCompositeFileSystemBackend.swift |

### Steps:
1. Add `public enum ColonyFileSystem {}` to ColonyFileSystem.swift
2. Move each type as a nested type under the namespace (use `extension ColonyFileSystem { ... }`)
3. Add deprecated typealiases for backward compatibility:
   ```swift
   @available(*, deprecated, renamed: "ColonyFileSystem.VirtualPath")
   public typealias ColonyVirtualPath = ColonyFileSystem.VirtualPath
   ```
4. Update all references across Sources/ (~15 files reference `ColonyVirtualPath`)
5. Update `ColonySummarizationPolicy.historyPathPrefix` type
6. `swift build` + `swift test`

### Affected files (references to update):
- Sources/ColonyCore/ColonyFileSystem.swift (definitions)
- Sources/ColonyCore/ColonyCompositeFileSystemBackend.swift
- Sources/ColonyCore/ColonyCodingBackends.swift
- Sources/ColonyCore/ColonyConfiguration.swift
- Sources/ColonyCore/ColonyGit.swift
- Sources/ColonyCore/ColonyHardenedShellBackend.swift
- Sources/ColonyCore/ColonyLSP.swift
- Sources/ColonyCore/ColonyScratchbookStore.swift
- Sources/ColonyCore/ColonyShell.swift
- Sources/ColonyCore/ColonySubagents.swift
- Sources/ColonyCore/ColonySummarizationPolicy.swift
- Sources/ColonyCore/ColonyToolAudit.swift

---

## Phase 2: ColonyShell Namespace

**Goal**: Nest shell types under `public enum ColonyShell {}`.

### Types to nest:
| Current Name | New Name |
|---|---|
| `ColonyShellTerminalMode` | `ColonyShell.TerminalMode` |
| `ColonyShellExecutionRequest` | `ColonyShell.ExecutionRequest` |
| `ColonyShellExecutionResult` | `ColonyShell.ExecutionResult` |
| `ColonyShellSessionID` | `ColonyShell.SessionID` |
| `ColonyShellSessionOpenRequest` | `ColonyShell.SessionOpenRequest` |
| `ColonyShellSessionReadResult` | `ColonyShell.SessionReadResult` |
| `ColonyShellSessionSnapshot` | `ColonyShell.SessionSnapshot` |
| `ColonyShellBackend` | `ColonyShell.Backend` |
| `ColonyShellExecutionError` | `ColonyShell.ExecutionError` |
| `ColonyShellConfinementPolicy` | `ColonyShell.ConfinementPolicy` |

### Steps:
1. Wrap types in `extension ColonyShell { ... }`
2. Add deprecated typealiases
3. Update references in ColonyHardenedShellBackend.swift, ColonyLSP.swift
4. `swift build` + `swift test`

---

## Phase 3: ColonyToolApproval Namespace

**Goal**: Nest approval types under `public enum ColonyToolApproval {}`.

### Types to nest:
| Current Name | New Name |
|---|---|
| `ColonyPerToolApprovalDecision` | `ColonyToolApproval.PerToolDecision` |
| `ColonyPerToolApproval` | `ColonyToolApproval.PerToolEntry` |
| `ColonyToolApprovalDecision` | `ColonyToolApproval.Decision` |
| `ColonyToolApprovalPolicy` | `ColonyToolApproval.Policy` |
| `ColonyToolApprovalRequirementReason` | `ColonyToolApproval.RequirementReason` |
| `ColonyToolRiskLevel` | `ColonyToolApproval.RiskLevel` |

### Steps:
1. Create namespace in ColonyToolApproval.swift
2. Move types from ColonyToolApproval.swift and ColonyToolSafetyPolicy.swift
3. Add deprecated typealiases
4. Update references in ColonyConfiguration.swift, ColonyToolSafetyPolicy.swift, ColonyToolAudit.swift
5. `swift build` + `swift test`

---

## Phase 4: ColonyToolAudit Namespace

**Goal**: Nest audit types under `public enum ColonyToolAudit {}`.

### Types to nest:
| Current Name | New Name |
|---|---|
| `ColonyToolAuditDecisionKind` | `ColonyToolAudit.DecisionKind` |
| `ColonyToolAuditEvent` | `ColonyToolAudit.Event` |
| `ColonyToolAuditRecordPayload` | `ColonyToolAudit.RecordPayload` |
| `ColonySignedToolAuditRecord` | `ColonyToolAudit.SignedRecord` |
| `ColonyToolAuditError` | `ColonyToolAudit.AuditError` |
| `ColonyToolAuditSigner` | `ColonyToolAudit.Signer` |
| `ColonyHMACSHA256ToolAuditSigner` | `ColonyToolAudit.HMACSHA256Signer` |
| `ColonyImmutableToolAuditLogStore` | `ColonyToolAudit.ImmutableLogStore` |
| `ColonyToolAuditVerifier` | `ColonyToolAudit.Verifier` |

### Steps:
1. Move types into `extension ColonyToolAudit { ... }`
2. Add deprecated typealiases
3. `swift build` + `swift test`

---

## Phase 5: ColonyGit Namespace

**Goal**: Nest git types under `public enum ColonyGit {}`.

### All `ColonyGit*` types → nested under `ColonyGit`.

### Steps:
1. Create namespace in ColonyGit.swift
2. Move all types (StatusRequest, StatusEntry, DiffRequest, etc.)
3. Add deprecated typealiases
4. `swift build` + `swift test`

---

## Phase 6: ColonyLSP Namespace

**Goal**: Nest LSP types under `public enum ColonyLSP {}`.

### All `ColonyLSP*` types → nested under `ColonyLSP`.

---

## Phase 7: ColonyHarness Namespace

**Goal**: Nest harness types under `public enum ColonyHarness {}`.

### All `ColonyHarness*` types → nested under `ColonyHarness`.

---

## Phase 8: Smaller Namespaces

Group remaining type families:
- **ColonyMemory**: ColonyMemoryItem, ColonyMemoryRecallRequest, etc.
- **ColonyScratchbook**: ColonyScratchItem, ColonyScratchbook, ColonyScratchbookPolicy, etc.
- **ColonySubagents**: ColonySubagentDescriptor, ColonySubagentContext, etc.
- **ColonyCodingBackends**: ColonyApplyPatchResult, ColonyWebSearchResult, ColonyCodeSearchMatch, etc.
- **ColonyObservability**: ColonyObservabilityEvent, ColonyObservabilitySink
- **ColonyConfig**: ColonyConfiguration, ColonyConfiguration.SafetyConfiguration, ColonyConfiguration.PromptConfiguration (already nested)

---

## Phase 9: Phantom-Typed ColonyID

**Goal**: Introduce generic `ColonyID<Domain>` for compile-time ID safety.

### Current state:
- `ColonyHarnessSessionID` is a struct with `rawValue: String`
- Other IDs are just `String` or `UUID`

### Target:
```swift
public struct ColonyID<Domain>: Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
}

public enum ColonyIDDomain {
    public enum Thread: Sendable {}
    public enum Interrupt: Sendable {}
    public enum HarnessSession: Sendable {}
}

public typealias ColonyThreadID = ColonyID<ColonyIDDomain.Thread>
public typealias ColonyInterruptID = ColonyID<ColonyIDDomain.Interrupt>
public typealias ColonyHarnessSessionID = ColonyID<ColonyIDDomain.HarnessSession>
```

### Steps:
1. Add `ColonyID.swift` with generic struct + phantom domains
2. Replace `ColonyHarnessSessionID` with typealias
3. Add type-safe IDs for Thread, Interrupt where `String` is currently used
4. `swift build` + `swift test`

---

## Phase 10: Access Control Cleanup

**Goal**: Demote internal/test types to `package` access.

### Types to demote (test doubles, internal machinery):
- `ColonySystemClock` → `package`
- `ColonyNoopLogger` → `package`
- In-memory test doubles (audit log stores, rule stores, etc.)
- `ColonyDefaultSubagentRegistry` → `package`
- `ColonyDurableRunStateStore` → `package`

---

## Verification

After each phase:
```bash
swift build
swift test
```

After all phases:
- Run full test suite
- Verify no public API regressions (deprecated typealiases maintain source compatibility)
- Update README examples if needed

## Estimated Scope

| Phase | Types | Files to change | Effort |
|---|---|---|---|
| 1: FileSystem | 6 | ~12 | Medium |
| 2: Shell | 10 | ~3 | Small |
| 3: ToolApproval | 6 | ~5 | Small |
| 4: ToolAudit | 9 | ~3 | Small |
| 5: Git | ~12 | ~2 | Small |
| 6: LSP | ~10 | ~2 | Small |
| 7: Harness | ~10 | ~3 | Small |
| 8: Small groups | ~20 | ~5 | Medium |
| 9: ColonyID | 3 | ~5 | Medium |
| 10: Access control | ~10 | ~8 | Small |
