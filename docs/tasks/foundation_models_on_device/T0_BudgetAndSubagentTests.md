Prompt:
Add Swift Testing coverage for strict request-level budgeting (system + tools) and for subagent on-device budget inheritance.

Goal:
Create failing tests that define the required behavior before implementation changes.

Task Breakdown:
1. Add a test that proves request budgeting accounts for the system prompt (not just compaction).
2. Add a test that proves tool definition payload is accounted for in the request budget.
3. Add a test that validates deterministic trimming: oldest messages trimmed first, newest preserved.
4. Add a test that validates subagent invocations inherit the on-device budget posture (4k-safe by default).

Expected Output:
- New tests under `Tests/ColonyTests/` using Swift Testing.
- Tests fail against current codebase until WS-A/WS-B are implemented.

