# Sift Collections

## Team (company-*)

| Collection | Contents | Best for | Example queries |
|------------|----------|----------|-----------------|
| `company-linear` | Linear issues, tasks, bugs | Project state, work tracking, blockers | "onboarding form bugs", "what's in backlog" |
| `company-code` | Source files from all repos | Implementation details, patterns, architecture | "how does auth work", "Stripe integration" |
| `company-docs` | Wiki, Obsidian docs, legal | Official documentation, specs, policies | "commission model", "design system spec" |
| `company-discord` | Team chat messages | Informal decisions, discussions, context | "why did we choose Vercel", "pricing discussion" |
| `company-research` | Competitor & market analysis | Market positioning, feature comparison | "Contact.xyz pricing", "EU crew booking market" |
| `company-memory` | Agent/team knowledge base | Architecture notes, project overview | "tech stack decisions", "deployment setup" |
| `company-github` | PRs, reviews, code changes | Recent code changes, review feedback | "PR for mobile fix", "review comments on auth" |
| `company-fathom` | Meeting transcripts (AI summaries) | What was discussed in calls | "equity discussion call", "Tea design feedback" |
| `company-calendar` | Calendar events | Meeting context, schedules | "meetings this week", "when was the design review" |

## Personal (requires Bearer auth)

| Collection | Contents | Best for | Example queries |
|------------|----------|----------|-----------------|
| `personal-memory` | Daily notes, people profiles, decisions | Personal recall, relationship context | "what happened Feb 10", "Rugile's preferences" |
| `personal-vault` | Obsidian personal vault (health, finance, bureaucracy) | Personal documents, life admin | "Finanzamt debt", "doctor appointment" |
| `agent-sessions` | Past AI conversation transcripts | Recovering context from old sessions | "that debugging session about chunking" |

## Tips

- **Leave `collection` empty** to search everything — good for exploratory queries
- **Scope to 1-2 collections** when you know the source type — reduces noise, faster results
- **Combine collections logically:** `company-discord` + `company-docs` for decision archaeology,
  `company-linear` + `company-code` for implementation context
