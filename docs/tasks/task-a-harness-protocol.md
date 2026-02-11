Prompt:
Implement a first-class harness session API and versioned protocol payload contracts for Colony.

Goal:
Provide stable API surface: create/start/stream/interrupted/resume/stop with typed versioned envelopes.

Task Breakdown:
1. Add new harness types in Colony/ColonyCore:
   - Session identifiers and lifecycle state.
   - Versioned envelope containing protocolVersion, eventType, sequence, timestamp, run/session IDs.
   - Payload enums for assistant_delta, tool_request, tool_result, tool_denied.
2. Add `ColonyHarnessSession` actor wrapping `ColonyRuntime` and translating Hive events/outcomes.
3. Add stop/cancel behavior and interruption resume API.
4. Add protocol contract tests for encoding/decoding and event ordering.

Expected Output:
- New source files for harness protocol/session.
- New tests that fail before implementation and pass after.
- No breaking changes to existing runtime APIs.
