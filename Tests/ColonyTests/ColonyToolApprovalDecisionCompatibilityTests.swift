import Foundation
import Testing
import Colony

@Test("Tool approval decision decodes legacy cancelled payload")
func toolApprovalDecisionDecodesLegacyCancelledPayload() throws {
    let data = Data(#""cancelled""#.utf8)
    let decoded = try JSONDecoder().decode(ColonyToolApprovalDecision.self, from: data)
    #expect(decoded == .cancelled)
}

@Test("Tool approval decision preserves legacy raw-value shape")
func toolApprovalDecisionPreservesLegacyRawValueShape() {
    #expect(ColonyToolApprovalDecision(rawValue: "approved") == .approved)
    #expect(ColonyToolApprovalDecision(rawValue: "rejected") == .rejected)
    #expect(ColonyToolApprovalDecision(rawValue: "cancelled") == .cancelled)
    #expect(ColonyToolApprovalDecision(rawValue: "per_tool") == .perTool([]))

    #expect(ColonyToolApprovalDecision.approved.rawValue == "approved")
    #expect(ColonyToolApprovalDecision.rejected.rawValue == "rejected")
    #expect(ColonyToolApprovalDecision.cancelled.rawValue == "cancelled")
    #expect(
        ColonyToolApprovalDecision
            .perTool([ColonyPerToolApproval(toolCallID: "call-1", decision: .approved)])
            .rawValue == "per_tool"
    )
}

@Test("Legacy cancelled decision maps to deny semantics for tool calls")
func toolApprovalDecisionCancelledMapsToRejectForToolCallResolution() {
    let decision = ColonyToolApprovalDecision.cancelled
    #expect(decision.decision(forToolCallID: "tool-call-1") == .rejected)
}

@Test("Per-tool decision Codable path preserves explicit per-call approvals")
func toolApprovalDecisionPerToolCodableRoundTrip() throws {
    let value = ColonyToolApprovalDecision.perTool(
        [
            ColonyPerToolApproval(toolCallID: "call-1", decision: .approved),
            ColonyPerToolApproval(toolCallID: "call-2", decision: .rejected),
        ]
    )

    let encoded = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(ColonyToolApprovalDecision.self, from: encoded)
    #expect(decoded == value)
}
