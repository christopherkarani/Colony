// ColonyDeprecations.swift
// Consolidated deprecated typealiases for the ColonyCore module.
// These exist solely for backward compatibility — prefer the canonical names.

import Foundation

// MARK: - From ColonyID.swift

@available(*, deprecated, renamed: "ColonyIDDomain.Thread")
public typealias ThreadDomain = ColonyIDDomain.Thread
@available(*, deprecated, renamed: "ColonyIDDomain.Interrupt")
public typealias InterruptDomain = ColonyIDDomain.Interrupt
@available(*, deprecated, renamed: "ColonyIDDomain.HarnessSession")
public typealias HarnessSessionDomain = ColonyIDDomain.HarnessSession
@available(*, deprecated, renamed: "ColonyIDDomain.Project")
public typealias ProjectDomain = ColonyIDDomain.Project
@available(*, deprecated, renamed: "ColonyIDDomain.ProductSession")
public typealias ProductSessionDomain = ColonyIDDomain.ProductSession
@available(*, deprecated, renamed: "ColonyIDDomain.ProductSessionVersion")
public typealias ProductSessionVersionDomain = ColonyIDDomain.ProductSessionVersion
@available(*, deprecated, renamed: "ColonyIDDomain.ShareToken")
public typealias ShareTokenDomain = ColonyIDDomain.ShareToken

// MARK: - From ColonyRuntimeSurface.swift

@available(*, deprecated, renamed: "ColonyRun.CheckpointPolicy")
public typealias ColonyRunCheckpointPolicy = ColonyRun.CheckpointPolicy

@available(*, deprecated, renamed: "ColonyRun.StreamingMode")
public typealias ColonyRunStreamingMode = ColonyRun.StreamingMode

@available(*, deprecated, renamed: "ColonyRun.Options")
public typealias ColonyRunOptions = ColonyRun.Options

@available(*, deprecated, renamed: "ColonyRun.Transcript")
public typealias ColonyTranscript = ColonyRun.Transcript

@available(*, deprecated, renamed: "ColonyRun.Interruption")
public typealias ColonyRunInterruption = ColonyRun.Interruption

@available(*, deprecated, renamed: "ColonyRun.Outcome")
public typealias ColonyRunOutcome = ColonyRun.Outcome

@available(*, deprecated, renamed: "ColonyRun.StartRequest")
public typealias ColonyRunStartRequest = ColonyRun.StartRequest

@available(*, deprecated, renamed: "ColonyRun.ResumeRequest")
public typealias ColonyRunResumeRequest = ColonyRun.ResumeRequest

@available(*, deprecated, renamed: "ColonyRun.Handle")
public typealias ColonyRunHandle = ColonyRun.Handle

@available(*, deprecated, renamed: "ColonyRun.CheckpointConfiguration")
public typealias ColonyCheckpointConfiguration = ColonyRun.CheckpointConfiguration

// MARK: - From ColonyShell.swift

@available(*, deprecated, renamed: "ColonyShell.TerminalMode")
public typealias ColonyShellTerminalMode = ColonyShell.TerminalMode

@available(*, deprecated, renamed: "ColonyShell.ExecutionError")
public typealias ColonyShellExecutionError = ColonyShell.ExecutionError

@available(*, deprecated, renamed: "ColonyShell.ExecutionRequest")
public typealias ColonyShellExecutionRequest = ColonyShell.ExecutionRequest

@available(*, deprecated, renamed: "ColonyShell.ExecutionResult")
public typealias ColonyShellExecutionResult = ColonyShell.ExecutionResult

@available(*, deprecated, renamed: "ColonyShell.SessionOpenRequest")
public typealias ColonyShellSessionOpenRequest = ColonyShell.SessionOpenRequest

@available(*, deprecated, renamed: "ColonyShell.SessionReadResult")
public typealias ColonyShellSessionReadResult = ColonyShell.SessionReadResult

@available(*, deprecated, renamed: "ColonyShell.SessionSnapshot")
public typealias ColonyShellSessionSnapshot = ColonyShell.SessionSnapshot

@available(*, deprecated, renamed: "ColonyShell.ConfinementPolicy")
public typealias ColonyShellConfinementPolicy = ColonyShell.ConfinementPolicy

// MARK: - From ColonyFileSystem.swift

@available(*, deprecated, renamed: "ColonyFileSystem.VirtualPath")
public typealias ColonyVirtualPath = ColonyFileSystem.VirtualPath

@available(*, deprecated, renamed: "ColonyFileSystem.FileInfo")
public typealias ColonyFileInfo = ColonyFileSystem.FileInfo

@available(*, deprecated, renamed: "ColonyFileSystem.GrepMatch")
public typealias ColonyGrepMatch = ColonyFileSystem.GrepMatch

@available(*, deprecated, renamed: "ColonyFileSystem.Error")
public typealias ColonyFileSystemError = ColonyFileSystem.Error

@available(*, deprecated, renamed: "ColonyFileSystem.DiskBackend")
public typealias ColonyDiskFileSystemBackend = ColonyFileSystem.DiskBackend

// MARK: - From ColonyInferenceSurface.swift

@available(*, deprecated, renamed: "ColonyTool.Definition")
public typealias ColonyToolDefinition = ColonyTool.Definition

@available(*, deprecated, renamed: "ColonyTool.Call")
public typealias ColonyToolCall = ColonyTool.Call

@available(*, deprecated, renamed: "ColonyTool.Result")
public typealias ColonyToolResult = ColonyTool.Result

// MARK: - From ColonyModelCapabilities.swift

@available(*, deprecated, renamed: "ColonyTool.PromptStrategy")
public typealias ColonyToolPromptStrategy = ColonyTool.PromptStrategy

// MARK: - From ColonyToolSafetyPolicy.swift

@available(*, deprecated, renamed: "ColonyTool.RiskLevel")
public typealias ColonyToolRiskLevel = ColonyTool.RiskLevel

@available(*, deprecated, renamed: "ColonyToolApproval.RequirementReason")
public typealias ColonyToolApprovalRequirementReason = ColonyToolApproval.RequirementReason

@available(*, deprecated, renamed: "ColonyToolApproval.Disposition")
public typealias ColonyToolApprovalDisposition = ColonyToolApproval.Disposition

@available(*, deprecated, renamed: "ColonyToolApproval.RetryDisposition")
public typealias ColonyToolRetryDisposition = ColonyToolApproval.RetryDisposition

@available(*, deprecated, renamed: "ColonyToolApproval.ResultDurability")
public typealias ColonyToolResultDurability = ColonyToolApproval.ResultDurability

@available(*, deprecated, renamed: "ColonyTool.PolicyMetadata")
public typealias ColonyToolPolicyMetadata = ColonyTool.PolicyMetadata

// MARK: - From ColonyToolApproval.swift

@available(*, deprecated, renamed: "ColonyToolApproval.PerToolDecision")
public typealias ColonyPerToolApprovalDecision = ColonyToolApproval.PerToolDecision

@available(*, deprecated, renamed: "ColonyToolApproval.PerToolEntry")
public typealias ColonyPerToolApproval = ColonyToolApproval.PerToolEntry

@available(*, deprecated, renamed: "ColonyToolApproval.Decision")
public typealias ColonyToolApprovalDecision = ColonyToolApproval.Decision

@available(*, deprecated, renamed: "ColonyToolApproval.Policy")
public typealias ColonyToolApprovalPolicy = ColonyToolApproval.Policy

// MARK: - From ColonyCapabilities.swift

@available(*, deprecated, renamed: "ColonyAgentCapabilities")
public typealias ColonyCapabilities = ColonyAgentCapabilities

// MARK: - From ColonyToolName.swift

@available(*, deprecated, renamed: "ColonyTool.Name")
public typealias ColonyToolName = ColonyTool.Name

// MARK: - From ColonyCodingBackends.swift

@available(*, deprecated, renamed: "ColonyPatch.Result")
public typealias ColonyApplyPatchResult = ColonyPatch.Result

@available(*, deprecated, renamed: "ColonyWebSearch.ResultItem")
public typealias ColonyWebSearchResultItem = ColonyWebSearch.ResultItem

@available(*, deprecated, renamed: "ColonyWebSearch.Result")
public typealias ColonyWebSearchResult = ColonyWebSearch.Result

@available(*, deprecated, renamed: "ColonyCodeSearch.Match")
public typealias ColonyCodeSearchMatch = ColonyCodeSearch.Match

@available(*, deprecated, renamed: "ColonyCodeSearch.Result")
public typealias ColonyCodeSearchResult = ColonyCodeSearch.Result

@available(*, deprecated, renamed: "ColonyMCP.Resource")
public typealias ColonyMCPResource = ColonyMCP.Resource

// MARK: - From ColonyHarnessProtocol.swift

@available(*, deprecated, renamed: "ColonyHarness.LifecycleState")
public typealias ColonyHarnessLifecycleState = ColonyHarness.LifecycleState

@available(*, deprecated, renamed: "ColonyHarness.ProtocolVersion")
public typealias ColonyHarnessProtocolVersion = ColonyHarness.ProtocolVersion

@available(*, deprecated, renamed: "ColonyHarness.EventType")
public typealias ColonyHarnessEventType = ColonyHarness.EventType

@available(*, deprecated, renamed: "ColonyHarness.EventPayload")
public typealias ColonyHarnessEventPayload = ColonyHarness.EventPayload

@available(*, deprecated, renamed: "ColonyHarness.AssistantDeltaPayload")
public typealias ColonyHarnessAssistantDeltaPayload = ColonyHarness.AssistantDeltaPayload

@available(*, deprecated, renamed: "ColonyHarness.ToolRequestPayload")
public typealias ColonyHarnessToolRequestPayload = ColonyHarness.ToolRequestPayload

@available(*, deprecated, renamed: "ColonyHarness.ToolResultPayload")
public typealias ColonyHarnessToolResultPayload = ColonyHarness.ToolResultPayload

@available(*, deprecated, renamed: "ColonyHarness.ToolDeniedPayload")
public typealias ColonyHarnessToolDeniedPayload = ColonyHarness.ToolDeniedPayload

@available(*, deprecated, renamed: "ColonyHarness.EventEnvelope")
public typealias ColonyHarnessEventEnvelope = ColonyHarness.EventEnvelope

@available(*, deprecated, renamed: "ColonyHarness.Interruption")
public typealias ColonyHarnessInterruption = ColonyHarness.Interruption

// MARK: - From ColonyCompositeFileSystemBackend.swift

@available(*, deprecated, renamed: "ColonyFileSystem.CompositeBackend")
public typealias ColonyCompositeFileSystemBackend = ColonyFileSystem.CompositeBackend

// MARK: - From ColonySubagents.swift

@available(*, deprecated, renamed: "ColonySubagent.Descriptor")
public typealias ColonySubagentDescriptor = ColonySubagent.Descriptor

@available(*, deprecated, renamed: "ColonySubagent.Context")
public typealias ColonySubagentContext = ColonySubagent.Context

@available(*, deprecated, renamed: "ColonySubagent.FileReference")
public typealias ColonySubagentFileReference = ColonySubagent.FileReference

@available(*, deprecated, renamed: "ColonySubagent.Request")
public typealias ColonySubagentRequest = ColonySubagent.Request

@available(*, deprecated, renamed: "ColonySubagent.Result")
public typealias ColonySubagentResult = ColonySubagent.Result

// MARK: - From ColonyMemory.swift

@available(*, deprecated, renamed: "ColonyMemory.Item")
public typealias ColonyMemoryItem = ColonyMemory.Item

@available(*, deprecated, renamed: "ColonyMemory.RecallRequest")
public typealias ColonyMemoryRecallRequest = ColonyMemory.RecallRequest

@available(*, deprecated, renamed: "ColonyMemory.RecallResult")
public typealias ColonyMemoryRecallResult = ColonyMemory.RecallResult

@available(*, deprecated, renamed: "ColonyMemory.RememberRequest")
public typealias ColonyMemoryRememberRequest = ColonyMemory.RememberRequest

@available(*, deprecated, renamed: "ColonyMemory.RememberResult")
public typealias ColonyMemoryRememberResult = ColonyMemory.RememberResult

// MARK: - From ColonyLSP.swift

@available(*, deprecated, renamed: "ColonyLSP.Position")
public typealias ColonyLSPPosition = ColonyLSP.Position

@available(*, deprecated, renamed: "ColonyLSP.Range")
public typealias ColonyLSPRange = ColonyLSP.Range

@available(*, deprecated, renamed: "ColonyLSP.SymbolsRequest")
public typealias ColonyLSPSymbolsRequest = ColonyLSP.SymbolsRequest

@available(*, deprecated, renamed: "ColonyLSP.Symbol")
public typealias ColonyLSPSymbol = ColonyLSP.Symbol

@available(*, deprecated, renamed: "ColonyLSP.DiagnosticsRequest")
public typealias ColonyLSPDiagnosticsRequest = ColonyLSP.DiagnosticsRequest

@available(*, deprecated, renamed: "ColonyLSP.Diagnostic")
public typealias ColonyLSPDiagnostic = ColonyLSP.Diagnostic

@available(*, deprecated, renamed: "ColonyLSP.ReferencesRequest")
public typealias ColonyLSPReferencesRequest = ColonyLSP.ReferencesRequest

@available(*, deprecated, renamed: "ColonyLSP.Reference")
public typealias ColonyLSPReference = ColonyLSP.Reference

@available(*, deprecated, renamed: "ColonyLSP.TextEdit")
public typealias ColonyLSPTextEdit = ColonyLSP.TextEdit

@available(*, deprecated, renamed: "ColonyLSP.ApplyEditRequest")
public typealias ColonyLSPApplyEditRequest = ColonyLSP.ApplyEditRequest

@available(*, deprecated, renamed: "ColonyLSP.ApplyEditResult")
public typealias ColonyLSPApplyEditResult = ColonyLSP.ApplyEditResult

// MARK: - From ColonyGit.swift

@available(*, deprecated, renamed: "ColonyGit.StatusRequest")
public typealias ColonyGitStatusRequest = ColonyGit.StatusRequest

@available(*, deprecated, renamed: "ColonyGit.StatusEntry")
public typealias ColonyGitStatusEntry = ColonyGit.StatusEntry

@available(*, deprecated, renamed: "ColonyGit.StatusResult")
public typealias ColonyGitStatusResult = ColonyGit.StatusResult

@available(*, deprecated, renamed: "ColonyGit.DiffRequest")
public typealias ColonyGitDiffRequest = ColonyGit.DiffRequest

@available(*, deprecated, renamed: "ColonyGit.DiffResult")
public typealias ColonyGitDiffResult = ColonyGit.DiffResult

@available(*, deprecated, renamed: "ColonyGit.CommitRequest")
public typealias ColonyGitCommitRequest = ColonyGit.CommitRequest

@available(*, deprecated, renamed: "ColonyGit.CommitResult")
public typealias ColonyGitCommitResult = ColonyGit.CommitResult

@available(*, deprecated, renamed: "ColonyGit.BranchRequest")
public typealias ColonyGitBranchRequest = ColonyGit.BranchRequest

@available(*, deprecated, renamed: "ColonyGit.BranchResult")
public typealias ColonyGitBranchResult = ColonyGit.BranchResult

@available(*, deprecated, renamed: "ColonyGit.PushRequest")
public typealias ColonyGitPushRequest = ColonyGit.PushRequest

@available(*, deprecated, renamed: "ColonyGit.PushResult")
public typealias ColonyGitPushResult = ColonyGit.PushResult

@available(*, deprecated, renamed: "ColonyGit.PreparePullRequestRequest")
public typealias ColonyGitPreparePullRequestRequest = ColonyGit.PreparePullRequestRequest

@available(*, deprecated, renamed: "ColonyGit.PreparePullRequestResult")
public typealias ColonyGitPreparePullRequestResult = ColonyGit.PreparePullRequestResult

// MARK: - From ColonyToolAudit.swift

@available(*, deprecated, renamed: "ColonyToolAudit.DecisionKind")
public typealias ColonyToolAuditDecisionKind = ColonyToolAudit.DecisionKind

@available(*, deprecated, renamed: "ColonyToolAudit.Event")
public typealias ColonyToolAuditEvent = ColonyToolAudit.Event

@available(*, deprecated, renamed: "ColonyToolAudit.RecordPayload")
public typealias ColonyToolAuditRecordPayload = ColonyToolAudit.RecordPayload

@available(*, deprecated, renamed: "ColonyToolAudit.SignedRecord")
public typealias ColonySignedToolAuditRecord = ColonyToolAudit.SignedRecord

@available(*, deprecated, renamed: "ColonyToolAudit.AuditError")
public typealias ColonyToolAuditError = ColonyToolAudit.AuditError

@available(*, deprecated, renamed: "ColonyToolAudit.FileSystemLogStore")
public typealias ColonyFileSystemToolAuditLogStore = ColonyToolAudit.FileSystemLogStore

@available(*, deprecated, renamed: "ColonyToolAudit.Recorder")
public typealias ColonyToolAuditRecorder = ColonyToolAudit.Recorder
