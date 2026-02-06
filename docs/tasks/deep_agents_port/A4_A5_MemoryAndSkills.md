Prompt:
Implement `AGENTS.md` memory injection and `SKILL.md` skills discovery + progressive disclosure in Colony.

Goal:
Match Deep Agents behavior: memory is loaded at startup and injected into system prompt; skills are discovered from layered sources, parsed for metadata from YAML frontmatter, and only disclosed as metadata until explicitly read via `read_file`.

Task Breakdown:
1. Add configuration for:
   - memory sources (`[ColonyVirtualPath]`)
   - skill sources (`[ColonyVirtualPath]` directories)
2. Implement memory loading via `ColonyFileSystemBackend.read` (missing files are non-fatal) and inject into system prompt.
3. Implement skill discovery:
   - list skill directories under each source
   - read `SKILL.md`
   - parse YAML frontmatter (name/description minimum), “last one wins” overrides across sources
4. Inject skills catalog into system prompt with guidance to `read_file` the relevant `SKILL.md` when needed (progressive disclosure).
5. Add Swift Testing tests for parsing and layering behavior and that system prompt includes memory/skills sections when configured.

Expected Output:
- New config + implementations with deterministic ordering.
- Tests proving behavior.
