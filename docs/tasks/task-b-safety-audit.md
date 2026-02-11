Prompt:
Implement a product-grade tool safety policy engine with signed immutable audit logs.

Goal:
Enforce per-tool risk and mandatory approval for mutating/execution actions; persist signed decisions.

Task Breakdown:
1. Add risk model enums and policy engine in ColonyCore.
2. Add decision model supporting per-tool approve/deny.
3. Extend runtime approval handling for partial approvals.
4. Add audit signer abstraction + HMAC signer implementation.
5. Add immutable hash-chained audit log store (append-only).
6. Integrate logging on approvals/denials and auto-decisions.
7. Add tests: risk enforcement, partial approve/deny, signature validation, hash-chain integrity.

Expected Output:
- Policy + audit infrastructure code.
- Runtime integration with tests proving mandatory approval for mutating tools.
