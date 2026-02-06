Prompt:
Implement strict request-level budget enforcement (system + tools + messages) and ensure subagent defaults inherit the parent profile posture.

Goal:
Make on-device behavior 4k-safe by design, including for subagent model turns.

Task Breakdown:
1. Add a typed request-level cap to `ColonyConfiguration` (e.g. `requestTokenLimit: Int?`).
2. Wire `.onDevice4k` defaults to a hard 4k request cap; keep cloud unbounded unless configured.
3. In `ColonyAgent.model(...)`, enforce the request cap immediately before model invocation:
   - preserve the system message
   - keep newest conversation messages
   - account for tool definition payload in the budget
4. If tool definitions alone exceed the cap, fail deterministically with a Colony error.
5. Thread `ColonyProfile` into `ColonyDefaultSubagentRegistry` and derive its configuration via `ColonyAgentFactory.configuration(profile:modelName:)`, applying subagent-specific capability gating (no recursion).

Expected Output:
- Code changes in `Sources/Colony` and `Sources/ColonyCore` implementing WS-A + WS-B.
- All WS-A/WS-B tests pass.

