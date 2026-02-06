Prompt:
Implement Deep Agents-style summarization + history offload in Colony.

Goal:
When configured and message history exceeds a threshold, offload evicted messages to `/conversation_history/{thread_id}.md` and replace the in-context history with a summary message + preserved tail.

Task Breakdown:
1. Add a `ColonySummarizationPolicy` configuration:
   - trigger (token threshold)
   - keep (last N messages or tokens)
   - history path prefix (default `/conversation_history`)
2. Implement summarization in a pre-model middleware pass:
   - partition messages (filter prior summary messages)
   - offload evicted messages to a thread-scoped markdown file (append semantics)
   - generate a summary via the model with tools disabled
   - rewrite message history to summary + preserved tail (using removeAll marker)
3. Add Swift Testing tests with a scripted model:
   - triggers summarization and writes history file
   - ensures messages include summary and reference to file path

Expected Output:
- Summarization reduces in-context history while preserving retrievable full history.
- Tests for trigger + file write + message rewrite.
