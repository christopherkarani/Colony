# Colony API Quality Improvement Plan: 78 → 95

**Status**: DRAFT - Awaiting Review  
**Breaking Changes**: YES - v0.x acceptable  
**Target**: Swift 6.2, iOS 26+ / macOS 26+

---

## Executive Summary

Colony's public API scores **78/100** with strong fundamentals (protocol-oriented design, type-safe IDs, progressive disclosure) but suffers from access control inconsistencies, awkward async patterns, deprecated alias bloat, and leaking abstractions. With breaking changes allowed, we can achieve **95/100**.

---

## Current Score Breakdown

| Dimension | Score | Max | Issues |
|-----------|-------|-----|--------|
| API Design | 20 | 25 | Protocol-oriented good, but `ColonyModel.Storage` leaks existentials |
| Ergonomics | 18 | 25 | 3-tier config excellent, but `Task<Outcome, Error>` awkward |
| Swift 6 Concurrency | 15 | 20 | Sendable correct, Task pattern unusual |
| Generic Design | 12 | 15 | `ColonyID<Domain>` elegant, limited primary associated type support |
| Error Handling | 13 | 15 | Typed errors good, some internals not exposed |
| Documentation | 0 | - | Missing comprehensive docs on complex types |
| **TOTAL** | **78** | **100** | |

---

## Phase 1: Kill All 150+ Deprecated Type Aliases

**File**: `Sources/ColonyCore/ColonyDeprecations.swift`

**Action**: Delete entire file. All aliases are unused.

**Verification**:
```bash
grep -r "ColonyRunOptions\|ColonyToolApprovalPolicy\|ColonyCapabilities" Tests/ Sources/
# Returns: 0 matches
```

**Breaking**: Yes - any external code using deprecated names will break.

**Impact**: +2 points

---

## Phase 2: Redesign `ColonyRun.Handle` Async Pattern

**Files**: 
- `Sources/ColonyCore/ColonyRuntimeSurface.swift` (Handle definition)
- `Sources/Colony/ColonyRuntime.swift` (makePublicHandle)

**Current** (20+ usages in tests):
```swift
let outcome = try await handle.outcome.value
```

**Redesign**:
```swift
public struct Handle: Sendable {
    public let runID: ColonyRunID
    public let attemptID: ColonyAttemptID
    
    /// The outcome of the agent run.
    /// Use `try await handle.outcome` directly.
    public var outcome: Outcome { get async throws }
    
    // Task removed - wrap if cancellation genuinely needed
}
```

**Migration**:
```swift
// Before
try await handle.outcome.value

// After
try await handle.outcome
```

**Breaking**: Yes - `.value` removed.

**Impact**: +3 points

---

## Phase 3: Make Entry Points Truly Public

**Files**:
- `Sources/Colony/ColonyBootstrap.swift`
- `Sources/Colony/ColonyAgentFactory.swift`
- `Sources/Colony/ColonyRuntimeCreationOptions.swift`

**Changes**:

```swift
// ColonyBootstrap.swift
public struct ColonyBootstrap: Sendable {
    public init() {}
    public func makeRuntime(options: ColonyRuntimeCreationOptions) async throws -> ColonyRuntime
    public func bootstrap(options: ColonyBootstrapOptions) async throws -> ColonyBootstrapResult
}

// ColonyAgentFactory.swift
public struct ColonyAgentFactory: Sendable {
    public init() {}
    public static func configuration(profile: ColonyProfile, modelName: ColonyModelName) -> ColonyConfiguration
    public static func configuration(profile: ColonyProfile, modelName: ColonyModelName, lane: ColonyLane) -> ColonyConfiguration
    public static func routeLane(forIntent intent: String) -> ColonyLane
    public func makeRuntime(_ options: ColonyRuntimeCreationOptions) throws -> ColonyRuntime
}

// ColonyRuntimeCreationOptions
public struct ColonyRuntimeCreationOptions: Sendable {
    public var profile: ColonyProfile
    public var threadID: ColonyThreadID
    public var modelName: ColonyModelName
    // ... all fields public
}
```

**Breaking**: No - exposes previously hidden APIs.

**Impact**: +3 points

---

## Phase 4: Hide Existentials in `ColonyModel`

**File**: `Sources/Colony/ColonyPublicAPI.swift`

**Current** (leaks Hive types):
```swift
public init(client: some ColonyModelClient, ...)
public init(router: some ColonyModelRouter, ...)
```

**Redesign**:
```swift
public enum ColonyModel: Sendable {
    case foundationModels(config: FoundationModelConfiguration)
    case onDevice(config: OnDeviceConfiguration)
    case multiProvider(providers: [ColonyProvider], policy: RoutingPolicy)
    
    internal var storage: Storage { get }
}

public struct OnDeviceConfiguration: Sendable {
    public var fallback: ColonyModelClient
    public var fallbackCapabilities: ColonyModelCapabilities
    public var policy: ColonyModel.OnDevicePolicy
    public var foundationConfig: ColonyModel.FoundationModelConfiguration
    
    public init(
        fallback: ColonyModelClient,
        fallbackCapabilities: ColonyModelCapabilities = [],
        policy: ColonyModel.OnDevicePolicy = .init(),
        foundationConfig: ColonyModel.FoundationModelConfiguration = .init()
    )
}

// Factory methods remain, hide internal protocols
public extension ColonyModel {
    static func foundationModels(
        configuration: FoundationModelConfiguration = .init()
    ) -> ColonyModel
    
    static func onDevice(
        fallback: ColonyModelClient,
        fallbackCapabilities: ColonyModelCapabilities = [],
        policy: OnDevicePolicy = .init(),
        foundationModels: FoundationModelConfiguration = .init()
    ) -> ColonyModel
    
    static func providerRouting(
        providers: [Provider],
        policy: RoutingPolicy = .init()
    ) -> ColonyModel
}
```

**Breaking**: Yes - `ColonyModel(client:)`, `ColonyModel(router:)` removed.

**Impact**: +3 points

---

## Phase 5: Add Convenience APIs

**File**: `Sources/Colony/ColonyRuntime.swift`

```swift
extension ColonyRuntime {
    /// Send message and wait for completion, returning only the final answer.
    /// Shorthand for `try await send(text).outcome` when you only need the answer.
    public func complete(
        _ text: String,
        optionsOverride: ColonyRun.Options? = nil
    ) async throws -> String {
        let handle = await sendUserMessage(text, optionsOverride: optionsOverride)
        let outcome = try await handle.outcome
        guard let answer = outcome.finalAnswer else {
            throw ColonyRuntimeError.noFinalAnswer
        }
        return answer
    }
}

extension ColonyRun.Outcome {
    /// True if the agent completed successfully.
    public var isFinished: Bool {
        if case .finished = self { return true }
        return false
    }
    
    /// True if the agent was interrupted (e.g., tool approval required).
    public var isInterrupted: Bool {
        if case .interrupted = self { return true }
        return false
    }
    
    /// The final answer string if available.
    public var finalAnswer: String? {
        switch self {
        case .finished(let transcript, _): return transcript.finalAnswer
        case .cancelled(let transcript, _): return transcript.finalAnswer
        case .outOfSteps(let transcript, _, _): return transcript.finalAnswer
        case .interrupted: return nil
        }
    }
}

public enum ColonyRuntimeError: Error, Sendable {
    case noFinalAnswer
    case interrupted(ColonyRun.Interruption)
}
```

**Breaking**: No - additive.

**Impact**: +2 points

---

## Phase 6: Full Documentation Pass

**Files**: All public API files

Add comprehensive doc comments to:
- `ColonyRuntime` - lifecycle, threading model
- `ColonyRun.Handle` - Task vs outcome, cancellation
- `ColonyRun.Outcome` - each case with Swift code example
- `ColonyModel` - when to use which factory method
- `ColonyToolApproval.Decision` - perTool usage pattern
- All backend protocols

**Example**:
```swift
/// The final outcome of a Colony agent run.
///
/// ## Interruption Handling
///
/// When the agent requires human approval for tool execution,
/// the outcome is `.interrupted`. Use `ColonyRuntime.resumeToolApproval()`
/// to continue:
///
/// ```swift
/// if case .interrupted(let interruption) = outcome {
///     let resumed = await runtime.resumeToolApproval(
///         interruptID: interruption.interruptID,
///         decision: .approved
///     )
///     // ...
/// }
/// ```
public enum ColonyRun.Outcome: Sendable, Equatable {
    // ...
}
```

**Breaking**: No - docs only.

**Impact**: +2 points

---

## Phase 7: Add `ColonyThreadID.generate()` Helper

**File**: `Sources/ColonyCore/ColonyID.swift`

```swift
extension ColonyThreadID {
    /// Generate a new unique thread ID with auto-prefix.
    public static func generate() -> ColonyThreadID {
        ColonyThreadID("colony:" + UUID().uuidString)
    }
}
```

**Breaking**: No - additive.

**Impact**: +1 point

---

## Revised Scoring

| Dimension | Before | Change | After |
|-----------|--------|--------|-------|
| API Design | 20 | +2 | 22 |
| Ergonomics | 18 | +5 | 23 |
| Swift 6 Concurrency | 15 | +1 | 16 |
| Generic Design | 12 | +1 | 13 |
| Error Handling | 13 | +1 | 14 |
| Documentation | 0 | +7 | 7 |
| **TOTAL** | **78** | **+17** | **95** |

---

## Breaking Changes Summary

| Change | Migration Effort |
|--------|-----------------|
| Delete `ColonyDeprecations.swift` | Use canonical names |
| `handle.outcome.value` → `handle.outcome` | Simple rename |
| `ColonyModel(client:)` removed | Use factory methods |
| `ColonyModel(router:)` removed | Use `.providerRouting()` |
| `ColonyBootstrap` now public | Import if needed |

---

## Implementation Order

1. **Phase 1** - Kill aliases (5 min, no logic)
2. **Phase 7** - ThreadID helper (2 min)
3. **Phase 2** - Handle async (15 min, update tests)
4. **Phase 3** - Make public (10 min)
5. **Phase 5** - Convenience APIs (15 min)
6. **Phase 6** - Documentation (30 min, can parallelize)
7. **Phase 4** - Existential cleanup (30 min, most complex)

**Total Estimated**: ~2 hours

---

## Files to Modify

```
Sources/ColonyCore/
  ColonyDeprecations.swift          [DELETE]
  ColonyRuntimeSurface.swift        [Handle redesign]
  ColonyID.swift                    [ThreadID helper]
  
Sources/Colony/
  ColonyPublicAPI.swift             [Storage enum redesign]
  ColonyRuntime.swift               [convenience APIs]
  ColonyBootstrap.swift             [public access]
  ColonyAgentFactory.swift           [public access]
  ColonyRuntimeCreationOptions.swift [public access]
```

---

## Verification Checklist

After implementation:
- [ ] `swift build` succeeds
- [ ] All tests pass with new syntax
- [ ] No `ColonyRunOptions`, `ColonyToolApprovalPolicy`, etc. remain
- [ ] `try await handle.outcome` works in all tests
- [ ] `ColonyModel.foundationModels()` compiles
- [ ] Documentation builds without warnings
