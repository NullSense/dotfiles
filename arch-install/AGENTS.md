# AI Agents on this machine — system overview & index

How `claude` / `codex` / `opencode` are wired, sandboxed, fed credentials,
and given tools. This is the **map**; deep-dives are linked per section.

> Scope: the local dev-agent stack on this Hyprland/Arch box. Homelab/network
> docs are separate (`~/notes/HOMELAB.md`).

## Related docs & live files

| Topic | Doc / file |
|---|---|
| Credential broker (HTTPS proxy) | [`AGENT-VAULT.md`](./AGENT-VAULT.md) |
| Agent state backup/restore | [`RECOVER-AGENT-STATE.md`](./RECOVER-AGENT-STATE.md) |
| Full machine install runbook | [`RUNBOOK.md`](./RUNBOOK.md) |
| Sandbox wrapper (source) | `bin/executable_agent-isolated` → `~/bin/agent-isolated` |
| Dispatch shim (source) | `bin/executable__agent-shim` → `~/bin/_agent-shim` |
| MCP source-of-truth | `.chezmoidata/mcp.yaml` |
| MCP sync tool | `dot_local/bin/executable_mcp-sync` → `~/.local/bin/mcp-sync` |
| Safety hooks | `dot_claude/hooks/{deny-secrets,destructive-guard,attention}.sh` |
| Hook registrations | `~/.claude/settings.json` (NOT chezmoi-tracked — edit live) |

## Runtime pipeline (what happens when you type `claude`)

```
You type:  claude / codex / opencode
   │  PATH → ~/bin/<agent> shim (on-disk, shadows the real binary so any
   │         shell/script/exec is caught — not a zsh function)
   ▼
~/bin/<agent>  ──exec──▶  ~/bin/_agent-shim <agent> "$@"
   │   lifts wrapper flags out of $@:  --ssh --gpg --rbw --agent-vault --dotfiles
   ▼
infisical run --silent --                      ◀── TIER 1  env-secret injection
   │   populates env from Infisical vault (skip with AGENT_NO_INFISICAL=1)
   ▼
~/bin/agent-isolated <agent>                   ◀── TIER 2  bwrap sandbox
   │   --unshare-all --share-net · tmpfs / · ro-bind $HOME (read floor)
   │   secret masks · writes scoped to projects · --clearenv + allowlist
   ▼
 ┌─ bwrap ─────────────────────────────────────────────────────┐
 │  AGENT PROCESS                                               │
 │    reads : ALL of $HOME            (secrets masked)          │
 │    writes: projects + ~/Programming + agent state           │
 │    net   : OPEN (--share-net, no egress filter by default)  │
 │    ├─ spawns stdio MCPs (npx playwright / chrome-devtools /  │
 │    │     react-grab) inside the sandbox, inherit env         │
 │    └─ HTTP MCPs (exa, context7) ─── network ───┐             │
 └────────────────────────────────────────────────┼───────────┘
                                                   ▼  iff --agent-vault + daemon up
                              agent-vault MITM proxy 127.0.0.1:14322   ◀── TIER 4
                                 injects real API keys on egress,
                                 blocks unregistered hosts
                                                   ▼
                                              upstream APIs

Host-side, Claude-Code-only, runs on each tool call (parallel to above):
   PreToolUse hooks → deny-secrets.sh · dcg · rtk hook claude   ◀── TIER 3
```

## The tiers

| Tier | Mechanism | Protects against | Always on? | Covers |
|---|---|---|---|---|
| 1 | **Infisical** (`infisical run`) | app secrets sitting in plaintext files | yes (if installed) | all agents |
| 2 | **bwrap** (`agent-isolated`) | prompt-injection touching FS / reading secrets | yes | all agents |
| 3 | **PreToolUse hooks** (`deny-secrets`, `dcg`) | secret-extraction & destructive commands | yes | **Claude only** |
| 4 | **agent-vault** (MITM proxy) | API keys leaking into transcripts/env | opt-in (`--agent-vault`) | per-invocation |

### Tier 1 — Infisical
Outermost wrap (`_agent-shim`). Pulls vault secrets into the process env so
Tier 2 can forward the per-agent API key. Note: Tier 2 does `--clearenv` and
only re-exports an allowlist, so Infisical effectively delivers *only* the
keys `agent-isolated` forwards (ANTHROPIC/OPENAI/OPENROUTER/OPENCODE) — not a
broad env. Disable per-call with `AGENT_NO_INFISICAL=1`.

### Tier 2 — bwrap sandbox (`agent-isolated`)
**Deny-then-allow read model** (mirrors Anthropic's `sandbox-runtime`):
- `--ro-bind $HOME` → the agent can READ the whole home (kills "can't access
  X" friction); system (`/usr`,`/etc`) read-only; `/` is tmpfs.
- Secrets carved back out with `--tmpfs` / `--ro-bind /dev/null` overlays —
  this masklist IS the security boundary (fail-closed; see the script).
- WRITES confined to: each agent's own state dirs, the cwd workspace (if a
  real project), **`~/Programming` (always RW)**, and `AGENT_BIND=/a:/b`.
- Everything else under `$HOME` (dotfiles, chezmoi source, `~/.config`,
  `~/bin`) is **read-only**.

Flags (all opt-in, lifted generically by `_agent-shim` so they work for every
agent — add a new one in TWO places: the shim's `case` + the script's parser):

| Flag | Effect |
|---|---|
| `--ssh` | bind Bitwarden SSH agent socket (git push / signed commits) |
| `--gpg` | bind `$XDG_RUNTIME_DIR/gnupg` + `GPG_TTY` |
| `--rbw` | bind rbw socket + binary (talk to unlocked vault — sparing) |
| `--agent-vault` | route HTTPS through the credential broker (Tier 4) |
| `--dotfiles` | flip config surface to RW (chezmoi source + `~/.config` + rc files + `~/bin`) for dotfile-management; **secrets stay masked** — NOT `*-raw` |

Bypasses: `AGENT_UNSANDBOX=1 <agent>` (no bwrap), or the `*-raw` aliases
(`claude-raw`→`~/.local/bin/claude`, `codex-raw`→`/usr/bin/codex`,
`opencode-raw`→`/usr/bin/opencode`) — full host access, **all secrets
exposed**. Last resort only.

Three access tiers, summarized:

| | reads | writes | secrets |
|---|---|---|---|
| `<agent>` (default) | all `$HOME` | projects + `~/Programming` | masked |
| `<agent> --dotfiles` | all `$HOME` | + configs + chezmoi source | **masked** |
| `<agent>-raw` / `AGENT_UNSANDBOX=1` | everything | everything | **exposed** |

Verify: `~/bin/agent-isolated --self-test` (33 checks; run from a project dir).
Deep-dive in memory `reference_agent_isolation.md`.

### Tier 3 — PreToolUse hooks (Claude Code only)
Registered in `~/.claude/settings.json` → `hooks.PreToolUse`:

| Hook command | Source | Purpose |
|---|---|---|
| `deny-secrets.sh` | `dot_claude/hooks/` (ours) | regex-block secret-extraction commands (rbw/bw/gpg/ssh-add/`cat *.pem`/`cat ~/.ssh`…). Matches **Bash + Read/Edit/Write/NotebookEdit/Glob/Grep**. |
| `dcg` | [Dicklesworthstone/destructive_command_guard](https://github.com/Dicklesworthstone/destructive_command_guard) (binary at `~/.local/bin/dcg`) | block destructive ops: `rm -rf`, destructive git, DB drops, k8s/docker/cloud/terraform, supply-chain, AST-level interpreter-escape. Per-rule allowlist: `dcg allow <rule-id>` → `~/.config/dcg/allowlist.toml`. |
| `rtk hook claude` | RTK | token-optimizing command rewrite (not security). |

`dot_claude/hooks/destructive-guard.sh` is a **retired no-op** (superseded by
`dcg` 2026-05-22); kept only so a stale reference returns exit 0.

**Related project not installed:**
[kenryu42/claude-code-safety-net](https://github.com/kenryu42/claude-code-safety-net)
— a multi-agent destructive-command catcher (Claude/Codex/OpenCode/Gemini/
Copilot). We use `dcg` instead, which is broader but **Claude-only**. See
"Known gaps" for the resulting codex/opencode exposure.

### Tier 4 — agent-vault (credential broker)
Opt-in MITM HTTPS proxy. The agent gets a session token + proxy URL, never
the real key; the proxy substitutes credentials on outbound requests and
blocks unregistered hosts. Engaged via `--agent-vault` (sets `HTTPS_PROXY`,
binds the MITM CA inside the sandbox). Daemon: `agent-vault.service` (systemd
--user, TPM2-sealed master). Full setup + MCP-through-AV in
[`AGENT-VAULT.md`](./AGENT-VAULT.md).

## MCP tools — single source of truth → per-agent sync

MCP config is **not** wired at runtime; it's generated at apply-time:

```
.chezmoidata/mcp.yaml          (edit here — the only place)
   │  chezmoi apply → run_onchange_after_mcp-sync.sh.tmpl  → mcp-sync
   ▼
~/.local/bin/mcp-sync (python; surgical edits, preserves other keys)
   ├──▶ ~/.claude.json                       (mcpServers)
   ├──▶ ~/.codex/config.toml                  ([mcp_servers.*])
   └──▶ ~/.config/opencode/opencode.jsonc     (mcp)
```

Two transports: `type: http` (exa, context7 — hosted) and `type: stdio`
(playwright, chrome-devtools, react-grab — local npx).

- **stdio MCPs spawn inside the sandbox** → inherit broad-read + open-net.
- **Browser MCPs bypass agent-vault**: prefixed `env -u HTTPS_PROXY -u
  HTTP_PROXY` in `mcp.yaml` so navigation to arbitrary sites isn't blocked by
  the broker (AV blocks unregistered hosts by design).
- **Credentialed HTTP MCPs**: leave the key out of `mcp.yaml`; register the
  upstream host in agent-vault and let the proxy inject it.

After editing `mcp.yaml`: `chezmoi apply` (or run `mcp-sync` directly). On
codex/opencode the synced block carries a "managed by mcp-sync" banner —
don't hand-edit the agent configs. See memory `project_chezmoi_mcp_sync.md`.

## Secret stack (3 legs)

| Layer | Tool | Holds | Reaches agent via |
|---|---|---|---|
| Human creds | **Bitwarden** | master pw, SSH key, recovery codes | rbw / SSH agent (opt-in `--ssh`/`--rbw`) |
| App env secrets | **Infisical** | `DATABASE_URL`, `JWT_SECRET`, … | Tier 1 `infisical run` |
| Brokered HTTPS keys | **Agent Vault** | LLM/MCP API keys (agent never sees) | Tier 4 proxy (opt-in `--agent-vault`) |

## Verification

```sh
~/bin/agent-isolated --self-test         # 33 checks (run from a project dir)
~/bin/agent-isolated codex --dry-run     # inspect the bwrap argv
dcg allow                                # list dcg allowlisted rules
systemctl --user status agent-vault      # broker health (Tier 4)
curl -s http://127.0.0.1:14321/health    # broker control API
```

## Known gaps / critique

1. **Open network egress + broad reads.** `--share-net` has no egress filter,
   and the read-floor exposes all of `$HOME`. A prompt-injected agent can read
   the whole codebase and exfiltrate it anywhere. FS isolation without network
   isolation is incomplete (Anthropic ships both for this reason). agent-vault
   *would* close it (blocks unregistered hosts) but is opt-in + can be down.
2. **Tier 4 is opt-in and degrades silently.** Default forwards the per-agent
   key as plaintext env; if the broker daemon is down, agents fall back to env
   keys with no error. The most secure path is off unless you ask for it.
3. **Tier 3 is Claude-only.** `dcg` + `deny-secrets` are `settings.json`
   hooks; **codex/opencode have no destructive-command or secret-deny hook**.
   They rely solely on the bwrap sandbox (Tier 2). claude-code-safety-net
   would cover all agents if multi-agent guarding is wanted.
4. **MCP supply chain.** stdio MCPs run `npx …@latest` inside the sandbox with
   the agent's full access; unpinned releases are a supply-chain vector.
5. **deny-secrets is a regex blocklist** — bypassable via `base64`,
   `python -c open(...)`, etc. Defense-in-depth, not a boundary.

## Conventions

- Add a sandbox capability → edit `bin/executable_agent-isolated` (source),
  `chezmoi apply ~/bin/agent-isolated`, re-run `--self-test`.
- Add a generic agent flag → shim `case` **and** `agent-isolated` parser.
- Add/remove an MCP → edit `.chezmoidata/mcp.yaml`, `chezmoi apply`.
- `settings.json` is **not** chezmoi-tracked — edit it live.
