import Foundation
import Testing
@_spi(ColonyInternal) import Swarm
@testable import Colony

// MARK: - ToolPermissionPolicy Tests

@Test("ToolPermissionPolicy.unrestricted never requires approval")
func toolPermissionPolicyUnrestricted() {
    let policy = ToolPermissionPolicy.unrestricted

    #expect(policy.requiresApproval(for: "write_file") == false)
    #expect(policy.requiresApproval(for: "execute") == false)
    #expect(policy.requiresApproval(for: "any_tool") == false)
}

@Test("ToolPermissionPolicy.requireApproval always requires approval")
func toolPermissionPolicyRequireApproval() {
    let policy = ToolPermissionPolicy.requireApproval

    #expect(policy.requiresApproval(for: "ls") == true)
    #expect(policy.requiresApproval(for: "read_file") == true)
    #expect(policy.requiresApproval(for: "any_tool") == true)
}

@Test("ToolPermissionPolicy.allowList only requires approval for non-listed tools")
func toolPermissionPolicyAllowList() {
    let policy = ToolPermissionPolicy.allowList(["ls", "read_file", "glob"])

    #expect(policy.requiresApproval(for: "ls") == false)
    #expect(policy.requiresApproval(for: "read_file") == false)
    #expect(policy.requiresApproval(for: "glob") == false)
    #expect(policy.requiresApproval(for: "write_file") == true)
    #expect(policy.requiresApproval(for: "execute") == true)
}

@Test("ToolPermissionPolicy.allowList with array convenience initializer")
func toolPermissionPolicyAllowListConvenience() {
    let policy = ToolPermissionPolicy.allowList(["ls", "read_file"])

    #expect(policy.requiresApproval(for: "ls") == false)
    #expect(policy.requiresApproval(for: "write_file") == true)
}

@Test("ToolPermissionPolicy checks multiple tools")
func toolPermissionPolicyMultipleTools() {
    let policy = ToolPermissionPolicy.allowList(["ls", "read_file"])

    #expect(policy.requiresApproval(for: ["ls", "read_file"]) == false)
    #expect(policy.requiresApproval(for: ["ls", "write_file"]) == true)
    #expect(policy.requiresApproval(for: ["write_file", "edit_file"]) == true)
}

// MARK: - ColonyToolPolicy Initialization Tests

@Test("ColonyToolPolicy default initialization")
func colonyToolPolicyDefaultInit() {
    let policy = ColonyToolPolicy()

    #expect(policy.requiresApproval(for: "ls") == false)
    #expect(policy.requiresApproval(for: "read_file") == false)
    #expect(policy.requiresApproval(for: "write_file") == true) // mutation risk level
    #expect(policy.requiresApproval(for: "execute") == true) // execution risk level
    #expect(policy.requiresApproval(for: "git_push") == true) // network risk level
}

@Test("ColonyToolPolicy custom initialization")
func colonyToolPolicyCustomInit() {
    let policy = ColonyToolPolicy(
        permissionPolicy: .allowList(["custom_tool"]),
        riskOverrides: ["custom_tool": .execution],
        requiredApprovalRisks: [.execution, .network],
        defaultRiskLevel: .readOnly
    )

    #expect(policy.requiresApproval(for: "custom_tool") == true) // overridden to execution (in requiredApprovalRisks)
    #expect(policy.requiresApproval(for: "unknown_tool") == true) // not in allow list, so requires approval
}

@Test("ColonyToolPolicy unrestricted convenience")
func colonyToolPolicyUnrestricted() {
    let policy = ColonyToolPolicy.unrestricted

    #expect(policy.permissionPolicy == .unrestricted)
    #expect(policy.requiresApproval(for: "write_file") == false) // mutation does not require approval (not in requiredApprovalRisks)
    #expect(policy.requiresApproval(for: "ls") == false) // readOnly does not
}

@Test("ColonyToolPolicy strict convenience")
func colonyToolPolicyStrict() {
    let policy = ColonyToolPolicy.strict

    #expect(policy.permissionPolicy == .requireApproval)
    #expect(policy.requiresApproval(for: "ls") == true)
    #expect(policy.requiresApproval(for: "read_file") == true)
}

// MARK: - Risk Level Tests

@Test("ColonyToolPolicy risk level for built-in tools")
func colonyToolPolicyRiskLevels() {
    let policy = ColonyToolPolicy()

    #expect(policy.riskLevel(for: "ls") == .readOnly)
    #expect(policy.riskLevel(for: "read_file") == .readOnly)
    #expect(policy.riskLevel(for: "write_todos") == .stateMutation)
    #expect(policy.riskLevel(for: "scratch_add") == .stateMutation)
    #expect(policy.riskLevel(for: "write_file") == .mutation)
    #expect(policy.riskLevel(for: "edit_file") == .mutation)
    #expect(policy.riskLevel(for: "execute") == .execution)
    #expect(policy.riskLevel(for: "task") == .execution)
    #expect(policy.riskLevel(for: "git_push") == .network)
    #expect(policy.riskLevel(for: "web_search") == .network)
}

@Test("ColonyToolPolicy risk level overrides")
func colonyToolPolicyRiskLevelOverrides() {
    let policy = ColonyToolPolicy(
        riskOverrides: ["ls": .execution, "write_file": .readOnly]
    )

    #expect(policy.riskLevel(for: "ls") == .execution)
    #expect(policy.riskLevel(for: "write_file") == .readOnly)
    #expect(policy.riskLevel(for: "read_file") == .readOnly) // unchanged
}

@Test("ColonyToolPolicy default risk level for unknown tools")
func colonyToolPolicyDefaultRiskLevel() {
    let policy = ColonyToolPolicy(defaultRiskLevel: .stateMutation)

    #expect(policy.riskLevel(for: "unknown_tool") == .stateMutation)
    #expect(policy.riskLevel(for: "ls") == .readOnly) // built-in takes precedence
}

// MARK: - Approval Requirement Tests

@Test("ColonyToolPolicy requires approval for mandatory risk levels")
func colonyToolPolicyMandatoryRiskLevels() {
    let policy = ColonyToolPolicy(
        permissionPolicy: .unrestricted, // normally no approval required
        requiredApprovalRisks: [.mutation, .execution, .network]
    )

    #expect(policy.requiresApproval(for: "ls") == false) // readOnly
    #expect(policy.requiresApproval(for: "write_todos") == false) // stateMutation
    #expect(policy.requiresApproval(for: "write_file") == true) // mutation
    #expect(policy.requiresApproval(for: "execute") == true) // execution
    #expect(policy.requiresApproval(for: "git_push") == true) // network
}

@Test("ColonyToolPolicy requires approval for permission policy")
func colonyToolPolicyPermissionPolicyApproval() {
    let policy = ColonyToolPolicy(
        permissionPolicy: .allowList(["ls", "read_file"]),
        requiredApprovalRisks: [] // no mandatory risk levels
    )

    #expect(policy.requiresApproval(for: "ls") == false)
    #expect(policy.requiresApproval(for: "read_file") == false)
    #expect(policy.requiresApproval(for: "write_file") == true) // not in allow list
    #expect(policy.requiresApproval(for: "execute") == true) // not in allow list
}

@Test("ColonyToolPolicy requires approval combines risk and policy")
func colonyToolPolicyCombinedApproval() {
    let policy = ColonyToolPolicy(
        permissionPolicy: .allowList(["write_file"]), // allow write_file
        requiredApprovalRisks: [.mutation] // but mutation requires approval
    )

    // write_file is in allow list but is mutation level
    #expect(policy.requiresApproval(for: "write_file") == true)

    // read_file is not in allow list but is readOnly
    #expect(policy.requiresApproval(for: "read_file") == true)

    // ls is not in allow list but is readOnly
    #expect(policy.requiresApproval(for: "ls") == true)
}

@Test("ColonyToolPolicy requires approval for multiple tools")
func colonyToolPolicyMultipleToolApproval() {
    let policy = ColonyToolPolicy()

    #expect(policy.requiresApproval(for: ["ls", "read_file"]) == false)
    #expect(policy.requiresApproval(for: ["ls", "write_file"]) == true)
    #expect(policy.requiresApproval(for: ["write_file", "execute"]) == true)
}

// MARK: - Assessment Tests

@Test("ColonyToolPolicy assess returns correct assessments")
func colonyToolPolicyAssess() async throws {
    let policy = ColonyToolPolicy(
        permissionPolicy: .allowList(["ls"]),
        requiredApprovalRisks: [.mutation]
    )

    let toolCalls = [
        HiveToolCall(id: "call-1", name: "ls", argumentsJSON: "{}"),
        HiveToolCall(id: "call-2", name: "write_file", argumentsJSON: "{}"),
        HiveToolCall(id: "call-3", name: "read_file", argumentsJSON: "{}")
    ]

    let assessments = policy.assess(toolCalls: toolCalls)

    #expect(assessments.count == 3)

    // ls: allowed by policy, readOnly
    #expect(assessments[0].toolCallID == "call-1")
    #expect(assessments[0].toolName == "ls")
    #expect(assessments[0].riskLevel == .readOnly)
    #expect(assessments[0].requiresApproval == false)
    #expect(assessments[0].reason == nil)

    // write_file: mutation requires approval
    #expect(assessments[1].toolCallID == "call-2")
    #expect(assessments[1].toolName == "write_file")
    #expect(assessments[1].riskLevel == .mutation)
    #expect(assessments[1].requiresApproval == true)
    #expect(assessments[1].reason == .mandatoryRiskLevel)

    // read_file: not in allow list
    #expect(assessments[2].toolCallID == "call-3")
    #expect(assessments[2].toolName == "read_file")
    #expect(assessments[2].riskLevel == .readOnly)
    #expect(assessments[2].requiresApproval == true)
    #expect(assessments[2].reason == .policyNotAllowListed)
}

@Test("ColonyToolPolicy assess with unrestricted policy")
func colonyToolPolicyAssessUnrestricted() async throws {
    let policy = ColonyToolPolicy(
        permissionPolicy: .unrestricted,
        requiredApprovalRisks: [.execution]
    )

    let toolCalls = [
        HiveToolCall(id: "call-1", name: "ls", argumentsJSON: "{}"),
        HiveToolCall(id: "call-2", name: "execute", argumentsJSON: "{}")
    ]

    let assessments = policy.assess(toolCalls: toolCalls)

    #expect(assessments[0].requiresApproval == false)
    #expect(assessments[1].requiresApproval == true)
    #expect(assessments[1].reason == .mandatoryRiskLevel)
}

@Test("ColonyToolPolicy assess with requireApproval policy")
func colonyToolPolicyAssessRequireApproval() async throws {
    let policy = ColonyToolPolicy(
        permissionPolicy: .requireApproval,
        requiredApprovalRisks: []
    )

    let toolCalls = [
        HiveToolCall(id: "call-1", name: "ls", argumentsJSON: "{}"),
        HiveToolCall(id: "call-2", name: "write_file", argumentsJSON: "{}")
    ]

    let assessments = policy.assess(toolCalls: toolCalls)

    #expect(assessments[0].requiresApproval == true)
    #expect(assessments[0].reason == ColonyToolApprovalRequirementReason.policyAlways)
    #expect(assessments[1].requiresApproval == true)
    #expect(assessments[1].reason == ColonyToolApprovalRequirementReason.policyAlways)
}

// MARK: - Approval Rules Integration Tests

@Test("ColonyToolPolicy resolveDecision returns nil without rule store")
func colonyToolPolicyResolveDecisionNoStore() async throws {
    let policy = ColonyToolPolicy()

    let decision = try await policy.resolveDecision(for: "write_file", consumeOneShot: true)

    #expect(decision == nil)
}

@Test("ColonyToolPolicy resolveDecision with rule store")
func colonyToolPolicyResolveDecisionWithStore() async throws {
    let store = ColonyInMemoryToolApprovalRuleStore(
        rules: [
            ColonyToolApprovalRule(
                pattern: .exact("write_file"),
                decision: .allowAlways
            )
        ]
    )
    let policy = ColonyToolPolicy(approvalRules: store)

    let decision = try await policy.resolveDecision(for: "write_file", consumeOneShot: true)

    #expect(decision?.decision == .allowAlways)
}

@Test("ColonyToolPolicy resolveDecision with no matching rule")
func colonyToolPolicyResolveDecisionNoMatch() async throws {
    let store = ColonyInMemoryToolApprovalRuleStore(
        rules: [
            ColonyToolApprovalRule(
                pattern: .exact("edit_file"),
                decision: .allowAlways
            )
        ]
    )
    let policy = ColonyToolPolicy(approvalRules: store)

    let decision = try await policy.resolveDecision(for: "write_file", consumeOneShot: true)

    #expect(decision == nil)
}

// MARK: - Backward Compatibility Tests

@Test("ColonyToolPolicy produces same results as ColonyToolSafetyPolicyEngine")
func colonyToolPolicyBackwardCompatibility() {
    let legacyPolicy = ColonyToolApprovalPolicy.allowList(["ls", "read_file"])
    let legacyEngine = ColonyToolSafetyPolicyEngine(
        approvalPolicy: legacyPolicy,
        riskLevelOverrides: ["custom": .execution],
        mandatoryApprovalRiskLevels: [.mutation, .execution],
        defaultRiskLevel: .readOnly
    )

    let unifiedPolicy = ColonyToolPolicy(
        permissionPolicy: .allowList(["ls", "read_file"]),
        riskOverrides: ["custom": .execution],
        requiredApprovalRisks: [.mutation, .execution],
        defaultRiskLevel: .readOnly
    )

    // Compare risk levels
    let tools = ["ls", "read_file", "write_file", "execute", "custom", "unknown"]
    for tool in tools {
        #expect(legacyEngine.riskLevel(for: tool) == unifiedPolicy.riskLevel(for: tool))
    }

    // Compare approval requirements
    #expect(legacyPolicy.requiresApproval(for: "ls") == unifiedPolicy.permissionPolicy.requiresApproval(for: "ls"))
    #expect(legacyPolicy.requiresApproval(for: "write_file") == unifiedPolicy.permissionPolicy.requiresApproval(for: "write_file"))
}

// MARK: - Edge Cases

@Test("ColonyToolPolicy with empty allow list requires approval for all")
func colonyToolPolicyEmptyAllowList() {
    let policy = ColonyToolPolicy(
        permissionPolicy: .allowList([]),
        requiredApprovalRisks: []
    )

    #expect(policy.requiresApproval(for: "ls") == true)
    #expect(policy.requiresApproval(for: "any_tool") == true)
}

@Test("ColonyToolPolicy with empty required risks only uses permission policy")
func colonyToolPolicyEmptyRequiredRisks() {
    let policy = ColonyToolPolicy(
        permissionPolicy: .allowList(["write_file"]),
        requiredApprovalRisks: []
    )

    #expect(policy.requiresApproval(for: "write_file") == false)
    #expect(policy.requiresApproval(for: "execute") == true)
}

@Test("ColonyToolPolicy risk levels are comparable")
func colonyToolPolicyRiskLevelComparison() {
    #expect(ColonyToolRiskLevel.readOnly < ColonyToolRiskLevel.stateMutation)
    #expect(ColonyToolRiskLevel.stateMutation < ColonyToolRiskLevel.mutation)
    #expect(ColonyToolRiskLevel.mutation < ColonyToolRiskLevel.execution)
    #expect(ColonyToolRiskLevel.execution < ColonyToolRiskLevel.network)
}

@Test("ColonyToolPolicy assess empty tool calls")
func colonyToolPolicyAssessEmpty() {
    let policy = ColonyToolPolicy()
    let toolCalls: [ColonyToolCall] = []

    let assessments = policy.assess(toolCalls: toolCalls)

    #expect(assessments.isEmpty)
}

@Test("ColonyToolPolicy default includes expected tools in allow list")
func colonyToolPolicyDefaultAllowListContents() {
    let policy = ColonyToolPolicy.default

    // These should not require approval (in default allow list and readOnly/stateMutation)
    #expect(policy.requiresApproval(for: "ls") == false)
    #expect(policy.requiresApproval(for: "read_file") == false)
    #expect(policy.requiresApproval(for: "glob") == false)
    #expect(policy.requiresApproval(for: "grep") == false)
    #expect(policy.requiresApproval(for: "read_todos") == false)
    #expect(policy.requiresApproval(for: "write_todos") == false) // stateMutation, not in requiredApprovalRisks

    // These should require approval (mutation/execution/network level)
    #expect(policy.requiresApproval(for: "write_file") == true)
    #expect(policy.requiresApproval(for: "execute") == true)
    #expect(policy.requiresApproval(for: "git_push") == true)
}
