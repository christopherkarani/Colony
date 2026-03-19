<div align="center">

# Colony

**Local-first AI agent runtime for Swift**

[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![iOS 26+](https://img.shields.io/badge/iOS-26+-blue.svg)](https://developer.apple.com/ios/)
[![macOS 26+](https://img.shields.io/badge/macOS-26+-blue.svg)](https://developer.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Discord](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fdiscord.com%2Fapi%2Fv10%2Finvites%2FNHgNh7HJ6M%3Fwith_counts%3Dtrue&query=%24.approximate_presence_count&suffix=%20online&logo=discord&label=Discord&color=5865F2)](https://discord.gg/NHgNh7HJ6M)

*Build local-first agents in Swift with guardrails, approval flows, and on-device Foundation Models support.*

[Features](#features) • [Quick Start](#quick-start) • [Architecture](#architecture) • [Examples](#examples) • [Documentation](#documentation)

</div>

---

## Why Colony

Colony is a local-first runtime for AI agents. It is built around on-device execution, explicit tool capabilities, and human approval paths for risky work.

### What stands out

| Feature | Colony | Other Agents |
|---------|--------|--------------|
| **Privacy** | 100% on-device | Cloud-dependent |
| **Latency** | Zero network round-trips | API calls add 100-500ms+ |
| **Cost** | Free forever | Pay-per-use APIs |
| **Offline** | Works without internet | Requires connectivity |
| **Safety** | Capability-gated tools with human approval | Often unrestricted |

---

## Features

### Safety by design
- **Capability-gated tools:** tools are only available when explicitly enabled.
- **Human approval:** approve, reject, or cancel risky tool calls.
- **Isolated subagents:** delegation happens through separate runtime instances.

### On-device defaults
- **Context management:** a 4k token budget with automatic compaction.
- **Summarization:** older context can be offloaded to `/conversation_history`.
- **Large result eviction:** big outputs can be moved to `/large_tool_results`.

### Built-in tool families
```swift
📁 Filesystem    → ls, read_file, write_file, edit_file, glob, grep
📝 Planning      → write_todos, read_todos  
💻 Shell         → execute (sandboxed)
📓 Scratchbook   → scratch_read, scratch_add, scratch_update...
👥 Subagents     → task (isolated delegation)
```

### Profiles

```swift
// Strict 4k budget for on-device Foundation Models
profile: .onDevice4k

// Generous limits for cloud deployments  
profile: .cloud
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Colony Runtime Loop                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   ┌──────────┐    ┌──────────┐    ┌──────────────────┐     │
│   │ preModel │───▶│  model   │───▶│ routeAfterModel  │     │
│   └──────────┘    └──────────┘    └────────┬─────────┘     │
│        ▲                                   │                │
│        │                                   ▼                │
│   ┌────┴────┐    ┌──────────┐    ┌──────────────────┐      │
│   │toolExec │◀───│  tools   │◀───│  (interrupts?)   │      │
│   └─────────┘    └──────────┘    └──────────────────┘      │
│                                                             │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    Module Separation                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   ┌─────────────────┐         ┌─────────────────────────┐   │
│   │   ColonyCore    │◀────────│        Colony           │   │
│   │  (Pure Values)  │         │   (Runtime/Orchestration)│   │
│   │                 │         │                         │   │
│   │ • Capabilities  │         │ • Agent Graph           │   │
│   │ • Configuration │         │ • Foundation Models     │   │
│   │ • Tool Contracts│         │ • Subagent Registry     │   │
│   │ • Scratchbook   │         │ • Run Control           │   │
│   └─────────────────┘         └─────────────────────────┘   │
│                                                             │
│              Built on HiveCore (../hive)                     │
└─────────────────────────────────────────────────────────────┘
```

---

## 🚀 Quick Start

### Prerequisites

- Swift 6.2
- iOS 26+ or macOS 26+
- [Hive](https://github.com/christopherkarani/hive) at `../hive`

### Installation

```bash
# Clone with Hive dependency
git clone https://github.com/christopherkarani/Colony.git
cd Colony
# Ensure ../hive exists (git clone https://github.com/christopherkarani/hive.git ../hive)

# Build & Test
swift package resolve
swift test
```

### Your First Agent

```swift
import Colony

@main
struct MyFirstAgent {
    static func main() async throws {
        // Check if on-device Foundation Models are available
        guard ColonyFoundationModelsClient.isAvailable else {
            print("Foundation Models not available on this device")
            return
        }

        // Create a runtime with on-device 4k profile
        let factory = ColonyAgentFactory()
        let runtime = try factory.makeRuntime(
            profile: .onDevice4k,
            modelName: "test-model",
            model: AnyHiveModelClient(ColonyFoundationModelsClient())
        )

        // Start the agent
        let handle = await runtime.runControl.start(
            .init(input: "List all Swift files in this project and summarize what they do.")
        )
        
        // Get the result
        let outcome = try await handle.outcome.value
        print(outcome)
    }
}
```

---

## 🎮 Examples

### Human-in-the-Loop Approval

```swift
import Colony

let factory = ColonyAgentFactory()
let runtime = try factory.makeRuntime(
    profile: .onDevice4k,
    modelName: "test-model",
    model: AnyHiveModelClient(ColonyFoundationModelsClient()),
    configure: { config in
        // Require approval for all tool calls
        config.toolApprovalPolicy = .always
    }
)

let handle = await runtime.runControl.start(
    .init(input: "Create a deployment checklist at /deploy.md")
)
let outcome = try await handle.outcome.value

// Handle approval interrupt
if case let .interrupted(interruption) = outcome,
   case let .toolApprovalRequired(toolCalls) = interruption.interrupt.payload {
    
    print("🔐 Approve these tools?", toolCalls.map(\.name))
    
    // Approve, reject, or cancel
    let resumed = await runtime.runControl.resume(
        .init(
            interruptID: interruption.interrupt.id,
            decision: .approved  // or .rejected / .cancelled
        )
    )
    
    let finalOutcome = try await resumed.outcome.value
    print(finalOutcome)
}
```

### Custom Capabilities

```swift
let runtime = try factory.makeRuntime(
    profile: .onDevice4k,
    modelName: "test-model",
    model: model,
    filesystem: myFileSystem,  // Enable filesystem tools
    shell: myShellBackend,     // Enable shell execution
    subagents: myRegistry,     // Enable subagent delegation
    configure: { config in
        // Customize capabilities
        config.capabilities = [.planning, .filesystem, .scratchbook]
        
        // Fine-tune approval policy
        config.toolApprovalPolicy = .allowList([
            "ls", "read_file", "scratch_read", "scratch_add"
        ])
    }
)
```

### Using the Scratchbook

The Scratchbook is Colony's persistent memory system for tracking state across context windows:

```swift
// The agent can automatically:
// - Add notes: "Found 3 critical bugs in Auth.swift"
// - Track todos: "Fix race condition in NetworkManager"
// - Monitor tasks: "Refactoring Database layer (45% complete)"

// All items are persisted and survive context compaction
// Pinned items always stay visible in the context window
```

---

## 🧪 Proven Behaviors (100% Test Coverage)

Every major feature is backed by comprehensive tests:

| Behavior | Test Location |
|----------|--------------|
| Tool approval interrupts + resume | `ColonyAgentTests.swift`, `ColonyRunControlTests.swift` |
| 4k token budget enforcement | `ColonyContextBudgetTests.swift` |
| History summarization + offload | `ColonySummarizationTests.swift` |
| Large tool result eviction | `ColonyToolResultEvictionTests.swift` |
| Scratchbook persistence | `ColonyScratchbookCoreAndStorageTests.swift` |
| Isolated subagent execution | `DefaultSubagentRegistryTests.swift` |

```bash
# Run all tests
swift test

# Run specific test
swift test --filter ColonyContextBudgetTests
```

---

## 📚 Documentation

- [CLAUDE.md](CLAUDE.md) — Detailed architecture and development guide
- [API Documentation](https://christopherkarani.github.io/Colony) *(coming soon)*
- [Example Projects](Sources/ColonyResearchAssistantExample) — Research Assistant CLI

---

## 🔧 Troubleshooting

| Issue | Solution |
|-------|----------|
| `swift package resolve` fails | Verify `../hive/Package.swift` exists |
| `foundationModelsUnavailable` | On-device models require iOS 26+/macOS 26+ |
| Missing tools in prompts | Check capability + backend wiring |
| Build errors | Ensure Swift 6.2 toolchain |

---

## 🗺️ Roadmap

- [ ] SwiftPM package distribution (remove local `../hive` dependency)
- [ ] visionOS support
- [ ] Additional model provider integrations
- [ ] Visual debugging tools
- [ ] More built-in tool families

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

Please ensure your code follows the existing style and includes tests for new functionality.

---

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## ⭐ Star History

If you find Colony useful, please consider giving it a star! It helps others discover the project and motivates continued development.

[![Star History Chart](https://api.star-history.com/svg?repos=christopherkarani/Colony&type=Date)](https://star-history.com/#christopherkarani/Colony&Date)

---

<div align="center">

**Built with ❤️ for the Swift AI community**

[⬆ Back to Top](#-colony)

</div>
