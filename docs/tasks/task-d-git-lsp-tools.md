Prompt:
Add first-class Git and LSP backends/tools for coding workflows.

Goal:
Expose Git/LSP operations as typed backends and built-in tool definitions.

Task Breakdown:
1. Add `ColonyGitBackend` and `ColonyLSPBackend` protocols/types in ColonyCore.
2. Add capabilities for Git/LSP and config wiring.
3. Add built-in tool definitions:
   - git_status, git_diff, git_commit, git_branch, git_push, git_prepare_pr
   - lsp_symbols, lsp_diagnostics, lsp_references, lsp_apply_edit
4. Wire execution in ColonyAgent tool executor.
5. Add unit tests for tool dispatch and argument decoding.

Expected Output:
- New backends and built-in tools with tests.
