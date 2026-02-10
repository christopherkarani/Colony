#!/usr/bin/env swift
// Diagnostic: mimic ColonyFoundationModelsClient behavior with instructions + streaming

#if canImport(FoundationModels)
import FoundationModels
import Foundation

if #available(macOS 26.0, *) {
    print("=== Test 1: Basic respond (no instructions) ===")
    do {
        let session1 = LanguageModelSession(model: .default, tools: [])
        let r1 = try await session1.respond(to: "Say hello.")
        print("OK: \(r1.content)")
    } catch {
        print("FAIL: \(type(of: error)) — \(error)")
    }

    print("\n=== Test 2: With instructions (like Colony system prompt) ===")
    let instructions = """
    Research assistant mode:
    - Start by writing and maintaining a concise TODO plan.
    - Gather evidence with filesystem tools before concluding.
    - Cite concrete evidence with /path:line references.

    Tool calling:
    - Emit tool calls as JSON wrapped in tags:
      <tool_call>{"name":"tool_name","arguments":{...}}</tool_call>
    - Emit one block per call.
    - If you emit tool calls, do not emit other assistant text.

    Available tools:
    - glob
      args: pattern*
    - grep
      args: pattern*, path
    - ls
      args: path*
    - read_file
      args: file_path*
    - read_todos
    - write_todos
      args: todos*
    - task
      args: prompt*, subagent_type*
    """
    do {
        let session2 = LanguageModelSession(model: .default, tools: [], instructions: { instructions })
        let r2 = try await session2.respond(to: "User:\nWhat files are in the root directory?")
        print("OK: \(r2.content.prefix(200))")
    } catch {
        print("FAIL: \(type(of: error)) — \(error)")
    }

    print("\n=== Test 3: Streaming (like Colony client) ===")
    do {
        let session3 = LanguageModelSession(model: .default, tools: [], instructions: { instructions })
        let stream = session3.streamResponse(to: "User:\nWhat files are in the root directory?")
        var lastContent = ""
        for try await snapshot in stream {
            lastContent = snapshot.content
        }
        print("OK (streamed): \(lastContent.prefix(200))")
    } catch {
        print("FAIL: \(type(of: error)) — \(error)")
    }

    print("\n=== Test 4: Multi-turn (like Colony conversation) ===")
    do {
        let session4 = LanguageModelSession(model: .default, tools: [], instructions: { instructions })
        // First turn
        let r4a = try await session4.respond(to: "User:\nList files in the root directory.")
        print("Turn 1 OK: \(r4a.content.prefix(100))")
        // Second turn (simulating tool result + follow-up)
        let r4b = try await session4.respond(to: "Tool(ls) [id: call-1]:\nREADME.md\nPackage.swift\nSources/\n\nUser:\nWhat is in README.md?")
        print("Turn 2 OK: \(r4b.content.prefix(100))")
    } catch {
        print("FAIL: \(type(of: error)) — \(error)")
    }

    print("\nAll tests complete.")
} else {
    print("macOS 26.0+ not available")
}
#else
print("FoundationModels: NOT importable")
#endif
