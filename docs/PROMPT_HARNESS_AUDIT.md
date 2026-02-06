# Colony Prompt Harness Audit

## Scope
This document inventories prompt-bearing strings and templates used by Colony runtime, plus prompt fixtures in Colony tests.

Included:
- `Sources/ColonyCore/ColonyPrompts.swift`
- `Sources/Colony/ColonyAgent.swift`
- `Sources/Colony/ColonyDefaultSubagentRegistry.swift`
- `Sources/Colony/ColonyFoundationModelsClient.swift`
- `Sources/ColonyCore/ColonyScratchbook.swift`
- `Sources/ColonyCore/ColonyBuiltInToolDefinitions.swift`
- `Tests/ColonyTests/*` prompt fixtures

Excluded from runtime inventory:
- `deepagents-master-2/**` (vendored reference code, not Colony runtime)

## Canonical Harness Entry Points
1. `Sources/Colony/ColonyAgent.swift` (system prompt assembly, budgeting, request creation)
2. `Sources/ColonyCore/ColonyPrompts.swift` (base system prompt + section composition)
3. `Sources/Colony/ColonyFoundationModelsClient.swift` (Foundation Models prompt/instructions mapping)
4. `Sources/Colony/ColonyDefaultSubagentRegistry.swift` (subagent delegated prompt assembly)

## Prompt Composition Model
`ColonyAgent` composes the system prompt from:
1. `ColonyPrompts.baseSystemPrompt`
2. optional `additionalSystemPrompt`
3. optional `Memory:` section
4. optional `Skills:` section
5. optional `Scratchbook:` section
6. optional `Tools:` section

Then request messages are sent to the model adapter; on Foundation Models, role lines and tool-calling protocol text are rendered into an instruction block + prompt block.

## Runtime Prompt Inventory

### 1) Base System Prompt
File: `Sources/ColonyCore/ColonyPrompts.swift:4`

```text
In order to complete the objective that the user asks of you, you have access to a number of standard tools.

Follow these rules:
- Be concise and direct unless the user asks for detail.
- Prefer using tools over guessing.
- When operating on files, read before editing, and avoid unnecessary changes.
- Skills are metadata-only; read the referenced SKILL.md file when needed.
- If memory files are provided, update them via edit_file only when asked (never store secrets).
```

Section labels in `Sources/ColonyCore/ColonyPrompts.swift`:
- `Memory:\n` (`:56`)
- `Skills:\n` (`:60`)
- `Scratchbook:\n` (`:64`)
- `Tools:\n` (`:72`)
- Tool list line format: `- <tool.name>: <tool.description>`

### 2) ColonyAgent Prompt/Message Templates
File: `Sources/Colony/ColonyAgent.swift`

Compactor delegated prompt (`:714`):
```text
Conversation history was offloaded to: \(historyPath.rawValue)

Update the Scratchbook at: \(scratchbookPath.rawValue)
- Add or update a concise summary note that references the offloaded history path.
- Add at least one concrete next action as a todo/task item.
- Keep updates compact and on-device friendly.
```

Summary notice system message (`:737`):
```text
Note: conversation has been summarized. Full prior history is available at \(historyPath.rawValue).
```

Scratchbook fallback items:
- Title (`:766`): `History offloaded: \(historyPath.rawValue)`
- Body (`:767`): `Conversation history was offloaded to \(historyPath.rawValue).`
- Next-action title (`:777`): `Next actions (see \(historyPath.rawValue))`
- Next-action body (`:778`):
```text
Next actions:
- Next action: Review \(historyPath.rawValue)
- Next action: Update Scratchbook tasks/todos for the current objective
```

Large tool result eviction message (`:947`):
```text
Tool result too large (tool_call_id: \(toolCall.id)).
Full content was written to \(path.rawValue). Read it with read_file using offset/limit.

Preview:
\(preview)
```

Tool execution control messages:
- `Tool execution rejected by user.` (`:499`)
- `Tool call \(call.name) with id \(call.id) was cancelled - tool execution was rejected by the user.` (`:506`)
- `Tool call \(call.name) with id \(call.id) was cancelled - another message came in before it could be completed.` (`:656`)

Budget truncation notices injected into prompt context:
- `[Memory truncated to fit context budget]` (`:824`)
- `[Skills list truncated to fit context budget]` (`:868`)

Prompt-visible tool response strings:
- `Error: Tool registry missing.` (`:1242`)
- `Error: \(error)` (`:1246`)
- `Error: Scratchbook capability not enabled.` (`:1272`, `:1289`, `:1332`, `:1377`, `:1421`, `:1451`)
- `Error: Filesystem not configured.` (`:1275`, `:1292`, `:1335`, `:1380`, `:1424`, `:1454`, `:1476`, `:1488`, `:1503`, `:1512`, `:1530`, `:1538`)
- `Error: Scratchbook item not found: \(args.id)` (`:1346`, `:1391`, `:1435`)
- `Error: Shell backend not configured.` (`:1547`)
- `Error: Subagent registry not configured.` (`:1573`)
- `OK: added \(itemID)` (`:1328`)
- `OK: updated \(args.id)` (`:1373`)
- `OK: completed \(args.id)` (`:1417`)
- `OK: pinned \(args.id)` (`:1447`)
- `OK: unpinned \(args.id)` (`:1472`)
- `OK: wrote \(path.rawValue)` (`:1508`)
- `OK: edited \(path.rawValue) (\(occurrences) replacement(s))` (`:1524`)
- Execute output rendering uses:
- `exit_code: \(result.exitCode)` (`:1773`)
- `stdout:\n\(result.stdout)` (`:1775`)
- `stderr:\n\(result.stderr)` (`:1778`)
- `warning: output truncated` (`:1781`)

Prompt-visible scratch/todo render strings:
- `(No todos)` (`:1594`)
- `[\(todo.status.rawValue)] \(todo.id): \(todo.title)` (`:1596`)
- `(Scratchbook view disabled)` (`:1607`)
- `(Scratchbook empty)` (`:1610`)
- `PINNED ` (`:1663`)
- `\(prefix)[\(item.kind.rawValue)/\(item.status.rawValue)] \(item.id): \(title)` (`:1665`)
- ` — ` (`:1669`)
- `#\(tag)` (`:1675`)

### 3) Subagent Prompt Templates
File: `Sources/Colony/ColonyDefaultSubagentRegistry.swift`

Compactor-mode additional system prompt (`:93`):
```text
Compactor mode:
- Produce a compact, structured summary and concrete next actions.
- If the prompt references an offloaded history file, treat it as the source of truth.
- Prefer writing updates into the Scratchbook (via Scratchbook tools) rather than returning long prose.
- Do not call the `task` tool; recursive subagents are disabled.
```

Subagent descriptor strings (surface in task-tool available subagents text):
- `General-purpose helper.` (`:66`)
- `Compacts offloaded history into a dense summary + next actions.` (`:70`)

Delegated prompt augmentation templates:
- `Structured context:` (`:163`)
- `objective: \(objective)` (`:166`)
- `constraints:` (`:169`)
- `(none)` (`:171`)
- `- \(constraint)` (`:173`)
- `acceptance_criteria:` (`:176`)
- `(none)` (`:178`)
- `- \(criterion)` (`:180`)
- `notes:` (`:183`)
- `(none)` (`:185`)
- `- \(note)` (`:187`)
- `File context snippets:` (`:196`)
- `path: \(ref.path.rawValue)` (`:203`)
- `requested_offset: \(ref.offset ?? 0)` (`:204`)
- `requested_limit: \(ref.limit ?? 100)` (`:205`)
- `excerpt: (filesystem not configured)` (`:209`)
- `excerpt:\n` + line-numbered excerpt (`:216`)
- `excerpt_error: \(error)` (`:218`)

### 4) Foundation Models Prompt/Instruction Templates
File: `Sources/Colony/ColonyFoundationModelsClient.swift`

Role rendering:
- `User:\n\(message.content)` (`:133`)
- `Assistant:\n\(assistantBlock)` (`:145`)
- `Tool(\(toolName)) [id: \(callID)]:\n\(message.content)` (`:150`)

Tool call protocol tags:
- `<tool_call>` (`:75`)
- `</tool_call>` (`:76`)

Tool-calling instruction block (`:185`):
```text
Tool calling:
- If you need to call a tool, emit one or more tool call blocks.
- A tool call block MUST be valid JSON wrapped with tags, with no surrounding text:
  <tool_call>{"name":"tool_name","arguments":{...}}</tool_call>
- If you emit any tool call blocks, do NOT include other assistant text outside tool calls.

Available tools:
\(toolList)
```

Rendered call markup format (`:198`):
```text
<tool_call>{"id":"\(jsonEscaped(call.id))","name":"\(jsonEscaped(call.name))","arguments":\(call.argumentsJSON)}</tool_call>
```

### 5) Scratchbook View Templates
File: `Sources/ColonyCore/ColonyScratchbook.swift`

- `(Scratchbook view disabled)` (`:123`)
- `(Scratchbook empty)` (`:126`)
- `PINNED ` (`:256`)
- `#\(tag)` (`:262`)
- `phase=\(normalizeSingleLine(phase))` (`:268`)
- `progress=\(percent)%` (`:272`)
- `\(prefix)[\(item.kind.rawValue)/\(item.status.rawValue)] \(item.id): \(title)` (`:276`)
- `(" + extras.joined(separator: ", ") + ")` suffix format (`:278`)
- ` — ` (`:283`)

### 6) Tool Metadata Included in Prompt Surface
File: `Sources/ColonyCore/ColonyBuiltInToolDefinitions.swift`

These descriptions are injected when `Tools:` is enabled and are also used in model-facing tool metadata.

- `ls` (`:7`): `List files in a directory (non-recursive).`
- `read_file` (`:15`): `Read a file with line numbers. Use offset/limit for pagination.`
- `write_file` (`:23`): `Create a new file. Fails if the file already exists.`
- `edit_file` (`:31`): `Replace an exact string in a file.`
- `glob` (`:39`): `Find files matching a glob pattern.`
- `grep` (`:47`): `Search for a literal string across files. Optionally filter files with glob.`
- `write_todos` (`:55`): `Replace the current todo list with the provided items.`
- `read_todos` (`:63`): `Read the current todo list.`
- `execute` (`:71`): `Execute a shell command using the configured sandbox backend.`
- `scratch_read` (`:79`): `Read the Scratchbook (compact view).`
- `scratch_add` (`:87`): `Add a Scratchbook item (note/todo/task).`
- `scratch_update` (`:95`): `Update fields on an existing Scratchbook item by id.`
- `scratch_complete` (`:103`): `Mark a Scratchbook item done by id.`
- `scratch_pin` (`:111`): `Pin a Scratchbook item by id.`
- `scratch_unpin` (`:119`): `Unpin a Scratchbook item by id.`
- `task` (`:138`): `Launch an isolated subagent task. Available subagents: \(available)`

JSON parameter schemas for each tool are prompt-relevant and defined adjacent to each description at:
- `ls` (`:9`)
- `read_file` (`:17`)
- `write_file` (`:25`)
- `edit_file` (`:33`)
- `glob` (`:41`)
- `grep` (`:49`)
- `write_todos` (`:57`)
- `read_todos` (`:65`)
- `execute` (`:73`)
- `scratch_read` (`:81`)
- `scratch_add` (`:89`)
- `scratch_update` (`:97`)
- `scratch_complete` (`:105`)
- `scratch_pin` (`:113`)
- `scratch_unpin` (`:121`)
- `task` (`:139`)

### 7) Factory-Provided Additional Prompt Defaults
File: `Sources/Colony/ColonyAgentFactory.swift`

- On-device profile default (`:88`):
`On-device runtime: keep context tight (~4k). Prefer writing large outputs to files and referencing them.`

## Dynamic Injection Points (Runtime)
1. `Sources/Colony/ColonyAgent.swift:221-255`
   - Loads memory (`memorySources`) and injects under `Memory:`
   - Loads skill catalog metadata (`skillSources`) and injects under `Skills:`
   - Loads scratchbook view and injects under `Scratchbook:`
   - Injects tools list under `Tools:` if enabled
2. `Sources/ColonyCore/ColonyPrompts.swift:51-73`
   - Appends `additional`, `memory`, `skills`, `scratchbook`, and `availableTools` only when non-empty
3. `Sources/Colony/ColonyDefaultSubagentRegistry.swift:91-100`
   - Adds compactor-specific additional system prompt
4. `Sources/Colony/ColonyFoundationModelsClient.swift:154-166`
   - Appends tool instructions and any adapter-level `additionalInstructions`
5. `Sources/Colony/ColonyDefaultSubagentRegistry.swift:149-159`
   - Builds delegated prompt from base prompt + optional structured context + optional file snippets

## Test Prompt Fixtures (ColonyTests)

### `Tests/ColonyTests/DefaultSubagentRegistryTests.swift`
- `:46` `{"prompt":"Create /from-subagent.txt with content 'hello'.","subagent_type":"general-purpose"}`
- `:146` `{"prompt":"Should not run.","subagent_type":"general-purpose"}`
- `:372` `Read /big.txt and confirm the first and last line number.`
- `:408` `Draft rollout plan.`
- `:411` `Roll out safely.`
- `:412` `No network access.`
- `:412` `Preserve existing behavior.`
- `:413` `Return three rollout checkpoints.`
- `:414` `Prioritize correctness.`
- `:430` `Structured context:`
- `:431` `objective: Roll out safely.`
- `:432` `constraints:`
- `:433` `acceptance_criteria:`
- `:434` `notes:`
- `:436` `File context snippets:`

### `Tests/ColonyTests/ColonyAgentTests.swift`
- `:64` `Tool execution rejected by user.`
- `:201` `{"prompt":"Collect three iOS benchmark ideas.","subagent_type":"research"}`
- `:244` `{"prompt":"Draft migration approach.","subagent_type":"research",...}`
- `:554` `Collect three iOS benchmark ideas.`
- `:608` `Draft migration approach.`
- `:623` `MEMORY_A: Keep responses concise.`
- `:624` `MEMORY_B: Prefer value types.`
- `:670` skill frontmatter/body fixture including `BODY_SENTINEL_SHOULD_NOT_BE_DISCLOSED`

### `Tests/ColonyTests/ScratchbookPromptInjectionTests.swift`
- Prompt-section assertions around `Scratchbook:` at `:130`, `:175`, `:232`, `:298`
- Tools-section assertion at `:355`, `:356`
- Scratchbook item literals include `Alpha`, `Hello`, `Title-1`, `Title-2`, `Title-3`

## Notable Audit Findings
1. Prompt surface is centralized and reasonably well-factored: `ColonyPrompts` + `ColonyAgent` + adapter/subagent layers.
2. Prompt text exists both in runtime and tests; runtime coverage of injected sections appears intentional.
3. `ColonyAgent.swift` and `ColonyScratchbook.swift` both contain scratchbook view string formatting; monitor for divergence if one implementation changes.

## Optional Reference Inventory (Not Runtime)
Vendored prompt files exist under `deepagents-master-2/**` (for parity/reference work), including:
- `deepagents-master-2/libs/cli/deepagents_cli/default_agent_prompt.md`
- `deepagents-master-2/examples/deep_research/research_agent/prompts.py`

These are not part of Colony runtime harness unless explicitly imported/integrated.
