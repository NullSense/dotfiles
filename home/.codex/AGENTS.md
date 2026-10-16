# Agent Instructions (Global)

One global instruction file for every coding agent: `~/.dotfiles/home/.codex/AGENTS.md`. Claude
Code loads it as the user rule `~/.claude/rules/AGENTS.md`, Codex as `~/.codex/AGENTS.md`, omp as
`~/.omp/agent/AGENTS.md`, and OpenCode as `~/.config/opencode/AGENTS.md` (all symlinks). Do not
add a global `CLAUDE.md` or a `~/.claude/AGENTS.md`.

## Dotfiles = plain Git + direct symlinks · repo: `~/.dotfiles/` · public NullSense/dotfiles
Tracked home files live under `~/.dotfiles/home/` using their literal paths. Each live target is an
individual symlink into that tree, so editing `~/.zshrc` or `~/.config/foo` directly edits the
Git-tracked file. There is no render/apply/re-add layer and no encoded filename vocabulary.

**Canonical workflow:** edit the live home path, inspect `git -C ~/.dotfiles diff`, then commit and
push deliberately. `~/.dotfiles/install.sh --check` verifies every tracked target; `--install`
repairs links and preserves conflicting files under `~/.local/state/dotfiles-backups/`.

- Never put plaintext credentials in this public repository. Use Infisical, Agent Vault, systemd
  encrypted credentials, or ignored local state.
- Custom MCP inventory lives in `~/.config/litellm/config-mcp.yaml`; clients connect only to the
  loopback LiteLLM MCP gateway at `http://127.0.0.1:4001/mcp/`.
- New dotfiles go under the literal `home/` path, then run `~/.dotfiles/install.sh --install`.
- Repository-only documentation and bootstrap tools stay outside `home/` and are not linked.

## Delegation
- The lead agent plans at high reasoning effort and gives each sub-agent a concrete plan,
  owned files, acceptance criteria, and a narrow validation budget before dispatch.
- Use medium reasoning effort for delegated implementation work. The lead agent orchestrates,
  reviews results, and owns integration; keep expensive validation coordinated across agents.

## Git
Commit finished, verified work without being asked. For dotfiles, commit from `~/.dotfiles` and
push deliberately; a push publishes immediately to a public repository. The dotfiles index is
shared by every session and often holds other sessions' staged files, so commit with an explicit
pathspec (`git -C ~/.dotfiles commit -F <msg> -- <paths>`) and stage nothing you don't commit in
the same command. A pathspec commit takes the whole working file, so name only files whose diff is
entirely yours; leave mixed files to the user. Pause
before pushing ONLY if it would bundle unrelated drift, include secrets, rewrite pushed history,
or land on a protected branch with no feature branch.

## Privilege elevation
- This workstation uses a bounded 15-minute global sudo timestamp so one explicit `sudo -v`
  authentication can cover concurrent trusted agent maintenance. Agents must use `sudo -n`; if
  the ticket is absent or expired, stop and ask the user to run `sudo -v` in their own terminal.
- Do not use repeated `pkexec` or `run0` calls for agent automation: separate agent processes can
  still trigger separate graphical Polkit prompts. Group related privileged changes into one
  reviewed operation where practical, and never start parallel authentication prompts.
- Never read, pipe, log, or store the user's password. Never enable passwordless sudo or an
  infinite timestamp. Revoke the global ticket early with `sudo -K` after maintenance.

## Keybindings
Before binding any shortcut (Hyprland/app/shell), grep the config for the exact modifier+key and
confirm it's free; also scan `hyprctl binds` live. If taken, don't clobber — pick a free mnemonic
and tell the user. Hyprland binds: `~/.config/hypr/bindings.conf`.
Taken (non-exhaustive): SUPER+ALT+ C=Capture · D=Dictation · V=Voice menu · R=Recording · G=Grab.

## Testing
Fix a bug → write a regression test immediately (TDD preferred).

## Ephemeral scripts and artifacts
- Investigation scripts, probes, one-off migrations, temporary fixtures, debug harnesses, and
  generated reports are ephemeral by default. Delete them before finishing the task.
- A new script may remain only when it has a named recurring caller or is wired into an existing
  test, install, or operations interface. "Might be useful later" is not sufficient.
- Prefer adding reusable behavior to the existing owning module over creating another standalone
  helper. Migrate any unique coverage, then delete superseded or overlapping scripts.
- Before committing, review every newly added executable and scratch artifact. Explicitly remove
  those used only during the investigation and report any intentionally retained script with its
  owner and invocation path.
- Keep bulk builds, tool caches, binaries, model data, source snapshots, archives, databases, and
  acceptance/benchmark fixtures in verified disk-backed, owner-specific storage such as
  `${XDG_CACHE_HOME:-$HOME/.cache}/agent-tmp/<project-or-agent>/`. Set each child’s `TMPDIR` and
  relevant tool build/output roots there before launch; verify the filesystem, since a cache path
  or `TMPDIR` may itself be RAM-backed.
- Use `/tmp`, tmpfs/ramfs, and runtime directories only for small, short-lived scratch, sockets, or
  control metadata—not bulk data. Keep fixture/build data on disk even when a Unix socket needs
  a short path.
- **Clean up after yourself before reporting done.** Every lane or sub-agent removes what it
  created: its `TMPDIR`/scratch directories, test stacks and containers (never their volumes),
  builder containers, throwaway databases, and `target/` dirs of its own disposable worktrees.
  Delete through `agent-clean` (`agent-clean path …`, `agent-clean [--running] docker …`). It is the
  only allowlisted delete. `rm -rf` on absolute or home paths is denied, and the tool refuses
  anything in use or outside its approved roots. It also permits owned Python bytecode caches
  under `~/bin`, `~/.local/bin` and their dotfile sources; see `agent-clean` for exact scope.
  Prefer an owner tool where one exists (e.g. `sift-test-infra down`). The coordinator verifies
  cleanup in each hand-back.
  A refused cleanup is a permission bug: report the exact command so the user can fix the
  settings. Never route it through another agent.
- Track ownership of temporary directories and leases; promptly remove owned obsolete artifacts
  after retaining needed evidence through existing project disk handoffs. Before cleanup, check
  ownership and actual references; preserve unowned/live data and byte-verify any needed archive.
  Do not stop services or processes to reclaim it. Report filesystem space freed separately from
  physical RAM recovered.

## Documentation and web research — never answer third-party facts from memory
- **Known libraries, SDKs, CLIs, and developer tools → Context7 MCP first.** Resolve the library ID,
  verify it against the project-pinned version, then fetch a narrow topic (1–2k tokens; 5k+ for
  overviews). Reuse resolved IDs in-session.
- **Whenever a web search is needed → `parallel-cli` or Exa first.** Two independent providers.
  Reach for either, and switch to the other rather than falling through to plain WebSearch.
  Fetching an already known authoritative URL directly is not a web search.
  - **`parallel-cli`** (Parallel, `~/.local/bin/parallel-cli`, OAuth-authenticated to the Tensil
    org — no key to manage). `parallel-cli search "<objective>" --mode fast --max-results N` for
    discovery; `--mode advanced` when quality matters more than the ~1s latency;
    `parallel-cli fetch <url>` returns token-efficient markdown. It also has `research`
    (long-running; poll with `/status <run_id>`), `findall`, `enrich`, and `monitor` — reach past
    `search` when the question really is a multi-entity or watch-over-time question.
    Also reachable through the LiteLLM MCP gateway as `mcp__litellm__parallel-web_search` /
    `-web_fetch`, which uses the anonymous free tier and so has lower rate limits than the CLI.
  - **Exa** via `mcp__litellm__exa-web_search_exa` / `-web_fetch_exa`. Exa is prepaid: a
    `402 exceeded your credits limit` is a top-up, not an outage — use `parallel-cli` meanwhile.
- **Services/products** (apps, SaaS, hardware, OS features) → use current official documentation as
  evidence; use a search provider to discover the right official page, then current real-world
  fixes/issues.
- **Libraries/models** → after Context7, use official versioned docs, GitHub, and Hugging Face model
  cards/issues as appropriate. Never rely on training memory for a current claim.

## Memory
- Required behavior and durable rules belong in this file or the closest project `AGENTS.md` /
  `CLAUDE.md`; native memory is a recall aid, never the sole authority.
- Curated cross-agent notes live under `~/.claude/memory/`: start with `MEMORY.md`, then read only
  the relevant `tools/*.md` or `domain/*.md`. Add durable cross-project findings there rather than
  bloating this top-level guidance.
- Codex native memories (`~/.codex/memories/`) are generated state. Let Codex manage them; do not
  hand-edit their generated files. claude-mem was removed 2026-09-15 (34 real searches in 4.5
  months); do not reinstall it.



# Shell output distillation — repowise

`repowise distill <cmd>` is the single distillation layer (see Output Distillation below). Run a
command bare when you need exact, unfiltered output — debugging, parsing, anything where a dropped
line changes the answer.

# Codebase navigation
- **repowise** is the default for codebase questions in any indexed repo: `get_context`,
  `search_codebase`, `get_symbol`, `get_health`, `get_change_risk` via MCP, or the `repowise` CLI.
  Ask with domain vocabulary, not paraphrase — retrieval is hybrid and the full-text leg wins on
  literal tokens. Its findings are candidates, not verdicts.
- **Never use `get_answer` / `get_why` / `repowise ask` / `repowise why`.** They are the only
  repowise surfaces that spend an LLM call, and the model doing that synthesis is a local one whose
  output quality does not justify it. The *retrieval* underneath is good; the paraphrase written
  over it is not, and a fluent wrong summary of correct hits costs more than it saves. Use the
  retrieval-only tools and synthesize yourself — you see the same hits `get_answer` would.
- **graphify** (`~/.claude/skills/graphify/SKILL.md`, trigger `/graphify`) is no longer the default
  and should not be reached for on a repo repowise has indexed. It stays installed for two reasons:
  the `/graphify` command when you explicitly ask for it, and because some projects consume
  `graphify-out/graph.json` programmatically (sift's `sift-ingest-path` skill walks its node/edge
  schema). Do not remove `graphify-out/` or the skill to "finish" a migration.
- **code-intel** (`/code-intel`) still fans out to graphify as one of its three legs. Treat its
  graphify leg as supplementary, not authoritative.

<!-- REPOWISE_DISTILL:START — Do not edit below this line. Auto-generated by Repowise. -->
### Output Distillation

- Prefer `repowise distill <cmd>` for noisy commands — test runs, builds, `git status`/`log`/`diff`, searches, file listings. It runs the command unchanged (exit code preserved) and prints a compact, errors-first rendering; every error line survives.
- Output may contain a marker like `[repowise#a1b2c3d4e5f6: 230 lines omitted (~6.1k tokens); restore: repowise expand a1b2c3d4e5f6]`. The omitted content is fully preserved — run `repowise expand <ref>` to retrieve it, or `repowise expand <ref> -q <regex>` for just the matching lines.
- Never re-run a command to see omitted output; expand the marker instead.
- For structure-level questions about a large indexed file ("what's in here", "which function handles X"), `get_context(["path"], include=["skeleton"])` returns the file with bodies elided — every signature plus the bodies of the most central symbols — at a fraction of the cost of a full Read.
<!-- REPOWISE_DISTILL:END -->
