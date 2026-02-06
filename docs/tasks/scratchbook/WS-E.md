Prompt:
Decompose WS-E (4k Density Fixes) into test-first, implementation, and review tasks. Ensure tool-result eviction previews respect the configured eviction token budget.

Goal:
Cap tool eviction previews as a function of `toolResultEvictionTokenLimit` to prevent dominance of the 4k window.

Task Breakdown:
1. Tests (Swift Testing): add failing tests covering:
   - Tool eviction preview length is capped by `toolResultEvictionTokenLimit`
   - Budget behavior is stable and deterministic
2. Implementation:
   - Apply budget-aware trimming in eviction preview generation
   - Ensure integration respects existing eviction logic
3. Review:
   - Validate no regressions in tool eviction behavior
   - Confirm budgeted previews cannot exceed configured limits

Expected Output:
- Tool eviction previews are budget-aware and covered by deterministic tests.

