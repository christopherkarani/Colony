Prompt:
Review strict context budget changes for correctness, type safety, API clarity, and regression risk.

Goal:
Verify the implementation complies with the immutable plan and does not regress existing Colony behavior.

Task Breakdown:
1. Review request-cap trimming logic for correctness and determinism.
2. Validate API surface in `ColonyConfiguration` and factory profile defaults.
3. Confirm tests cover key edge cases (cap compliance, recency retention, profile defaults).
4. Identify any gaps and produce a concrete fix list.

Expected Output:
- Prioritized findings with file/line references.
- Explicit statement if no critical findings remain.

