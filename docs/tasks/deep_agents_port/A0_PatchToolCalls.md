Prompt:
Implement Deep Agents-style dangling tool call patching in Colony, including the tool-approval rejection path.

Goal:
Ensure Colony never sends a message history to the model that contains assistant tool calls without corresponding tool messages (tool_call_id closure), matching Deep Agents `PatchToolCallsMiddleware`.

Task Breakdown:
1. Add a pre-model middleware pass that scans `messages` and inserts deterministic tool cancellation messages for any dangling tool calls.
2. Update the tool-approval rejection path to emit one cancellation tool message per rejected tool call id (instead of only a system message).
3. Ensure patched tool messages use stable ids (`tool:{toolCallID}`) and do not break later successful tool execution (real tool result should overwrite cancellation if it arrives).
4. Add Swift Testing tests that fail before implementation and pass after:
   - Rejecting tool approval produces tool messages closing each tool call.
   - Sending a new user message after an interrupted run patches previous dangling tool calls before next model invocation.

Expected Output:
- Colony tool-call histories are provider-valid (no dangling tool calls).
- New tests in `Tests/ColonyTests` covering the above scenarios.
