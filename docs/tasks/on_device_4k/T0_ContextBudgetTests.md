Prompt:
Implement failing Swift Testing coverage for strict request-level 4k context budgeting in Colony.

Goal:
Define behavior first: model requests must respect a hard token cap and keep the newest messages when trimming is required.

Task Breakdown:
1. Add tests in `Tests/ColonyTests` that exercise the real runtime path.
2. Create a recording model stub to capture the final `HiveChatRequest` passed to the model.
3. Add a test that configures a low hard cap and verifies request token count does not exceed it.
4. Add a test that verifies oldest conversation messages are trimmed first while newest messages are preserved.
5. Add a test that verifies on-device factory profile wires the hard 4k cap by default.
6. Run tests and confirm they fail before implementation.

Expected Output:
- New failing tests that precisely define strict budget behavior.
- Clear assertions on token count and recency-preserving trimming.

