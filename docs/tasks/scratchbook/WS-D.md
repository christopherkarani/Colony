Prompt:
Decompose WS-D (Offload + Compactor) into test-first, implementation, and review tasks. Extend history offload to update Scratchbook with a compact summary + next actions, preferring a compactor subagent when available.

Goal:
Integrate a compactor subagent for scratchbook updates during history offload, with deterministic fallback when subagents are unavailable.

Task Breakdown:
1. Tests (Swift Testing): add failing tests covering:
   - Offload writes history to `/conversation_history/...` as today
   - Scratchbook is updated with summary + next actions after offload
   - Compactor path is used when subagents are configured
   - Fallback path writes deterministic summary referencing history file path
2. Implementation:
   - Add compactor subagent type to registry (isolated, no recursive subagents)
   - Extend `maybeSummarize(...)` to update Scratchbook post-offload
   - Implement fallback deterministic summary note
3. Review:
   - Verify subagent isolation and concurrency safety
   - Ensure Scratchbook updates are deterministic and scoped

Expected Output:
- Offload flow updates Scratchbook via compactor or deterministic fallback, with tests covering both paths.

