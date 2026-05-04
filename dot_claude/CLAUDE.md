# Claude Instructions (Global)

## Testing
- Fix bugs → immediately write unit tests (TDD preferred)
- Long-standing bug fixes MUST include regression tests to prevent recurrence

## Documentation
- Always use Context7 for library docs (not web search)
- Prefer narrow topics: "persist middleware" not "state management"
- Use 1000-2000 tokens for focused queries, 5000+ for comprehensive overviews

## Context7 Strategy
- Resolve library ID first with `resolve-library-id`
- Then fetch docs with narrow, specific topic
- Reuse resolved library IDs within same session
- Always check version compatibility with project dependencies

## Structured memory directory

Cross-project knowledge lives in `~/.claude/memory/`:
- `general.md` — cross-project conventions (style, defaults, workflow preferences)
- `tools/*.md` — per-tool learnings (git.md, docker.md, cargo.md, pnpm.md, etc.)
- `domain/*.md` — per-domain patterns (rust.md, typescript.md, search.md, etc.)

When you learn a cross-project convention, write it to the appropriate file here
instead of expanding this CLAUDE.md. Keep this file focused on top-level
preferences only — concise indexes age better than sprawling ones.
