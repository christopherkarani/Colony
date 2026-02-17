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

    #expect(ColonyToolApprovalDecision.approved.rawValue == "approved")
    #expect(ColonyToolApprovalDecision.rejected.rawValue == "rejected")
    #expect(ColonyToolApprovalDecision.cancelled.rawValue == "cancelled")
}

@Test("Legacy cancelled decision maps to deny semantics for tool calls")
func toolApprovalDecisionCancelledMapsToRejectForToolCallResolution() {
    let decision = ColonyToolApprovalDecision.cancelled
    #expect(decision.decision(forToolCallID: "tool-call-1") == .rejected)
}
