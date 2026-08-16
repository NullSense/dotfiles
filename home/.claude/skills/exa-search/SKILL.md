---
name: exa-search
description: >
  Find things on the web: GitHub repos, Rust crates, docs, papers, code examples.
  The raw search tool — use when you need to look something up, find a crate, read
  a project's docs, or get code examples. Wraps Exa neural search with domain presets
  for Rust ecosystem, RAG tools, and academic sources. Use INSTEAD of WebSearch for
  higher quality results. NOT for: library API docs you already know the name of
  (use Context7), internal knowledge (use sift-skill), or architecture decisions
  that need structured comparison (use platform-research).
---

# Exa — Web & Code Search

Neural search across the web with domain filtering, code context, and content extraction.

## Tool Selection

Pick the right Exa tool for the job:

| Need | Tool | Notes |
|------|------|-------|
| Code examples, implementations, patterns | `get_code_context_exa` | Always include language name ("Rust", "TypeScript") |
| Filtered search (by domain, date, category) | `web_search_advanced_exa` | Use `includeDomains` for focused results |
| General web search | `web_search_exa` | Broadest, least precise |
| Extract full content from a known URL | `crawling_exa` | When you already have the URL |

**Default to `get_code_context_exa` for code, `web_search_advanced_exa` for everything else.**
Only fall back to `web_search_exa` when you need maximum breadth.

## Search Hierarchy (When NOT to Use Exa)

1. **Context7** — library API docs, usage examples, versioned references. Always try first for known libraries.
2. **Exa** — ecosystem discovery, GitHub repos, crate comparison, competing tools, code patterns, academic papers.
3. **Sift** — internal organizational knowledge, past decisions, meeting notes.
4. **WebSearch/WebFetch** — fallback for general queries, or when you need a specific URL.

## Query Patterns

### Crate Discovery
```
web_search_advanced_exa:
  query: "Rust async retry backoff middleware tower"
  includeDomains: ["crates.io", "lib.rs", "docs.rs", "github.com"]
  numResults: 5
  contents: { highlights: { maxCharacters: 2000 } }
```

### GitHub Project Research
```
get_code_context_exa:
  query: "Rust qdrant batch upsert with payload filtering"
  numResults: 5
```

### Competing RAG Tool Analysis
```
web_search_advanced_exa:
  query: "open source RAG pipeline vector search ingestion"
  includeDomains: ["github.com", "docs.airweave.ai", "docs.vectara.com", "www.pinecone.io", "docs.llamaindex.ai"]
  numResults: 10
  contents: { highlights: { maxCharacters: 2000 } }
```

### Academic Papers
```
web_search_advanced_exa:
  query: "hybrid sparse dense retrieval reranking evaluation"
  category: "research paper"
  numResults: 5
  contents: { highlights: { maxCharacters: 3000 } }
```

## Defaults

- **Content**: Always prefer `highlights` over full `text` — 50-75% fewer tokens, better relevance. Only use `text` when you need contiguous content (full READMEs, complete code files).
- **`maxCharacters`**: 2000 for highlights (standard), 3000 for research papers, 10000 for full text extraction.
- **`numResults`**: 3-5 for focused queries, 10 for broad exploration.
- **Search type**: `auto` for most queries. Use `deep` only for thorough research where latency is acceptable.
- **Always include "Rust"** in code queries to avoid JavaScript/Python noise.

## Domain Presets

Use these `includeDomains` sets for common searches:

| Preset | Domains |
|--------|---------|
| Rust ecosystem | `github.com`, `docs.rs`, `crates.io`, `lib.rs`, `users.rust-lang.org` |
| RAG/search tools | `github.com`, `docs.airweave.ai`, `docs.vectara.com`, `www.pinecone.io`, `docs.llamaindex.ai`, `qdrant.tech` |
| Academic | `arxiv.org`, `openreview.net`, `paperswithcode.com` |
| General docs | `github.com`, `stackoverflow.com`, `dev.to` |

## Anti-Patterns

- Don't use Exa for library docs that Context7 covers — Context7 is faster and versioned.
- Don't fetch full `text` by default — highlights are almost always sufficient and save tokens.
- Don't search without domain filtering when you know the domain — unfiltered searches return noise.
- Don't use a single query and give up — reformulate 2-3 times with different vocabulary.
