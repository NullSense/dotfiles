---
name: searching-knowledge
description: >
  Searches indexed organizational knowledge via MCP tools — code, issues, PRs, chat messages,
  meeting transcripts, docs, research, and memory. Use for cross-domain recall, prior art,
  past decisions, duplicate detection, or any question benefiting from multi-source context.
  Not for: current issue status (use issue tracker API), live database queries, or structured
  field filters (use source-specific tools).
---

# Sift — Knowledge Search

Hybrid semantic search (dense + SPLADE sparse) with reranking across all indexed collections.

## Retrieval Workflow

**Default pattern for every query:**

1. **Reformulate** — translate the user's question into search-optimized terms. Strip conversational fluff, use domain vocabulary that would appear in the actual documents.
2. **Search** — `sift_search` with appropriate collection scope and limit.
3. **Evaluate** — read snippets. Don't blindly pick top score — a 0.70 result may be more relevant than a 0.85.
4. **Expand** — `sift_expand` on the best match. Snippets are ~200 chars; full documents are definitive. Always expand before concluding a result is irrelevant.
5. **Answer** from expanded context, not the snippet.

**Search is cheap.** Each query takes <1 second. Run 3-5 queries with different terms rather than settling for weak results. A bad answer from one query is worse than a great answer from five.

## Query Optimization

The biggest quality lever. Benchmarks show +51% to +257% score improvement from reformulation alone.

**Core technique:** Don't search with the user's exact words. Think about what words the actual document contains.

| User says | Better query | Why |
|-----------|-------------|-----|
| "what's our pricing" | "commission fee percentage take rate" | Docs discuss pricing with domain terms |
| "database stuff" | "table schema migration SQL profiles" | Schema docs use table names |
| "that meeting about strategy" | "action items decided next steps alignment" | Meeting notes capture outcomes |

**If top score < 0.6, reformulate before giving up:**
1. **Rephrase** — different vocabulary ("commission" → "fee structure" → "take rate")
2. **Broaden** — remove specific terms, search more abstractly
3. **Narrow** — add context, try a different collection
4. **Decompose** — split complex questions into 2-3 simpler searches

See [QUERY-PATTERNS.md](QUERY-PATTERNS.md) for detailed reformulation examples with benchmarked scores.

## Score Interpretation

| Score | Meaning | Action |
|-------|---------|--------|
| > 0.85 | Strong match | Expand and answer confidently |
| 0.6–0.85 | Good match | Expand to verify, may need supplementary search |
| 0.4–0.6 | Weak match | Reformulate query, try different collection |
| < 0.4 | Noise | Information likely not indexed — don't use |

## Retrieval Patterns

### Search → Similar → Synthesize
For investigation and "what do we know about X":
1. `sift_search` to find the seed
2. `sift_similar` on the best result to discover connections the query didn't anticipate
3. Synthesize across both result sets

Similar finds items *related to your best answer*, not just matching your query. A search for "pricing decision" finds the decision; similar finds the competitive analysis, the team discussion, and the implementation.

### Multi-Collection Triangulation
For cross-domain questions. Don't search everything at once — scope to 2-3 collections separately:
- Code tells you **how**, issues tell you **why**, chat tells you the **context**
- Scoped searches give ~40% better scores than unscoped global search

### Seed → Recommend → Explore
For research and "show me more like this":
1. Search to find 1-2 good results
2. `sift_recommend` with those IDs as positives
3. Recommendations surface thematically related documents the query missed

### Duplicate Detection
**Before creating issues in any tracker:**
1. Search the issues collection with the title you'd create
2. If score > 0.7 → likely duplicate, link to existing
3. `sift_similar` on the top result for near-matches

### Timeline Reconstruction
For "what happened with X" or decision archaeology:
1. Broad search with high limit
2. Sort results by date mentally
3. Expand key moments (the decision, the incident, the resolution)
4. Construct chronological narrative

## Quick Lookups for Coding Agents

Pre-filtered shortcuts for common agent tasks. Use these instead of unscoped search when you know what kind of document you need.

### "How is X implemented?"
```
sift_search query="retry logic backoff tower" filter={ must: [{ field: "source", match: "github" }] } limit=5
```
Then `sift_expand` on the best hit. Filters to code — skips issues, docs, chat noise.

### "What was decided about X?"
```
sift_multi_search query="authentication middleware rewrite" variants=[
  { label: "issues", filter: { must: [{ field: "source", match: "linear" }] } },
  { label: "PRs", filter: { must: [{ field: "source", match: "github" }, { field: "entity_type", match: "pull_request" }] } },
  { label: "docs", filter: { must: [{ field: "source", match: "project_docs" }] } }
]
```
Triangulates across decision surfaces in one call.

### "What's the contract/spec for X?"
```
sift_search query="RetrievalPayload canonical payload tiers" filter={ must: [{ field: "source", match: "project_docs" }] } limit=3
```
Targets internal documentation only.

### "Who worked on X / what's the history?"
```
sift_search query="circuit breaker rate limiting" filter={ must: [{ field: "source", match: "github" }, { field: "entity_type", match: "pull_request" }] } limit=10
```
PR history filtered by topic.

### "Are there existing issues for X?"
```
sift_search query="cursor pagination skips failed entities" filter={ must: [{ field: "source", match: "linear" }] } limit=5
```
Always check before creating new issues. Score > 0.7 = likely duplicate.

### Filter reference (common fields)

| Field | Values | Use |
|-------|--------|-----|
| `source` | `github`, `linear`, `project_docs`, `discord` | Scope by data source |
| `entity_type` | `pull_request`, `issue`, `code`, `document` | Narrow within a source |
| `repo` | repo name | Specific repository |
| `author` | username | Who wrote it |
| `status` | `open`, `closed`, `merged` | Issue/PR state |
| `labels` | label names | Topic tags |
| `project` | project name | Linear project scope |

Always call `sift_facets` first if unsure what values exist for a field.

## When NOT to Use Sift

- **Current issue/PR status** → use issue tracker or git API (Sift data may lag)
- **Structured queries** (status=open AND assignee=X) → use source-specific APIs
- **Live database records** → use database tools directly
- **Date-range browsing** → use source APIs with native date filters

Sift is for **discovery and recall**. Source APIs are for **current state and structured queries**. Combine both: find context in Sift, verify/act via source APIs.

## Collections & Data Freshness

Use `sift_collections` to list available collections and sizes.

See [COLLECTIONS.md](COLLECTIONS.md) for what's in each collection.

**Freshness varies by collection.** Some sync via webhooks (~instant), others via daily/weekly cron. For critical decisions, verify against the live source.

## Organization Context

See [CONTEXT.md](CONTEXT.md) for team, project, and domain background that helps interpret results.
