Prompt:
Decompose WS-B (Tools + Capability Gating) into test-first, implementation, and review tasks. Implement Scratchbook tool surface with strict scoping to the thread Scratchbook file only.

Goal:
Add scratchbook tools (`scratch_read`, `scratch_add`, `scratch_update`, `scratch_complete`, `scratch_pin`, `scratch_unpin`) and gate them behind `ColonyCapabilities.scratchbook`, wired into built-in tool execution and on-device allowlist.

Task Breakdown:
1. Tests (Swift Testing): add failing tests covering:
   - Capability gating: tools unavailable when scratchbook capability off
   - Tool execution paths for CRUD + pin/complete
   - Tool operations scoped to the thread scratchbook file only
   - `scratch_read` returns compact rendered view
2. Implementation:
   - Add `ColonyCapabilities.scratchbook`
   - Define built-in tool definitions with minimal/short names
   - Implement tool execution in `ColonyTools.executeBuiltIn(...)`
   - Wire on-device allowlist to include scratchbook tools
3. Review:
   - Verify tool API clarity and misuse resistance
   - Confirm no arbitrary filesystem writes are possible
   - Ensure Sendable/structured concurrency correctness

Expected Output:
- Built-in scratchbook tools are defined, gated, and tested; tool execution mutates only the thread scratchbook file.

