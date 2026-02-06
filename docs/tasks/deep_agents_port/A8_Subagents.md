Prompt:
Improve Colony subagents to ship a first-party “general-purpose” subagent stack and enforce isolation semantics.

Goal:
Provide an out-of-the-box `ColonySubagentRegistry` implementation that can run a subagent harness with isolated context windows, mirroring Deep Agents’ default compiled general-purpose subagent.

Task Breakdown:
1. Add a `ColonyDefaultSubagentRegistry` (or similarly named) implementation in `Sources/Colony`:
   - supports at least `general-purpose`
   - uses its own Hive/Colony runtime per task (ephemeral thread id)
   - does not inherit parent message history (prompt-only)
   - disables recursive subagents by default
2. Add tests verifying:
   - `task` with `subagent_type=general-purpose` runs and returns a single tool result
   - subagent does not mutate parent store except via filesystem side-effects (if enabled)

Expected Output:
- First-party subagent runner usable by consumers without custom registries.
- Tests covering basic behavior.
