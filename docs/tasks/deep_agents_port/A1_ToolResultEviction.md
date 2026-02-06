Prompt:
Implement large tool result eviction to `/large_tool_results/{tool_call_id}` in Colony, similar to Deep Agents `FilesystemMiddleware`.

Goal:
Prevent large tool outputs from bloating context; when a tool result exceeds a configurable threshold and a filesystem backend exists, write full output to `/large_tool_results/{sanitizedToolCallID}` and replace tool message content with a preview + file reference.

Task Breakdown:
1. Add configuration to enable/disable eviction and set a token/character threshold (default aligned with Deep Agents: 20k tokens ~= 80k chars).
2. Implement eviction in tool execution so it applies to built-in tools, external tool registries, and `execute`.
3. Add deterministic preview formatting (head/tail with line numbers) and stable file path sanitization.
4. Add truncation safeguards for `ls`, `glob`, and `grep` outputs (Deep Agents truncates these rather than evicting).
5. Add Swift Testing tests:
   - Large tool output triggers file write and tool message replacement.
   - Eviction is skipped when filesystem backend is absent (and output is truncated or left intact per config).

Expected Output:
- Large tool results are automatically evicted with stable references.
- Tests verifying file creation + message replacement.
