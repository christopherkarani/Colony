Prompt:
Implement prefix-based composite routing for Colony filesystem backends (Deep Agents `CompositeBackend` equivalent).

Goal:
Allow different filesystem backends to serve different virtual path prefixes with deterministic longest-prefix routing.

Task Breakdown:
1. Add `ColonyCompositeFileSystemBackend` implementing `ColonyFileSystemBackend` with:
   - `default` backend
   - `routes: [ColonyVirtualPath: any ColonyFileSystemBackend]`
   - deterministic longest-prefix match
2. Implement routing for `list/read/write/edit/glob/grep` with path prefix restore.
3. Add root listing behavior that exposes routed prefixes as virtual directories (optional parity).
4. Add Swift Testing tests for routing correctness + stable ordering.

Expected Output:
- Composite backend that supports Deep Agents-style routing by prefix.
- Tests for read/write routing and root listing.
