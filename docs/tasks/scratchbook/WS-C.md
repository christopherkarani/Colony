Prompt:
Decompose WS-C (Prompt Injection) into test-first, implementation, and review tasks. Inject the compact Scratchbook view into the system prompt and default-disable redundant tool list on-device.

Goal:
Ensure `ColonyPrompts.systemPrompt(...)` injects `Scratchbook:\n...` when enabled, and add `includeToolListInSystemPrompt` to configuration with on-device default `false` and cloud default `true`.

Task Breakdown:
1. Tests (Swift Testing): add failing tests covering:
   - Scratchbook view is injected when enabled and filesystem backend exists
   - Injection respects `viewTokenLimit` and `maxRenderedItems`
   - `includeToolListInSystemPrompt` toggles tool list output
   - On-device default is `false`, cloud default is `true`
2. Implementation:
   - Add `includeToolListInSystemPrompt` to `ColonyConfiguration`
   - Add `ColonyScratchbookPolicy` config (if not already added by WS-A)
   - Inject Scratchbook view in system prompt under budget
   - Remove redundant tool list when config disables it
3. Review:
   - Validate configuration defaults preserve cloud behavior
   - Confirm prompt injection is deterministic and budgeted

Expected Output:
- System prompt includes a budgeted Scratchbook section when enabled, with tool list suppression on-device by default, all covered by tests.

