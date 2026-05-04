# Organizational Context

Background for interpreting Sift search results. Read this when you need to understand
who/what results are referring to.

## Company: Dream Slate

Curated booking platform for on-set creatives (stylists, directors, photographers, DOPs, crew).
Pre-launch, targeting March 2026 MVP. Netherlands-first, then EU expansion.

- **Business model:** 4% creative commission / 15% client commission
- **11 roles across 5 categories:** Camera, Direction, Styling, Audio, Production
- **Stack:** Next.js landing, Expo/RN app, Supabase, Vercel, PostHog, Sentry

## People

Names appear across Linear issues, Discord messages, code commits, and meeting transcripts.

| Name | Aliases in data | Role | Focus |
|------|----------------|------|-------|
| Matas | NullSense, nullsense, matas.pe | Co-founder, Dev & Design | Full-stack, design, finance, infrastructure |
| Taisei | taiseii | Co-founder, Dev | App (Expo/React Native) |
| Nojus | — | SFX | Sound design (Matas's brother) |
| Tea Ferrari | tea, teaferrari | External designer | Design exchange partner |

**Former:** Teun (partnerships) — offboarded Feb 2026, removed from all systems.

## Projects in Linear

- **Team:** Dream Slate (DRE-xxx issue prefix)
- Issues use states: Triage → Backlog → Todo → In Progress → In Review → Done/Canceled
- Labels include: Bug, Feature, Design, Infrastructure, Research, SEO

## Key Repositories

| Repo | What | Collection |
|------|------|-----------|
| Dream-Slate-Landing | Next.js marketing site | `company-code` |
| Dream-Slate-Finance | Financial tracking | `company-code` |
| Sift | This search tool | `company-code` |
| Panopticon | Agent monitoring TUI | `company-code` |
| Tensil | Climbing app (on hold) | — |

## How Knowledge Is Distributed

Decisions and context are rarely in one place. Typical pattern:

1. **Discussion** happens in Discord (`company-discord`)
2. **Decision** gets captured in a Linear issue (`company-linear`) or doc (`company-docs`)
3. **Implementation** lives in code (`company-code`) and PRs (`company-github`)
4. **Meetings** are transcribed in Fathom (`company-fathom`)
5. **Research** backing decisions is in `company-research`

To fully understand something, search across 2-3 of these collections.

## Common Topics You'll Find

- **Competitor analysis:** Contact.xyz, Casting Networks, agency models (in `company-research`)
- **Design system:** Monochromatic cream/black, Outfit + Manrope fonts (in `company-docs`)
- **Commission model:** Evolution from various % splits to 4%/15% (across Discord + research + docs)
- **Shareholder agreement:** Equity discussions, Teun offboarding (in personal-memory, Discord, fathom)
- **Infrastructure:** Hetzner VPS, Docker Compose, Qdrant, Caddy, Headscale (in `company-memory`, code)
