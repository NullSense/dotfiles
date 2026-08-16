# Query Optimization Patterns

Query reformulation is the single biggest quality lever. Benchmarks show:
- Worst query score: 0.243 → 0.527 (+117%)
- Average weak query: 0.332 → 0.699 (+111%)
- Queries scoring > 0.6: 50% → 90%

## Core Technique: Term Expansion

Don't search with the user's exact words. Expand to include terms that actually appear in the documents.

| User query | Expanded search | Score improvement |
|-----------|----------------|-------------------|
| "design system" | "CSS variables theme colors font family tokens" | 0.378 → 0.871 (+130%) |
| "feedback from Tea" | "feedback 5 6 out of 10 typography" + scope to meetings | 0.243 → 0.867 (+257%) |
| "commission rates" | "commission fee percentage creative booker take rate" | 0.384 → 0.578 (+51%) |
| "data model" | "waitlist contacts profiles table schema migration SQL" | 0.365 → 0.652 (+79%) |
| "strategy meetings" | "action items decided agreed next steps alignment" | 0.291 → 0.527 (+81%) |

## Reformulation Strategies

When top score < 0.6, try these in order:

1. **Synonym expansion** — "commission" → "fee structure" → "take rate" → "platform cut"
2. **Domain specificity** — replace abstract terms with concrete ones that appear in docs
3. **Collection scoping** — narrow to the most likely collection (40% better scores than global)
4. **Decomposition** — split complex questions into 2-3 simpler searches
5. **Perspective shift** — search for what the *answer* contains, not the *question*

## The Expand Multiplier

Snippets (~200 chars) often look like weak matches. **Always expand before concluding
a result is irrelevant.** Full documents frequently contain the definitive answer.

| Query | Snippet impression | After expand |
|-------|-------------------|--------------|
| Design system | "Muted text, placeholders, monochromatic" | Full token table: fonts, CSS variables, color philosophy, usage rules |
| Commission | "Keep more of what you earn" | Complete pricing analysis: competitive positioning, comparisons, tiered suggestion |
| Feedback | "The Deal — we optimize her portfolio" | Full rating: 5-6/10, specific improvement areas, contact info, followup plan |

## Evaluate Before Expanding

Don't blindly expand the highest score. Read the snippets and pick the result that best
answers the user's *actual question*. A 0.70 result from the right document beats a 0.85
from a tangential one.

## Collection Scoping

Scoped searches give ~40% better scores than global. Use when you know the source type:

| Looking for | Likely collection type |
|------------|----------------------|
| Why a decision was made | Chat messages, meeting transcripts |
| How something is implemented | Code |
| Official specs or policies | Documentation |
| Issue history | Issue tracker |
| Market/competitor intel | Research |
| What happened on a date | Memory/daily notes |
| Past AI conversations | Session transcripts |

## Multi-Query Strategy

**Search is cheap (<1s per query).** Don't settle for one weak result.

Good patterns:
- Same topic, 2-3 different phrasings
- Same topic, 2-3 different collections
- Broad search first, then narrow based on what you find
- Opposing perspectives: search for positives AND negatives about the same topic

A bad answer from one query is worse than a great answer from five.
