Prompt:
Harden dependency and release process and add CI quality gates.

Goal:
Remove local path dependency, enforce reproducible dependency policy, and add CI tests for contracts/e2e/security.

Task Breakdown:
1. Replace local Hive path dependency with remote/tagged dependency.
2. Ensure Package.resolved policy and check.
3. Add release policy docs: semantic versioning, changelog, upgrade notes.
4. Add CI workflow running:
   - swift test
   - protocol contract tests
   - E2E approve/deny/resume tests
   - security tests
5. Add repository docs for release and upgrade flow.

Expected Output:
- Updated Package.swift and docs.
- CI workflow under `.github/workflows` with required checks.
