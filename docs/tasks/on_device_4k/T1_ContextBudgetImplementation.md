Prompt:
Implement strict request-level context budget enforcement for Colony model invocation.

Goal:
Add a typed, deterministic hard cap for model request input tokens that is safe for 4k on-device execution.

Task Breakdown:
1. Add configuration surface to `ColonyConfiguration` for hard request token cap.
2. Set a 4k default cap for `.onDevice4k` profile and leave cloud profile unbounded unless configured.
3. In `ColonyAgent.model(...)`, enforce cap after system prompt assembly and before model stream invocation.
4. Ensure trimming strategy preserves system message and most recent conversation messages.
5. Keep implementation `Sendable`-safe and deterministic.
6. Run tests and confirm new tests pass.

Expected Output:
- Code changes in `Sources/Colony` and `Sources/ColonyCore` with strict budget enforcement.
- Passing test suite for new budget behavior.

