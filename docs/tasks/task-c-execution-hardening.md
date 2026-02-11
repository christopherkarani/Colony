Prompt:
Implement execution hardening: PTY-backed shell runner and strict workspace confinement.

Goal:
Harden command execution and file path safety against traversal/symlink bypass.

Task Breakdown:
1. Add hardened shell backend implementing ColonyShellBackend:
   - PTY mode, timeout, cancellation, max output bytes, optional environment whitelist.
2. Add confinement policy type for shell runner (allowed root, denied prefixes).
3. Harden ColonyDiskFileSystemBackend resolve logic:
   - canonical root, boundary-aware prefix checks, symlink-safe parent resolution.
4. Add security tests for path traversal and symlink escape attempts.

Expected Output:
- Hardened shell backend and path resolver updates.
- Security-focused tests with deterministic behavior.
