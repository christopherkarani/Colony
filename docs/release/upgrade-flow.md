# Colony Upgrade Flow

Guide for upgrading Colony and its dependencies.

---

## Upgrading Colony

### Step 1: Check CHANGELOG.md

Always read `CHANGELOG.md` before upgrading. Look for:
- **Breaking changes** — may require code changes
- **Deprecated APIs** — scheduled for removal
- **New features** — may offer better patterns

### Step 2: Update Package.swift

```swift
// In your Package.swift
dependencies: [
    .package(url: "https://github.com/YOUR_ORG/Colony.git", from: "NEW_VERSION"),
]
```

Then:
```bash
swift package update
```

### Step 3: Run Tests

```bash
swift test
```

If tests fail, check the sections below for common upgrade issues.

---

## Upgrading Hive Dependency

Colony pins to a specific Hive revision, not a version tag.

### Current Pin

- **File**: `HIVE_DEPENDENCY.lock`
- **Revision**: `3074a0e24d6ab9db1f454dc072fa5caba1461310`
- **Tag**: `0.1.2`

### How to Update Hive Pin

1. **Update `HIVE_DEPENDENCY.lock`**:
   ```
   HIVE_REVISION=NEW_REVISION_HERE
   ```

2. **Bootstrap the new revision**:
   ```bash
   ./scripts/ci/bootstrap-hive.sh
   ```

3. **Run tests**:
   ```bash
   swift test
   ```

4. **Update CHANGELOG.md**:
   ```markdown
   ### Changed
   - Hive: updated pin from `OLD_REVISION` to `NEW_REVISION`
   ```

---

## Known Issues and Workarounds

### "foundationModelsUnavailable" Error

**Cause**: On-device Apple Foundation Models not available on this device/configuration.

**Solution**: Use `.providerRouting()` with a fallback provider:

```swift
let agent = try await Colony.agent(
    model: .providerRouting([
        .foundationModels(),           // Primary
        .onDevice(configuration: .init())  // Fallback
    ])
)
```

Or use a third-party provider like Ollama:

```swift
let agent = try await Colony.agent(
    model: .providerRouting([
        .foundationModels(),
        .ollama(endpoint: "http://localhost:11434", model: "llama3"),
    ])
)
```

### Swift 6.2 Required

**Cause**: Colony uses Swift 6.2 features.

**Solution**: Ensure you're using Swift 6.2 or later:
```bash
swift --version
# Should show swift-6.2 or later
```

### iOS/macOS 26+ Required

**Cause**: Colony targets iOS 26+ and macOS 26+.

**Solution**: Set your deployment target appropriately in `Package.swift` or Xcode project.

### Platform Availability Errors

If you see errors about platform availability:
- Colony requires iOS 26+ or macOS 26+
- Check your `swift-tools-version` in `Package.swift`
- Check deployment target in your project

---

## Migration: Pre-1.0 API Changes

As Colony approaches 1.0, some APIs have changed. This section documents migration paths.

### ColonyCapabilities → ColonyRuntimeCapabilities

**Changed in**: 0.2.0 (renamed)

```swift
// Old (deprecated)
let capabilities: ColonyCapabilities = [.filesystem, .shell]

// New
let capabilities: ColonyRuntimeCapabilities = [.filesystem, .shell]
```

### Swarm Types Renamed

**Changed in**: 0.2.0 (prefix added)

| Old Name | New Name |
|----------|----------|
| `SwarmToolRegistration` | `ColonySwarmToolRegistration` |
| `SwarmToolBridge` | `ColonySwarmToolBridge` |
| `SwarmMemoryAdapter` | `ColonySwarmMemoryAdapter` |
| `SwarmSubagentAdapter` | `ColonySwarmSubagentAdapter` |

Old names are available as deprecated typealiases but will be removed in a future version.

### Entry Point Changed

**Changed in**: 0.2.0

The `ColonyBootstrap` type is now `package`-internal. Use `Colony.agent()`:

```swift
// Old (no longer works)
let bootstrap = ColonyBootstrap()
let result = try await bootstrap.bootstrap(options: ...)

// New
let agent = try await Colony.agent(model: .foundationModels())
```

### Tool Name Constants

Tool names are now typed constants with dot syntax:

```swift
// Old (string-based)
let toolName = "read_file"

// New (type-safe)
let toolName = ColonyTool.Name.readFile
```

Available constants:
- Planning: `.writeTodos`, `.readTodos`
- Filesystem: `.ls`, `.readFile`, `.writeFile`, `.editFile`, `.glob`, `.grep`
- Shell: `.execute`, `.shellOpen`, `.shellWrite`, `.shellRead`, `.shellClose`
- Git: `.gitStatus`, `.gitDiff`, `.gitCommit`, `.gitBranch`, `.gitPush`, `.gitPreparePR`
- LSP: `.lspSymbols`, `.lspDiagnostics`, `.lspReferences`, `.lspApplyEdit`
- Memory: `.memoryRecall`, `.memoryRemember`
- Scratchbook: `.scratchRead`, `.scratchAdd`, `.scratchUpdate`, `.scratchComplete`, `.scratchPin`, `.scratchUnpin`
- Subagents: `.task`
- Web/Code: `.webSearch`, `.codeSearch`
- MCP: `.mcpListResources`, `.mcpReadResource`
- Plugins: `.pluginListTools`, `.pluginInvoke`
- Patch: `.applyPatch`

---

## Getting Help

If you encounter issues not covered here:

1. Check `CHANGELOG.md` for recent changes
2. Search existing issues on GitHub
3. Open a new issue with:
   - Colony version
   - Hive revision (from `HIVE_DEPENDENCY.lock`)
   - Swift version
   - Platform (iOS/macOS version)
   - Minimal reproduction case
