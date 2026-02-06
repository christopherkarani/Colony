Prompt:
Review the budget enforcement + subagent inheritance + Foundation Models adapter for correctness, type safety, and misuse resistance.

Goal:
Ensure the harness remains deterministic, 4k-safe by default on-device, and does not regress existing behavior.

Task Breakdown:
1. Verify request budgeting logic is deterministic and includes tools.
2. Verify subagent configuration inherits the parent profile posture.
3. Verify Foundation Models adapter preserves Colony tool semantics (no direct tool execution inside the model session).
4. Verify `Sendable` and structured concurrency constraints are met.
5. Run the full test suite.

Expected Output:
- Written review findings (if any) and/or confirmation.
- Green test suite.

