# Colony API Surface Catalog

Generated: 2026-03-24 | Framework: Colony | Branch: main

---

## Summary

| Module | Public/Open Types | Public Members | Notes |
|--------|------------------:|---------------:|-------|
| **ColonyCore** | ~60 | ~250+ | Core protocols, types, enums |
| **Colony** | ~35 | ~120+ | Entry points, runtime, public model types |
| **Effective surface via `import Colony`** | **~95** | **~370+** | ColonyCore types re-exported via `@_exported import ColonyCore` |

> **Note**: Colony.swift has `@_exported import ColonyCore` at line 1, so ColonyCore types are available via `import Colony` alone. Users do NOT need to explicitly `import ColonyCore`.

---

## Module 1: ColonyCore (via `import Colony` or `import ColonyCore`)

### 1.1 Identity Types

#### ColonyID and Domain

**File:** `Sources/ColonyCore/ColonyID.swift`

```swift
public enum ColonyIDDomain: Hashable, Codable, Sendable {
    case thread, run, attempt, checkpoint, interrupt, channel, node, subagent, artifact
}

public struct ColonyID<Domain>: Sendable, Hashable, Codable, RawRepresentable,
                              ExpressibleByStringLiteral, LosslessStringConvertible {
    public let rawValue: String
    public init(_ rawValue: String)
    public init?(stringLiteral: String)
    public init?(rawValue: String)
}
```

**Thread-Safe Typealiases:**

| Typealias | Definition | Notes |
|-----------|------------|-------|
| `ColonyThreadID` | `ColonyID<ColonyIDDomain.Thread>` | Conversation thread identifier |
| `ColonyRunID` | `ColonyID<ColonyIDDomain.Run>` | Run identifier |
| `ColonyRunAttemptID` | `ColonyID<ColonyIDDomain.Attempt>` | Attempt identifier |
| `ColonyCheckpointID` | `ColonyID<ColonyIDDomain.Checkpoint>` | Checkpoint identifier |
| `ColonyInterruptID` | `ColonyID<ColonyIDDomain.Interrupt>` | Interrupt identifier |
| `ColonyChannelID` | `ColonyID<ColonyIDDomain.Channel>` | Channel identifier |
| `ColonyNodeID` | `ColonyID<ColonyIDDomain.Node>` | Node identifier |
| `ColonySubagentType` | `ColonyID<ColonyIDDomain.Subagent>` | Subagent type identifier |
| `ColonyArtifactID` | `ColonyID<ColonyIDDomain.Artifact>` | Artifact identifier |

**Thread Safety:** All ColonyID types are `Sendable`, `Hashable`, `Codable`.

---

### 1.2 Agent Mode & Lane

**File:** `Sources/ColonyCore/AgentMode.swift`

```swift
public enum AgentMode: String, Sendable, CaseIterable {
    case general
    case coding
    case research
    case memory
}

public typealias ColonyLane = AgentMode
```

**Thread Safety:** `Sendable`

---

### 1.3 Capabilities

**File:** `Sources/ColonyCore/ColonyCapabilities.swift`

```swift
public struct ColonyCapabilities: OptionSet, Sendable {
    public static let planning: ColonyCapabilities
    public static let filesystem: ColonyCapabilities
    public static let shell: ColonyCapabilities
    public static let scratchbook: ColonyCapabilities
    public static let subagents: ColonyCapabilities
    public static let memory: ColonyCapabilities
    public static let git: ColonyCapabilities
    public static let lsp: ColonyCapabilities
    public static let webSearch: ColonyCapabilities
    public static let codeSearch: ColonyCapabilities
    public static let mcp: ColonyCapabilities
    public static let plugins: ColonyCapabilities
    public static let tools: ColonyCapabilities

    // Default capability set for typical agent behavior
    public static let `default`: ColonyCapabilities
}
```

**Thread Safety:** `Sendable`

---

### 1.4 Configuration

**File:** `Sources/ColonyCore/ColonyConfiguration.swift`

```swift
public struct ColonyConfiguration: Sendable {
    // 3-tier initialization pattern
    public init(modelName: String)
    public init(modelName: String, capabilities: ColonyCapabilities)
    public init(
        modelName: String,
        capabilities: ColonyCapabilities,
        toolApprovalPolicy: ColonyToolApprovalPolicy,
        systemPrompt: String? = nil,
        additionalSystemPrompt: String? = nil,
        compactionPolicy: ColonyCompactionPolicy = .default,
        summarizationPolicy: ColonySummarizationPolicy = .default,
        scratchbookPolicy: ColonyScratchbookPolicy = .default,
        maxRoundtrips: Int = 100,
        streamingMode: ColonyRun.StreamingMode = .events
    )

    // Properties
    public var modelConfiguration: ModelConfiguration
    public var safetyConfiguration: SafetyConfiguration
    public var contextConfiguration: ContextConfiguration
    public var promptConfiguration: PromptConfiguration
}

// Nested configuration types
extension ColonyConfiguration {
    public struct ModelConfiguration: Sendable {
        public var name: String
        public var capabilities: ColonyCapabilities
        public var structuredOutput: ColonyStructuredOutput?
    }

    public struct SafetyConfiguration: Sendable {
        public var toolApprovalPolicy: ColonyToolApprovalPolicy
        public var toolRiskLevelOverrides: [String: ColonyToolRiskLevel]
        public var mandatoryApprovalRiskLevels: Set<ColonyToolRiskLevel>
        public var defaultRiskLevel: ColonyToolRiskLevel
    }

    public struct ContextConfiguration: Sendable {
        public var compactionPolicy: ColonyCompactionPolicy
        public var summarizationPolicy: ColonySummarizationPolicy
        public var scratchbookPolicy: ColonyScratchbookPolicy
        public var maxRoundtrips: Int
        public var maxTokens: Int?
    }

    public struct PromptConfiguration: Sendable {
        public var systemPrompt: String?
        public var additionalSystemPrompt: String?
        public var toolPromptStrategy: ColonyToolPromptStrategy
    }
}
```

**Thread Safety:** `Sendable`

---

### 1.5 Tool Safety & Policy

**File:** `Sources/ColonyCore/ColonyToolSafetyPolicy.swift`

```swift
// Risk levels for tools (ordered by severity)
public enum ColonyToolRiskLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case readOnly
    case stateMutation
    case mutation
    case execution
    case network
}

// Safety assessment result
public struct ColonyToolSafetyAssessment: Sendable, Equatable {
    public var toolCallID: String
    public var toolName: String
    public var riskLevel: ColonyToolRiskLevel
    public var requiresApproval: Bool
    public var reason: ColonyToolApprovalRequirementReason?
}

// Policy engine for tool safety
public struct ColonyToolSafetyPolicyEngine: Sendable {
    public var approvalPolicy: ColonyToolApprovalPolicy
    public var riskLevelOverrides: [String: ColonyToolRiskLevel]
    public var mandatoryApprovalRiskLevels: Set<ColonyToolRiskLevel>
    public var defaultRiskLevel: ColonyToolRiskLevel

    public func riskLevel(for toolName: String) -> ColonyToolRiskLevel
    public func assess(toolCalls: [HiveToolCall]) -> [ColonyToolSafetyAssessment]
}
```

**File:** `Sources/ColonyCore/ColonyToolApproval.swift`

```swift
// Per-tool approval decision
public enum ColonyPerToolApprovalDecision: String, Codable, Sendable, Equatable {
    case approved
    case rejected
    case cancelled
}

public struct ColonyPerToolApproval: Codable, Sendable, Equatable {
    public var toolName: String
    public var decision: ColonyPerToolApprovalDecision
}

// Overall approval decision
public enum ColonyToolApprovalDecision: Codable, Sendable, Equatable {
    case approved
    case rejected(reason: String?)
    case cancelled
    case perTool([ColonyPerToolApproval])
}

// Policy for when approval is required
public enum ColonyToolApprovalPolicy: Sendable {
    case never                           // Never require approval
    case always                          // Always require approval
    case allowList(Set<String>)          // Only require for listed tools
    case perTool([String: ColonyToolApprovalPolicy])  // Per-tool policies
}
```

**Thread Safety:** All tool safety types are `Sendable`.

---

### 1.6 Tool Approval Rules

**File:** `Sources/ColonyCore/ColonyToolApprovalRules.swift`

```swift
public enum ColonyToolApprovalRuleDecision: String, Codable, Sendable, Equatable {
    case approve
    case reject
    case deferToPolicy
}

public enum ColonyToolApprovalPattern: Codable, Sendable, Equatable {
    case exactToolName(String)
    case toolNamePrefix(String)
    case toolNameRegex(NSRegularExpression)
    case contentContains(String)
    case contentRegex(NSRegularExpression)
}

public struct ColonyToolApprovalRule: Codable, Sendable, Equatable {
    public var pattern: ColonyToolApprovalPattern
    public var decision: ColonyToolApprovalRuleDecision
    public var description: String?
}

public struct ColonyMatchedToolApprovalRule: Sendable, Equatable {
    public var rule: ColonyToolApprovalRule
    public var isMatch: Bool
}

public protocol ColonyToolApprovalRuleStore: Sendable {
    func rules(for toolName: String, content: String?) async throws -> [ColonyToolApprovalRule]
    func addRule(_ rule: ColonyToolApprovalRule) async throws
    func removeRule(id: String) async throws
}
```

**Thread Safety:** Protocols and types are `Sendable`.

---

### 1.7 Tool Audit System

**File:** `Sources/ColonyCore/ColonyToolAudit.swift`

```swift
public enum ColonyToolAuditDecisionKind: String, Codable, Sendable, Equatable {
    case approved
    case rejected
    case cancelled
}

public struct ColonyToolAuditEvent: Codable, Sendable, Equatable {
    public let timestamp: Date
    public let toolName: String
    public let toolCallID: String
    public let argumentsJSON: String?
    public let decision: ColonyToolAuditDecisionKind
    public let reason: String?
}

public struct ColonyToolAuditRecordPayload: Codable, Sendable, Equatable {
    public let event: ColonyToolAuditEvent
    public let sessionID: String?
    public let threadID: ColonyThreadID?
    public let runID: ColonyRunID?
}

public struct ColonySignedToolAuditRecord: Codable, Sendable, Equatable {
    public let record: ColonyToolAuditRecordPayload
    public let signature: Data
}

public enum ToolAuditError: Error, Sendable, Equatable {
    case signingFailed
    case verificationFailed
    case storeError(String)
}

public typealias ColonyToolAuditError = ToolAuditError

public protocol ColonyToolAuditSigner: Sendable {
    func sign(_ record: ColonyToolAuditRecordPayload) async throws -> Data
}

public struct ColonyHMACSHA256ToolAuditSigner: ColonyToolAuditSigner {
    public init(key: Data)
    public func sign(_ record: ColonyToolAuditRecordPayload) async throws -> Data
}

public protocol ColonyImmutableToolAuditLogStore: Sendable {
    func append(_ record: ColonySignedToolAuditRecord) async throws
    func records(since: Date?) async throws -> [ColonySignedToolAuditRecord]
    func verify() async throws -> Bool
}
```

**Thread Safety:** All audit types are `Sendable`.

---

### 1.8 FileSystem Namespace

**File:** `Sources/ColonyCore/ColonyFileSystem.swift`

```swift
public enum ColonyFileSystem {}

extension ColonyFileSystem {
    // Virtual path with normalization and security checks
    public struct VirtualPath: Hashable, Sendable, Codable {
        public let rawValue: String
        public init(_ rawValue: String) throws
        public static var root: VirtualPath { get }
        public static var scratchbookRoot: VirtualPath { get }
        public static var conversationHistoryRoot: VirtualPath { get }
        public static var toolAuditRoot: VirtualPath { get }
    }

    // File information
    public struct FileInfo: Sendable, Codable, Equatable {
        public let path: VirtualPath
        public let isDirectory: Bool
        public let sizeBytes: Int?
    }

    // Grep match result
    public struct GrepMatch: Sendable, Codable, Equatable {
        public let path: VirtualPath
        public let line: Int
        public let text: String
    }

    // FileSystem errors
    public enum Error: Swift.Error, Sendable, Equatable {
        case invalidPath(String)
        case notFound(VirtualPath)
        case isDirectory(VirtualPath)
        case alreadyExists(VirtualPath)
        case ioError(String)
    }

    // Main service protocol
    public protocol Service: Sendable {
        func list(at path: VirtualPath) async throws -> [FileInfo]
        func read(at path: VirtualPath) async throws -> String
        func write(at path: VirtualPath, content: String) async throws
        func edit(at path: VirtualPath, oldString: String, newString: String, replaceAll: Bool) async throws -> Int
        func glob(pattern: String) async throws -> [VirtualPath]
        func grep(pattern: String, glob: String?) async throws -> [GrepMatch]
    }
}

// Typealiases (deprecated)
@available(*, deprecated, renamed: "ColonyFileSystem.VirtualPath")
public typealias ColonyVirtualPath = ColonyFileSystem.VirtualPath

@available(*, deprecated, renamed: "ColonyFileSystem.FileInfo")
public typealias ColonyFileInfo = ColonyFileSystem.FileInfo

@available(*, deprecated, renamed: "ColonyFileSystem.GrepMatch")
public typealias ColonyGrepMatch = ColonyFileSystem.GrepMatch

@available(*, deprecated, renamed: "ColonyFileSystem.Error")
public typealias ColonyFileSystemError = ColonyFileSystem.Error

@available(*, deprecated, renamed: "ColonyFileSystem.Service")
public typealias ColonyFileSystemService = ColonyFileSystem.Service

@available(*, deprecated, renamed: "ColonyFileSystem.Service")
public typealias ColonyFileSystemBackend = ColonyFileSystem.Service
```

**Concrete Implementations:**

```swift
// In-memory implementation for testing
public actor ColonyInMemoryFileSystemBackend: ColonyFileSystem.Service {
    public init(files: [ColonyFileSystem.VirtualPath: String] = [:])
    public func list(at path: ColonyFileSystem.VirtualPath) async throws -> [ColonyFileSystem.FileInfo]
    public func read(at path: ColonyFileSystem.VirtualPath) async throws -> String
    public func write(at path: ColonyFileSystem.VirtualPath, content: String) async throws
    public func edit(at path: ColonyFileSystem.VirtualPath, oldString: String, newString: String, replaceAll: Bool) async throws -> Int
    public func glob(pattern: String) async throws -> [ColonyFileSystem.VirtualPath]
    public func grep(pattern: String, glob: String?) async throws -> [ColonyFileSystem.GrepMatch]
}

// Disk-based implementation
public actor ColonyDiskFileSystemBackend: ColonyFileSystem.Service {
    public init(root: URL, fileManager: FileManager = .default)
    // ... same protocol requirements
}
```

**Thread Safety:** All FileSystem types are `Sendable`.

---

### 1.9 Shell Backend

**File:** `Sources/ColonyCore/ColonyShell.swift`

```swift
public enum ColonyShellTerminalMode: String, Sendable, Codable {
    case pipes
    case pty
}

public struct ColonyShellExecutionRequest: Sendable, Equatable {
    public var command: String
    public var workingDirectory: ColonyVirtualPath?
    public var environment: [String: String]?
    public var timeoutNanoseconds: UInt64?
    public var terminalMode: ColonyShellTerminalMode?
}

public struct ColonyShellExecutionResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let wasTruncation: Bool
}

public typealias ColonyShellExecutionResponse = ColonyShellExecutionResult

public protocol ColonyShellService: Sendable {
    func execute(_ request: ColonyShellExecutionRequest) async throws -> ColonyShellExecutionResult
}

public struct ColonyShellSessionID: Hashable, Codable, Sendable, Equatable {
    public let rawValue: String
}

public struct ColonyShellSessionOpenRequest: Sendable, Equatable {
    public var command: String
    public var workingDirectory: ColonyVirtualPath?
    public var idleTimeoutNanoseconds: UInt64?
}

public struct ColonyShellSessionReadResult: Sendable, Equatable {
    public let stdout: String
    public let stderr: String
    public let eof: Bool
    public let wasTruncated: Bool
}

public struct ColonyShellSessionSnapshot: Sendable, Equatable {
    public let id: ColonyShellSessionID
    public let command: String
    public let workingDirectory: ColonyVirtualPath?
    public let startedAt: Date
    public var isRunning: Bool
}

public protocol ColonyShellBackend: ColonyShellService {
    func openSession(_ request: ColonyShellSessionOpenRequest) async throws -> ColonyShellSessionID
    func writeToSession(_ sessionID: ColonyShellSessionID, data: Data) async throws
    func readFromSession(_ sessionID: ColonyShellSessionID, maxBytes: Int, timeoutNanoseconds: UInt64?) async throws -> ColonyShellSessionReadResult
    func closeSession(_ sessionID: ColonyShellSessionID) async
}

public enum ColonyShellExecutionError: Error, Sendable, Equatable {
    case launchFailed(String)
    case timeout
    case invalidWorkingDirectory(ColonyVirtualPath)
    case sessionNotFound(ColonyShellSessionID)
    case ioError(String)
}

public struct ColonyShellConfinementPolicy: Sendable, Equatable {
    public var allowedWorkingDirectories: Set<ColonyVirtualPath>?
    public var deniedWorkingDirectories: Set<ColonyVirtualPath>?
    public var resolveWorkingDirectory(_ path: ColonyVirtualPath?) throws -> URL
}
```

**Hardened Shell Backend (Production):**

```swift
public final class ColonyHardenedShellBackend: ColonyShellBackend, Sendable {
    public let confinement: ColonyShellConfinementPolicy
    public let defaultTimeoutNanoseconds: UInt64?
    public let maxOutputBytes: Int
    public let environmentWhitelist: Set<String>?
    public let defaultTerminalMode: ColonyShellTerminalMode

    public init(
        confinement: ColonyShellConfinementPolicy,
        defaultTimeoutNanoseconds: UInt64? = nil,
        maxOutputBytes: Int = 64 * 1024,
        environmentWhitelist: Set<String>? = nil,
        defaultTerminalMode: ColonyShellTerminalMode = .pipes
    )
}
```

**Thread Safety:** All Shell types are `Sendable`.

---

### 1.10 Memory Backend

**File:** `Sources/ColonyCore/ColonyMemory.swift`

```swift
public struct ColonyMemoryItem: Sendable, Codable, Equatable {
    public let id: String
    public let content: String
    public let timestamp: Date
    public let metadata: [String: String]
}

public struct ColonyMemorySearchRequest: Sendable, Codable, Equatable {
    public var query: String
    public var limit: Int?
    public var since: Date?
}

public struct ColonyMemorySearchResponse: Sendable, Codable, Equatable {
    public let items: [ColonyMemoryItem]
    public let totalCount: Int
}

public struct ColonyMemoryStoreRequest: Sendable, Codable, Equatable {
    public var content: String
    public var metadata: [String: String]?
}

public struct ColonyMemoryStoreResponse: Sendable, Codable, Equatable {
    public let item: ColonyMemoryItem
}

// Typealiases
public typealias ColonyMemoryRecallRequest = ColonyMemorySearchRequest
public typealias ColonyMemoryRecallResult = ColonyMemorySearchResponse
public typealias ColonyMemoryRememberRequest = ColonyMemoryStoreRequest
public typealias ColonyMemoryRememberResult = ColonyMemoryStoreResponse

public protocol ColonyMemoryService: Sendable {
    func recall(_ request: ColonyMemorySearchRequest) async throws -> ColonyMemorySearchResponse
    func remember(_ request: ColonyMemoryStoreRequest) async throws -> ColonyMemoryStoreResponse
}

public typealias ColonyMemoryBackend = ColonyMemoryService
```

**Thread Safety:** All Memory types are `Sendable`.

---

### 1.11 Subagent System

**File:** `Sources/ColonyCore/ColonySubagents.swift`

```swift
public struct ColonySubagentDescriptor: Sendable, Codable, Equatable {
    public let name: String
    public let description: String
    public let capability: ColonyCapabilities?
}

public struct ColonySubagentContext: Sendable, Codable, Equatable {
    public var objective: String?
    public var constraints: [String]
    public var acceptanceCriteria: [String]
    public var notes: [String]
}

public struct ColonySubagentFileReference: Sendable, Codable, Equatable {
    public let path: ColonyFileSystem.VirtualPath
    public var offset: Int?
    public var limit: Int?
}

public struct ColonySubagentRequest: Sendable, Equatable {
    public var subagentType: ColonySubagentType
    public var prompt: String
    public var context: ColonySubagentContext?
    public var fileReferences: [ColonySubagentFileReference]
}

public struct ColonySubagentResult: Sendable, Equatable {
    public let content: String
    public let metrics: [String: String]?
}

// Typealiases
public typealias ColonySubagentTaskRequest = ColonySubagentRequest
public typealias ColonySubagentTaskResponse = ColonySubagentResult

public protocol ColonySubagentService: Sendable {
    func listSubagents() -> [ColonySubagentDescriptor]
    func run(_ request: ColonySubagentRequest) async throws -> ColonySubagentResult
}

public protocol ColonySubagentRegistry: ColonySubagentService {
    // Inherits listSubagents() and run(_:)
}
```

**Thread Safety:** All Subagent types are `Sendable`.

---

### 1.12 Git Backend

**File:** `Sources/ColonyCore/ColonyGit.swift`

```swift
public struct ColonyGitStatusRequest: Sendable, Equatable, Codable {}
public struct ColonyGitStatusEntry: Sendable, Equatable, Codable {
    public let path: String
    public let status: String
    public let staged: Bool
}

public struct ColonyGitDiffRequest: Sendable, Equatable, Codable {
    public var path: String?
    public var staged: Bool
}

public struct ColonyGitCommitRequest: Sendable, Equatable, Codable {
    public var message: String
    public var authorName: String?
    public var authorEmail: String?
}

public struct ColonyGitBranchRequest: Sendable, Equatable, Codable {
    public var name: String
    public var startPoint: String?
    public var create: Bool
    public var delete: Bool
}

public struct ColonyGitPushRequest: Sendable, Equatable, Codable {
    public var remote: String?
    public var branch: String?
    public var force: Bool
}

public struct ColonyGitPreparePullRequestRequest: Sendable, Equatable, Codable {
    public var baseBranch: String
    public var headBranch: String
    public var title: String?
    public var body: String?
}

// Response types
public struct ColonyGitStatusResponse: Sendable, Equatable, Codable {
    public let entries: [ColonyGitStatusEntry]
    public let clean: Bool
}

public struct ColonyGitDiffResponse: Sendable, Equatable, Codable {
    public let diff: String
    public let path: String?
}

public struct ColonyGitCommitResponse: Sendable, Equatable, Codable {
    public let sha: String
    public let message: String
}

public struct ColonyGitBranchResponse: Sendable, Equatable, Codable {
    public let name: String
    public let current: Bool
}

public struct ColonyGitPushResponse: Sendable, Equatable, Codable {
    public let remote: String
    public let branch: String
    public let success: Bool
}

public struct ColonyGitPreparePullRequestResponse: Sendable, Equatable, Codable {
    public let url: String
    public let number: Int?
}

// Protocol
public protocol ColonyGitService: Sendable {
    func status(_ request: ColonyGitStatusRequest) async throws -> ColonyGitStatusResponse
    func diff(_ request: ColonyGitDiffRequest) async throws -> ColonyGitDiffResponse
    func commit(_ request: ColonyGitCommitRequest) async throws -> ColonyGitCommitResponse
    func branch(_ request: ColonyGitBranchRequest) async throws -> ColonyGitBranchResponse
    func push(_ request: ColonyGitPushRequest) async throws -> ColonyGitPushResponse
    func preparePullRequest(_ request: ColonyGitPreparePullRequestRequest) async throws -> ColonyGitPreparePullRequestResponse
}

// Typealiases
public typealias ColonyGitBackend = ColonyGitService
```

**Thread Safety:** All Git types are `Sendable`.

---

### 1.13 LSP Backend

**File:** `Sources/ColonyCore/ColonyLSP.swift`

```swift
public struct ColonyLSPPosition: Sendable, Equatable, Codable {
    public let line: Int
    public let character: Int
}

public struct ColonyLSPRange: Sendable, Equatable, Codable {
    public let start: ColonyLSPPosition
    public let end: ColonyLSPPosition
}

public struct ColonyLSPSymbolsRequest: Sendable, Equatable, Codable {
    public var path: String?
}

public struct ColonyLSPSymbol: Sendable, Equatable, Codable {
    public let name: String
    public let kind: String
    public let location: ColonyLSPLocation
    public let containerName: String?
}

public struct ColonyLSPLocation: Sendable, Equatable, Codable {
    public let uri: String
    public let range: ColonyLSPRange
}

public struct ColonyLSPDiagnosticsRequest: Sendable, Equatable, Codable {
    public var path: String?
}

public struct ColonyLSPDiagnostic: Sendable, Equatable, Codable {
    public let message: String
    public let severity: ColonyLSPDiagnosticSeverity
    public let range: ColonyLSPRange
    public let source: String?
}

public enum ColonyLSPDiagnosticSeverity: String, Codable, Sendable {
    case error, warning, information, hint
}

public struct ColonyLSPReferencesRequest: Sendable, Equatable, Codable {
    public var path: String
    public var position: ColonyLSPPosition
    public var includeDeclaration: Bool
}

public struct ColonyLSPReference: Sendable, Equatable, Codable {
    public let location: ColonyLSPLocation
    public let isDeclaration: Bool
}

public struct ColonyLSPTextEdit: Sendable, Equatable, Codable {
    public let range: ColonyLSPRange
    public let newText: String
}

public struct ColonyLSPApplyEditRequest: Sendable, Equatable, Codable {
    public var path: String
    public var edits: [ColonyLSPTextEdit]
}

public struct ColonyLSPApplyEditResult: Sendable, Equatable, Codable {
    public let applied: Bool
    public let failureReason: String?
}

public struct ColonyLSPSymbolsResponse: Sendable, Equatable, Codable {
    public let symbols: [ColonyLSPSymbol]
}

public struct ColonyLSPDiagnosticsResponse: Sendable, Equatable, Codable {
    public let diagnostics: [ColonyLSPDiagnostic]
}

public struct ColonyLSPReferencesResponse: Sendable, Equatable, Codable {
    public let references: [ColonyLSPReference]
}

public protocol ColonyLSPService: Sendable {
    func symbols(_ request: ColonyLSPSymbolsRequest) async throws -> ColonyLSPSymbolsResponse
    func diagnostics(_ request: ColonyLSPDiagnosticsRequest) async throws -> ColonyLSPDiagnosticsResponse
    func references(_ request: ColonyLSPReferencesRequest) async throws -> ColonyLSPReferencesResponse
    func applyEdit(_ request: ColonyLSPApplyEditRequest) async throws -> ColonyLSPApplyEditResult
}

public typealias ColonyLSPBackend = ColonyLSPService
```

**Thread Safety:** All LSP types are `Sendable`.

---

### 1.14 Coding Backends (WebSearch, CodeSearch, MCP, Patch)

**File:** `Sources/ColonyCore/ColonyCodingBackends.swift`

```swift
// Apply Patch
public struct ColonyApplyPatchResult: Sendable, Codable, Equatable {
    public let applied: Bool
    public let patch: String
}

public protocol ColonyApplyPatchBackend: Sendable {
    func applyPatch(_ patch: String, to content: String) async throws -> ColonyApplyPatchResult
}

// Web Search
public struct ColonyWebSearchResultItem: Sendable, Codable, Equatable {
    public let title: String
    public let url: String
    public let snippet: String
    public let score: Double?
}

public struct ColonyWebSearchResult: Sendable, Codable, Equatable {
    public let query: String
    public let items: [ColonyWebSearchResultItem]
    public let totalCount: Int?
}

public protocol ColonyWebSearchBackend: Sendable {
    func search(_ query: String, limit: Int?) async throws -> ColonyWebSearchResult
}

// Code Search
public struct ColonyCodeSearchMatch: Sendable, Codable, Equatable {
    public let filePath: String
    public let lineNumber: Int
    public let line: String
    public let context: String?
}

public struct ColonyCodeSearchResult: Sendable, Codable, Equatable {
    public let query: String
    public let matches: [ColonyCodeSearchMatch]
    public let totalCount: Int?
}

public protocol ColonyCodeSearchBackend: Sendable {
    func search(_ query: String, options: [String: String]?) async throws -> ColonyCodeSearchResult
}

// MCP (Model Context Protocol)
public struct ColonyMCPResource: Sendable, Codable, Equatable {
    public let uri: String
    public let name: String
    public let mimeType: String?
    public let content: String?
}

public protocol ColonyMCPBackend: Sendable {
    func listResources() async throws -> [ColonyMCPResource]
    func readResource(_ uri: String) async throws -> ColonyMCPResource
    func listTools() async throws -> [ColonyTool.Definition]
    func invokeTool(_ name: String, arguments: [String: String]) async throws -> String
}

// Plugin Tool Registry
public protocol ColonyPluginToolRegistry: Sendable {
    func listTools() async -> [ColonyTool.Definition]
    func invoke(_ toolName: String, arguments: [String: String]) async throws -> ColonyTool.Result
}
```

**Thread Safety:** All coding backend types are `Sendable`.

---

### 1.15 Composite FileSystem Backend

**File:** `Sources/ColonyCore/ColonyCompositeFileSystemBackend.swift`

```swift
public struct ColonyCompositeFileSystemService: ColonyFileSystem.Service {
    public init(write: ColonyFileSystem.Service, read: ColonyFileSystem.Service? = nil)

    // ColonyFileSystem.Service conformance
    public func list(at path: ColonyFileSystem.VirtualPath) async throws -> [ColonyFileSystem.FileInfo]
    public func read(at path: ColonyFileSystem.VirtualPath) async throws -> String
    public func write(at path: ColonyFileSystem.VirtualPath, content: String) async throws
    public func edit(at path: ColonyFileSystem.VirtualPath, oldString: String, newString: String, replaceAll: Bool) async throws -> Int
    public func glob(pattern: String) async throws -> [ColonyFileSystem.VirtualPath]
    public func grep(pattern: String, glob: String?) async throws -> [ColonyFileSystem.GrepMatch]
}

@available(*, deprecated, renamed: "ColonyCompositeFileSystemService")
public typealias ColonyCompositeFileSystemBackend = ColonyCompositeFileSystemService

@available(*, deprecated, renamed: "ColonyCompositeFileSystemService")
public typealias ColonyFileSystemCompositeService = ColonyCompositeFileSystemService
```

**Thread Safety:** `Sendable`

---

### 1.16 Policies

**File:** `Sources/ColonyCore/Policies/ColonyResourcePolicy.swift`

```swift
public struct ColonyResourcePolicy: Sendable {
    public var maxTokens: Int
    public var maxRoundtrips: Int
    public var contextWindowPolicy: ContextWindowPolicy
    public var compressionPolicy: ContextCompressionPolicy
    public var workingMemoryPolicy: WorkingMemoryPolicy
}

public struct ContextWindowPolicy: Sendable {
    public var warningThreshold: Double  // 0.0-1.0 of max tokens
    public var compactionThreshold: Double
    public var evictionThreshold: Double
}

public struct ContextCompressionPolicy: Sendable {
    public var enabled: Bool
    public var algorithm: String?
    public var aggressiveness: Double  // 0.0-1.0
}

public struct WorkingMemoryPolicy: Sendable {
    public var maxItems: Int
    public var evictionPolicy: String
}
```

**File:** `Sources/ColonyCore/Policies/ColonyRoutingPolicy.swift`

```swift
public struct RetryPolicy: Sendable {
    public var maxAttempts: Int
    public var backoffMultiplier: Double
    public var initialDelayNanoseconds: UInt64
    public var maxDelayNanoseconds: UInt64
}

public struct ProviderRoute: Sendable {
    public var providerID: ProviderID
    public var priority: Int
    public var capabilities: ColonyCapabilities
    public var maxConcurrentRequests: Int?
}

public enum PrivacyBehavior: Sendable {
    case allow
    case deny
    case anonymize
}

public enum BudgetPeriod: Sendable {
    case perRequest
    case perMinute
    case perHour
    case perDay
    case total
}

public typealias ProviderID = String

public struct CostPreference: Sendable {
    public var maxCostPerRequest: Double?
    public var preferredProviders: [ProviderID]?
}

public struct CostPolicy: Sendable {
    public var budget: Double?
    public var period: BudgetPeriod
    public var alertThreshold: Double
}

public enum RoutingStrategy: Sendable {
    case priorityBased
    case leastLoaded
    case roundRobin
    case costOptimized
    case capabilityMatch
}

public struct ColonyRoutingPolicy: Sendable {
    public var defaultRoute: ProviderRoute?
    public var routes: [ProviderRoute]
    public var retryPolicy: RetryPolicy
    public var costPolicy: CostPolicy?
    public var routingStrategy: RoutingStrategy
    public var fallbackToOnDevice: Bool
}
```

**File:** `Sources/ColonyCore/Policies/ColonyToolPolicy.swift`

```swift
public struct ColonyToolPolicy: Sendable {
    public var enabledTools: Set<String>
    public var disabledTools: Set<String>
    public var toolTimeouts: [String: UInt64]  // tool name -> timeout in nanoseconds
    public var maxInvocationsPerRound: Int
    public var permissionPolicy: ToolPermissionPolicy
}

public enum ToolPermissionPolicy: Sendable, Equatable {
    case allowAll
    case denyAll
    case allowList(Set<String>)
    case denyList(Set<String>)
    case prompt
}
```

**Thread Safety:** All Policy types are `Sendable`.

---

### 1.17 Interrupts

**File:** `Sources/ColonyCore/ColonyInterrupts.swift`

```swift
public enum ColonyInterruptPayload: Codable, Sendable {
    case toolApprovalRequired(toolCallID: String, toolName: String, arguments: String)
    case maxRoundtripsReached
    case maxTokensReached
    case custom(String, Codable)
}

public enum ColonyResumePayload: Codable, Sendable {
    case approved(ColonyToolApprovalDecision)
    case rejected(reason: String?)
    case cancelled
    case custom(String, Codable)
}
```

**Thread Safety:** `Sendable`, `Codable`

---

### 1.18 Harness Protocol

**File:** `Sources/ColonyCore/ColonyHarnessProtocol.swift`

```swift
public struct ColonyHarnessSessionID: Hashable, Codable, Sendable {
    public let rawValue: String
}

public enum ColonyHarnessLifecycleState: String, Codable, Sendable {
    case initial
    case running
    case interrupted
    case finished
    case cancelled
}

public enum ColonyHarnessProtocolVersion: String, Codable, Sendable {
    public static let current = ColonyHarnessProtocolVersion.v1
    case v1
}

public enum ColonyHarnessEventType: String, Codable, Sendable {
    case runStarted
    case runResumed
    case runFinished
    case runInterrupted
    case runCancelled
    case assistantDelta
    case toolRequest
    case toolResult
    case toolDenied
}

public struct ColonyHarnessAssistantDeltaPayload: Codable, Equatable, Sendable {
    public let content: String
    public let isFinal: Bool
}

public struct ColonyHarnessToolRequestPayload: Codable, Equatable, Sendable {
    public let toolCallID: String
    public let toolName: String
    public let argumentsJSON: String
}

public struct ColonyHarnessToolResultPayload: Codable, Equatable, Sendable {
    public let toolCallID: String
    public let content: String
    public let wasTruncated: Bool
}

public struct ColonyHarnessToolDeniedPayload: Codable, Equatable, Sendable {
    public let toolCallID: String
    public let toolName: String
    public let reason: String?
}

public enum ColonyHarnessEventPayload: Codable, Equatable, Sendable {
    case runStarted(runID: UUID, threadID: ColonyThreadID)
    case runResumed(runID: UUID)
    case runFinished(runID: UUID, output: String)
    case runInterrupted(runID: UUID, reason: String)
    case runCancelled(runID: UUID)
    case assistantDelta(ColonyHarnessAssistantDeltaPayload)
    case toolRequest(ColonyHarnessToolRequestPayload)
    case toolResult(ColonyHarnessToolResultPayload)
    case toolDenied(ColonyHarnessToolDeniedPayload)
}

public struct ColonyHarnessEventEnvelope: Codable, Equatable, Sendable {
    public let version: ColonyHarnessProtocolVersion
    public let sessionID: ColonyHarnessSessionID
    public let runID: UUID
    public let sequence: Int
    public let timestamp: Date
    public let eventType: ColonyHarnessEventType
    public let payload: ColonyHarnessEventPayload
}

public struct ColonyHarnessInterruption: Sendable {
    public let runID: UUID
    public let interruptID: ColonyInterruptID
    public let reason: String
    public let requiredAction: String
}
```

**Thread Safety:** All Harness types are `Sendable`, `Codable`.

---

### 1.19 Scratchbook

**File:** `Sources/ColonyCore/ColonyScratchbook.swift`

```swift
public struct ColonyWorkspaceItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var content: String
    public var isPinned: Bool
    public var isComplete: Bool
    public let createdAt: Date
    public var updatedAt: Date
    public var tags: [String]
}

public struct ColonyWorkspace: Codable, Sendable, Equatable {
    public var items: [ColonyWorkspaceItem]
    public var nextPinnedOrder: Int
    public var nextUnpinnedOrder: Int
}

@available(*, deprecated, renamed: "ColonyWorkspaceItem")
public typealias ColonyScratchItem = ColonyWorkspaceItem

@available(*, deprecated, renamed: "ColonyWorkspace")
public typealias ColonyScratchbook = ColonyWorkspace
```

**File:** `Sources/ColonyCore/ColonyScratchbookStore.swift`

```swift
public enum ColonyScratchbookStore {
    case memory
    case filesystem(ColonyFileSystem.Service)
}
```

**File:** `Sources/ColonyCore/ColonyScratchbookPolicy.swift`

```swift
public struct ColonyScratchbookPolicy: Sendable {
    public var enabled: Bool
    public var maxItems: Int?
    public var maxItemSizeBytes: Int?
    public var retainCompletedItems: Bool
    public var store: ColonyScratchbookStore
}
```

**Thread Safety:** All Scratchbook types are `Sendable`.

---

### 1.20 Compaction & Summarization

**File:** `Sources/ColonyCore/ColonyCompactionPolicy.swift`

```swift
public enum ColonyCompactionPolicy: Sendable {
    case disabled
    case tokenBased(threshold: Int, target: Int)
    case messageBased(threshold: Int, target: Int)

    public static let `default`: ColonyCompactionPolicy
}
```

**File:** `Sources/ColonyCore/ColonySummarizationPolicy.swift`

```swift
public struct ColonySummarizationPolicy: Sendable {
    public var enabled: Bool
    public var threshold: Int  // tokens
    public var targetTokens: Int
    public var prompt: String?
    public var modelName: String?

    public static let `default`: ColonySummarizationPolicy
}
```

**Thread Safety:** Both are `Sendable`.

---

### 1.21 Tokenizer

**File:** `Sources/ColonyCore/ColonyTokenizer.swift`

```swift
public protocol ColonyTokenizer: Sendable {
    func countTokens(_ text: String) async throws -> Int
}

public struct ColonyApproximateTokenizer: ColonyTokenizer, Sendable {
    public init(averageTokensPerWord: Double = 1.3)

    public func countTokens(_ text: String) async throws -> Int {
        // Approximation: count words and multiply by average
        let words = text.split(whereSeparator: { $0.isWhitespace }).count
        return Int(Double(words) * averageTokensPerWord)
    }
}
```

**File:** `Sources/ColonyCore/ColonyBudgetError.swift`

```swift
public enum BudgetError: Error, Sendable, Equatable {
    case tokenBudgetExceeded(current: Int, limit: Int)
    case contextWindowExceeded(limit: Int)
    case outputTruncated(reason: String)
}

@available(*, deprecated, renamed: "BudgetError")
public typealias ColonyBudgetError = BudgetError
```

**Thread Safety:** `Sendable`

---

### 1.22 Built-In Tool Definitions

**File:** `Sources/ColonyCore/ColonyBuiltInToolDefinitions.swift`

```swift
public enum ColonyBuiltInToolDefinitions {
    // Planning tools
    public static var writeTodos: ColonyTool.Definition { get }
    public static var readTodos: ColonyTool.Definition { get }

    // Filesystem tools
    public static var ls: ColonyTool.Definition { get }
    public static var readFile: ColonyTool.Definition { get }
    public static var writeFile: ColonyTool.Definition { get }
    public static var editFile: ColonyTool.Definition { get }
    public static var glob: ColonyTool.Definition { get }
    public static var grep: ColonyTool.Definition { get }

    // Scratchbook tools
    public static var scratchRead: ColonyTool.Definition { get }
    public static var scratchAdd: ColonyTool.Definition { get }
    public static var scratchUpdate: ColonyTool.Definition { get }
    public static var scratchComplete: ColonyTool.Definition { get }
    public static var scratchPin: ColonyTool.Definition { get }
    public static var scratchUnpin: ColonyTool.Definition { get }

    // Workspace tools
    public static var workspaceRead: ColonyTool.Definition { get }
    public static var workspaceAdd: ColonyTool.Definition { get }
    public static var workspaceUpdate: ColonyTool.Definition { get }
    public static var workspaceComplete: ColonyTool.Definition { get }
    public static var workspacePin: ColonyTool.Definition { get }
    public static var workspaceUnpin: ColonyTool.Definition { get }

    // Shell tools
    public static var execute: ColonyTool.Definition { get }
    public static var shellRead: ColonyTool.Definition { get }
    public static var shellOpen: ColonyTool.Definition { get }
    public static var shellWrite: ColonyTool.Definition { get }
    public static var shellClose: ColonyTool.Definition { get }

    // Git tools
    public static var gitStatus: ColonyTool.Definition { get }
    public static var gitDiff: ColonyTool.Definition { get }
    public static var gitCommit: ColonyTool.Definition { get }
    public static var gitBranch: ColonyTool.Definition { get }
    public static var gitPush: ColonyTool.Definition { get }
    public static var gitPreparePR: ColonyTool.Definition { get }

    // LSP tools
    public static var lspSymbols: ColonyTool.Definition { get }
    public static var lspDiagnostics: ColonyTool.Definition { get }
    public static var lspReferences: ColonyTool.Definition { get }
    public static var lspApplyEdit: ColonyTool.Definition { get }

    // Memory tools
    public static var memoryRecall: ColonyTool.Definition { get }
    public static var memoryRemember: ColonyTool.Definition { get }

    // Web/Code search tools
    public static var webSearch: ColonyTool.Definition { get }
    public static var codeSearch: ColonyTool.Definition { get }

    // MCP tools
    public static var mcpListResources: ColonyTool.Definition { get }
    public static var mcpReadResource: ColonyTool.Definition { get }

    // Plugin tools
    public static var pluginListTools: ColonyTool.Definition { get }
    public static var pluginInvoke: ColonyTool.Definition { get }

    // Patch tool
    public static var applyPatch: ColonyTool.Definition { get }

    // Subagent tool
    public static var task: ColonyTool.Definition { get }
}
```

**Thread Safety:** `Sendable`

---

### 1.23 Prompts

**File:** `Sources/ColonyCore/ColonyPrompts.swift`

```swift
public enum ColonyPrompts {
    public static func systemPrompt(for capabilities: ColonyCapabilities) -> String
    public static func toolPrompt(for tool: ColonyTool.Definition) -> String
    public static func planningPrompt() -> String
}
```

**Thread Safety:** `Sendable`

---

### 1.24 Todo

**File:** `Sources/ColonyCore/ColonyTodo.swift`

```swift
public struct ColonyTodo: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var content: String
    public var isComplete: Bool
    public var priority: Int?
    public let createdAt: Date
    public var updatedAt: Date
}
```

**Thread Safety:** `Sendable`, `Codable`

---

### 1.25 Version

**File:** `Sources/ColonyCore/ColonyCoreVersion.swift`

```swift
public enum ColonyCoreVersion {
    public static let string: String
    public static var major: Int { get }
    public static var minor: Int { get }
    public static var patch: Int { get }
}
```

---

## Module 2: Colony (via `import Colony`)

### 2.1 Entry Point

**File:** `Sources/Colony/Colony.swift`

```swift
@_exported import ColonyCore
@_exported import HiveCore

public enum Colony {
    /// Starts a new Colony runtime with the given model name.
    public static func start(
        modelName: String,
        profile: ColonyProfile = .device,
        configure: @Sendable (inout ColonyConfiguration) -> Void = { _ in }
    ) throws -> ColonyRuntime
}

public enum ColonyVersion {
    public static let string: String  // "1.0.0-rc.1"
}
```

**Thread Safety:** `Sendable`

---

### 2.2 Profile & Lane Configuration

**File:** `Sources/Colony/ColonyAgentFactory.swift`

```swift
public struct ColonyBuilderError: Error, Sendable {}

public enum ColonyProfile: Sendable {
    case device      // On-device ~4k token budget
    case cloud       // Cloud with generous limits

    public var displayName: String { get }
}

public typealias ColonyLane = AgentMode

public struct ColonyLaneConfigurationPreset: Sendable {
    public var capabilities: ColonyCapabilities
    public var maxRoundtrips: Int
    public var compactionPolicy: ColonyCompactionPolicy
    public var summarizationPolicy: ColonySummarizationPolicy
}

public struct ColonySystemClock: HiveClock, Sendable {}

public struct ColonyNoopLogger: HiveLogger, Sendable {}

// Main builder (ColonyAgentFactory deprecated alias)
public struct ColonyBuilder: Sendable {
    public init()

    @discardableResult
    public func model(name: String) -> ColonyBuilder

    @discardableResult
    public func profile(_ profile: ColonyProfile) -> ColonyBuilder

    @discardableResult
    public func configure(_ block: @escaping @Sendable (inout ColonyConfiguration) -> Void) -> ColonyBuilder

    public func build() throws -> ColonyRuntime
}

@available(*, deprecated, renamed: "ColonyBuilder")
public typealias ColonyAgentFactory = ColonyBuilder
```

**Thread Safety:** `Sendable`

---

### 2.3 ColonyRuntime

**File:** `Sources/Colony/ColonyRuntime.swift`

```swift
public struct ColonyRuntime: Sendable {
    // Injected from HiveCore - this struct wraps HiveRuntime<ColonySchema>
    // Key methods exposed through Sendable interface
}
```

**Thread Safety:** `Sendable` (delegates to HiveCore)

---

### 2.4 Runtime Surface

**File:** `Sources/Colony/ColonyRuntimeSurface.swift`

```swift
public typealias ColonyOutcome = HiveRunOutcome<ColonySchema>

public enum ColonyRun {
    public enum CheckpointPolicy: Sendable {
        case disabled
        case everyStep
        case every(steps: Int)
        case onInterrupt
    }

    public enum StreamingMode: Sendable {
        case events
        case values
        case updates
        case combined
    }

    public struct Transcript: Sendable {
        public let messages: [HiveChatMessage]
        public let finalAnswer: String?
        public let todos: [ColonyTodo]
    }

    public struct StartRequest: Sendable {
        public var threadID: HiveThreadID
        public var input: String
        public var options: HiveRunOptions?
    }

    public struct ResumeRequest: Sendable {
        public var interruptID: UUID
        public var decision: ColonyToolApprovalDecision
    }

    public enum Outcome: Sendable {
        case finished(output: String, metadata: [String: String]?)
        case interrupted(interrupt: HiveInterruption<ColonySchema>)
        case cancelled(output: String?, metadata: [String: String]?)
        case outOfSteps(maxSteps: Int, output: String?)
    }

    public struct Handle: Sendable {
        public let runID: ColonyRunID
        public let attemptID: ColonyRunAttemptID
        public let outcome: ColonyOutcome
    }
}
```

**Thread Safety:** All Runtime Surface types are `Sendable`.

---

### 2.5 Run Control

**File:** `Sources/Colony/ColonyRunControl.swift`

```swift
public struct ColonyRunStartRequest: Sendable {
    public var threadID: ColonyThreadID
    public var input: String
    public var checkpointPolicy: ColonyRun.CheckpointPolicy
}

public struct ColonyRunResumeRequest: Sendable {
    public var interruptID: ColonyInterruptID
    public var decision: ColonyToolApprovalDecision
}

public struct ColonyRunControl: Sendable {
    public var startRequest: ColonyRunStartRequest?
    public var resumeRequest: ColonyRunResumeRequest?
}
```

**Thread Safety:** `Sendable`

---

### 2.6 Model Configuration

**File:** `Sources/Colony/ColonyPublicAPI.swift`

```swift
// Foundation Models Configuration
public struct ColonyFoundationModelsConfiguration: Sendable {
    public var additionalInstructions: String?
    public var prewarmSession: Bool
    public var toolInstructionVerbosity: ColonyToolInstructionVerbosity
}

public enum ColonyToolInstructionVerbosity: String, Sendable {
    case minimal
    case standard
    case detailed
}

// On-Device Policy
public struct ColonyOnDevicePolicy: Sendable {
    public var privacyBehavior: ColonyPrivacyBehavior
    public var networkBehavior: ColonyNetworkBehavior
    public var fallbackToCloud: Bool
}

public enum ColonyPrivacyBehavior: String, Sendable {
    case allow
    case anonymize
    case deny
}

public enum ColonyNetworkBehavior: String, Sendable {
    case allow
    case prompt
    case deny
}

// Provider Configuration
public struct ColonyProviderConfiguration: Sendable {
    public var providerID: String
    public var baseURL: URL?
    public var apiKey: String?
    public var headers: [String: String]
    public var timeout: TimeInterval?
}

public struct ColonyProviderPolicy: Sendable {
    public var maxAttemptsPerProvider: Int
    public var backoff: ColonyProviderBackoff
    public var costCeiling: Double?
    public var gracefulDegradation: ColonyGracefulDegradationPolicy
}

public enum ColonyGracefulDegradationPolicy: Sendable {
    case failFast
    case retryWithExponentialBackoff
    case fallbackToOnDevice
}
```

**Thread Safety:** All `Sendable`

---

### 2.7 Model Router

**File:** `Sources/Colony/ColonyModelRouter.swift`

```swift
public protocol ColonyModelClient: Sendable {
    func complete(_ request: ColonyInferenceRequest) async throws -> ColonyInferenceResponse
    func stream(_ request: ColonyInferenceRequest) async throws -> AsyncThrowingStream<ColonyInferenceStreamChunk, Error>
}

public struct ColonyInferenceRequest: Sendable {
    public var model: String
    public var messages: [HiveChatMessage]
    public var tools: [ColonyTool.Definition]?
    public var systemPrompt: String?
    public var temperature: Double?
    public var maxTokens: Int?
}

public struct ColonyInferenceResponse: Sendable {
    public var message: HiveChatMessage
    public var usage: ColonyTokenUsage?
    public var stopReason: String?
}

public enum ColonyInferenceStreamChunk: Sendable {
    case contentDelta(String)
    case contentComplete
    case toolCall(ColonyTool.Call)
    case done
}

public struct ColonyModelRouter: ColonyModelClient, Sendable {
    public init(onDevice: ColonyOnDeviceModelRouter?, providers: [ColonyProviderRouter]?)
    public func complete(_ request: ColonyInferenceRequest) async throws -> ColonyInferenceResponse
    public func stream(_ request: ColonyInferenceRequest) async throws -> AsyncThrowingStream<ColonyInferenceStreamChunk, Error>
}

public enum ColonyModelRouterError: Error, CustomStringConvertible {
    case noProviderAvailable
    case allProvidersFailed([Error])
    case invalidRequest(String)
}
```

**Thread Safety:** `Sendable`

---

### 2.8 Provider Router

**File:** `Sources/Colony/ColonyProviderRouter.swift`

```swift
public enum ProviderRoutingError: Error, Sendable, CustomStringConvertible, Equatable {
    case providerNotFound(String)
    case routingFailed(String)
    case configurationError(String)
}

public typealias ColonyProviderRouterError = ProviderRoutingError

public struct ColonyProviderRouter: HiveModelRouter, Sendable {
    public init(
        configuration: ColonyProviderConfiguration,
        policy: ColonyProviderPolicy,
        modelClient: AnyHiveModelClient
    )
}
```

**Thread Safety:** `Sendable`

---

### 2.9 On-Device Model Router

**File:** `Sources/Colony/ColonyOnDeviceModelRouter.swift`

```swift
public enum OnDeviceRoutingError: Error, Sendable, CustomStringConvertible {
    case modelNotFound(String)
    case initializationFailed(String)
    case inferenceFailed(String)
}

public typealias ColonyOnDeviceModelRouterError = OnDeviceRoutingError

public struct ColonyOnDeviceModelRouter: HiveModelRouter, Sendable {
    public init(modelName: String)
}
```

**Thread Safety:** `Sendable`

---

### 2.10 Foundation Models Client

**File:** `Sources/Colony/ColonyFoundationModelsClient.swift`

```swift
public enum OnDeviceModelError: Error, Sendable, CustomStringConvertible {
    case notAvailable
    case initializationFailed(String)
    case inferenceFailed(String)
    case unsupportedModel(String)
}

public typealias ColonyFoundationModelsClientError = OnDeviceModelError

public struct ColonyFoundationModelsClient: HiveModelClient, Sendable {
    public init(
        modelName: String,
        configuration: ColonyFoundationModelsConfiguration?
    )
}
```

**Thread Safety:** `Sendable`

---

### 2.11 Agent Types

**File:** `Sources/Colony/ColonyAgent.swift`

```swift
public enum ColonySchema: HiveSchema {
    public enum Channels {
        public static let messages: String { get }
        public static let finalAnswer: String { get }
        public static let todos: String { get }
        public static let scratchpad: String { get }
        public static let artifacts: String { get }
    }

    public typealias Event = HiveAgentEvent<ColonySchema>
}

public struct ColonyContext: Sendable {
    public var configuration: ColonyConfiguration
    public var filesystem: (any ColonyFileSystemBackend)?
    public var shell: (any ColonyShellBackend)?
    public var subagents: (any ColonySubagentRegistry)?
}

public enum ColonyAgent {
    public static func compile() throws -> CompiledHiveGraph<ColonySchema>
}
```

**Thread Safety:** `Sendable`

---

### 2.12 Observability

**File:** `Sources/Colony/ColonyObservability.swift`

```swift
public struct ColonyObservabilityEvent: Codable, Sendable, Equatable {
    public let name: ColonyEventName
    public let timestamp: Date
    public let runID: ColonyRunID?
    public let threadID: ColonyThreadID?
    public let attributes: [String: String]
}

public protocol ColonyObservabilitySink: Sendable {
    func emit(_ event: ColonyObservabilityEvent) async
}

public actor ColonyObservabilityEmitter {
    public init(sinks: [any ColonyObservabilitySink])
    public func emit(_ event: ColonyObservabilityEvent) async
    public func emitHarnessEnvelope(_ envelope: ColonyHarnessEventEnvelope, threadID: ColonyThreadID?) async
}
```

**Thread Safety:** `Sendable`, Actor

---

### 2.13 Artifact Store

**File:** `Sources/Colony/ColonyArtifactStore.swift`

```swift
public struct ColonyArtifactRetentionPolicy: Sendable {
    public var maxArtifacts: Int?
    public var maxAge: TimeInterval?
}

public struct ColonyArtifactRecord: Codable, Sendable, Equatable {
    public let id: ColonyArtifactID
    public let threadID: ColonyThreadID
    public let runID: ColonyRunID?
    public let kind: String
    public let createdAt: Date
    public let redacted: Bool
    public let metadata: [String: String]
}

public actor ColonyArtifactStore {
    public init(
        baseURL: URL,
        retentionPolicy: ColonyArtifactRetentionPolicy = ColonyArtifactRetentionPolicy(),
        redactionPolicy: ColonyRedactionPolicy = ColonyRedactionPolicy(),
        fileManager: FileManager = .default
    ) throws

    public func put(
        threadID: ColonyThreadID,
        runID: ColonyRunID?,
        kind: String,
        content: String,
        metadata: [String: String] = [:],
        redact: Bool = true,
        createdAt: Date = Date()
    ) async throws -> ColonyArtifactRecord

    public func list(
        threadID: ColonyThreadID? = nil,
        runID: ColonyRunID? = nil,
        kind: String? = nil,
        limit: Int? = nil
    ) async throws -> [ColonyArtifactRecord]

    public func readContent(id: String) async throws -> String?
    public func enforceRetention(now: Date = Date()) async throws -> [String]
}
```

**Thread Safety:** Actor (`Sendable`)

---

### 2.14 Persistence Support

**File:** `Sources/Colony/ColonyPersistenceSupport.swift`

```swift
public struct ColonyRedactionPolicy: Sendable {
    public static let defaultSensitiveKeys: Set<String>

    public var sensitiveKeys: Set<String>
    public var replacement: String

    public func redact(key: String, value: String) -> String
    public func redact(values: [String: String]) -> [String: String]
    public func redactInlineSecrets(in value: String) -> String
}
```

**Thread Safety:** `Sendable`

---

### 2.15 Durable Checkpoint Store

**File:** `Sources/Colony/ColonyDurableCheckpointStore.swift`

```swift
public actor ColonyDurableCheckpointStore<Schema: HiveSchema>: HiveCheckpointQueryableStore {
    public init(baseURL: URL, fileManager: FileManager = .default) throws

    public func save(_ checkpoint: HiveCheckpoint<Schema>) async throws
    public func loadLatest(threadID: HiveThreadID) async throws -> HiveCheckpoint<Schema>?
    public func listCheckpoints(threadID: HiveThreadID, limit: Int?) async throws -> [HiveCheckpointSummary]
    public func loadCheckpoint(threadID: HiveThreadID, id: HiveCheckpointID) async throws -> HiveCheckpoint<Schema>?
}
```

**Thread Safety:** Actor (`Sendable`)

---

### 2.16 Durable Run State Store

**File:** `Sources/Colony/ColonyDurableRunStateStore.swift`

```swift
public enum ColonyRunPhase: String, Codable, Sendable, Equatable {
    case running
    case interrupted
    case finished
    case cancelled
}

public struct ColonyRunStateSnapshot: Codable, Sendable, Equatable {
    public let runID: ColonyRunID
    public let sessionID: ColonyHarnessSessionID
    public let threadID: ColonyThreadID
    public let phase: ColonyRunPhase
    public let lastEventSequence: Int
    public let updatedAt: Date
}

public actor ColonyDurableRunStateStore {
    public init(baseURL: URL, fileManager: FileManager = .default) throws

    public func appendEvent(_ envelope: ColonyHarnessEventEnvelope, threadID: ColonyThreadID) async throws
    public func loadRunState(runID: UUID) async throws -> ColonyRunStateSnapshot?
    public func listRunStates(limit: Int? = nil) async throws -> [ColonyRunStateSnapshot]
    public func loadEvents(runID: UUID, limit: Int? = nil) async throws -> [ColonyHarnessEventEnvelope]
    public func latestInterruptedRun(sessionID: ColonyHarnessSessionID?) async throws -> ColonyRunStateSnapshot?
    public func latestRunState(sessionID: ColonyHarnessSessionID?) async throws -> ColonyRunStateSnapshot?
}
```

**Thread Safety:** Actor (`Sendable`)

---

### 2.17 Harness Session

**File:** `Sources/Colony/ColonyHarnessSession.swift`

```swift
public enum HarnessError: Error, Sendable {
    case sessionNotFound
    case eventAppendFailed(Error)
    case invalidStateTransition
}

public typealias ColonyHarnessSessionError = HarnessError
```

**Thread Safety:** `Sendable`

---

### 2.18 Bootstrap (Deprecated)

**File:** `Sources/Colony/ColonyBootstrap.swift`

```swift
@available(*, deprecated, renamed: "Colony")
public enum ColonyBootstrap {
    @available(*, deprecated, renamed: "Colony.start")
    public static func bootstrap(
        modelName: String,
        profile: ColonyProfile = .device,
        threadID: HiveThreadID? = nil
    ) throws -> ColonyRuntime
}
```

**Thread Safety:** `Sendable`

---

### 2.19 RunHandle Convenience Extensions

**File:** `Sources/Colony/ColonyRunHandleConvenience.swift`

```swift
extension HiveRunHandle where Schema == ColonySchema {
    public var isFinished: Bool { get async }
    public var isInterrupted: Bool { get async }
    public func complete() async throws -> HiveRunOutcome<Schema>
}

extension HiveRunOutcome {
    public var isFinished: Bool { get }
    public var isInterrupted: Bool { get }
    public var finishedOutput: HiveRunOutput<Schema>? { get }
    public var interruption: HiveInterruption<Schema>? { get }
}
```

**Thread Safety:** Extensions on `Sendable` types

---

## Appendix A: Deprecated Typealiases

| Deprecated Name | Replacement | Module |
|----------------|-------------|--------|
| `ColonyFoundationModelConfiguration` | `ColonyFoundationModelsConfiguration` | Colony |
| `ColonyOnDeviceModelPolicy` | `ColonyOnDevicePolicy` | Colony |
| `ColonyProviderID` | `ColonyModel.ProviderID` | Colony |
| `ColonyProvider` | `ColonyModel.Provider` | Colony |
| `ColonyProviderRoutingPolicy` | `ColonyProviderPolicy` | Colony |
| `ColonyVirtualPath` | `ColonyFileSystem.VirtualPath` | ColonyCore |
| `ColonyFileInfo` | `ColonyFileSystem.FileInfo` | ColonyCore |
| `ColonyGrepMatch` | `ColonyFileSystem.GrepMatch` | ColonyCore |
| `FileSystemError` | `ColonyFileSystem.Error` | ColonyCore |
| `ColonyFileSystemError` | `ColonyFileSystem.Error` | ColonyCore |
| `ColonyFileSystemService` | `ColonyFileSystem.Service` | ColonyCore |
| `ColonyFileSystemBackend` | `ColonyFileSystem.Service` | ColonyCore |
| `ColonyBudgetError` | `BudgetError` | ColonyCore |
| `ColonyScratchItem` | `ColonyWorkspaceItem` | ColonyCore |
| `ColonyScratchbook` | `ColonyWorkspace` | ColonyCore |
| `ColonyAgentFactory` | `ColonyBuilder` | Colony |
| `ColonyBootstrap` | `Colony` | Colony |

---

## Appendix B: Internal/Package Types

These should not be used directly by external consumers:

| Type | Access | File |
|------|--------|------|
| `ColonyDefaultSubagentRegistry` | `package` | ColonyDefaultSubagentRegistry.swift:5 |
| `ColonyPersistenceIO` | `internal` | ColonyPersistenceSupport.swift:75 |

---

## Appendix C: Complete Public API Dependency Graph

```
Colony (namespace)
├── .start(modelName:profile:configure:)  // Primary entry point
├── .version.string                       // "1.0.0-rc.1"

ColonyBuilder (formerly ColonyAgentFactory)
├── .model(name:)
├── .profile(_:)
├── .configure(_:)
└── .build() -> ColonyRuntime

ColonyRuntime
└── (wraps HiveRuntime<ColonySchema>)

ColonyProfile
├── .device   // ~4k token budget
└── .cloud    // Generous limits

ColonyConfiguration (3-tier init)
├── ModelConfiguration
├── SafetyConfiguration
├── ContextConfiguration
└── PromptConfiguration

ColonyOutcome = HiveRunOutcome<ColonySchema>

ColonyRun
├── CheckpointPolicy
├── StreamingMode
├── Transcript
├── StartRequest
└── ResumeRequest
```
