# Recovering Agent State After Arch Install

Backups created: 2026-05-04 ~20:46 GMT+2
Source machine: WSL (archlinux distro on Windows)
Destination: F:\migration-backup\agent-state\ on the Ventoy USB

## What's in the backups

| Tarball | Size | Contents | Excluded |
|---|---|---|---|
| `claude-mem-20260504.tgz` | 28 MB | `~/.claude-mem/` — full Hindsight SQLite DB + auto-backups + logs | (nothing — this dir is small) |
| `claude-20260504.tgz` | 1.16 GB | `~/.claude/` — sessions, plans, todos, projects, history.jsonl, settings, memory, skills, commands, plugins, statusline, mcp.json, CLAUDE.md | `cache/`, `debug/`, `telemetry/`, `statsig/`, `file-history/`, `paste-cache/`, `shell-snapshots/`, `session-env/`, `usage-data/`, `plugins/cache/`, `backups/` |
| `codex-20260504.tgz` | 135 MB | `~/.codex/` — config.toml, history.jsonl, logs_2.sqlite (27 MB), state_5.sqlite, sessions, memories, rules, skills, plugins | `auth.json` (re-login), `cache/`, `tmp/`, `.tmp/`, `log/`, `shell_snapshots/` |
| `opencode-20260504.tgz` | 33 MB | `~/.local/share/opencode/` — opencode.db (90 MB → ~33 MB compressed), snapshot/, storage/ | `auth.json`, `mcp-auth.json`, `log/`, `tool-output/` |

**Total: 1.36 GB on Ventoy.** Bitwarden backup, transmission, and Arch ISO together fit in remaining ~3 GB.

## Restore procedure on Arch (after `post-install.sh` runs)

```bash
# 1. Mount the Ventoy USB (udiskie auto-mounts but check):
ls /run/media/$USER/Ventoy/migration-backup/agent-state/

# 2. Extract everything to home directory:
cd ~
tar -xzf /run/media/$USER/Ventoy/migration-backup/agent-state/claude-mem-20260504.tgz
tar -xzf /run/media/$USER/Ventoy/migration-backup/agent-state/claude-20260504.tgz
tar -xzf /run/media/$USER/Ventoy/migration-backup/agent-state/codex-20260504.tgz
tar -xzf /run/media/$USER/Ventoy/migration-backup/agent-state/opencode-20260504.tgz

# Verify:
ls ~/.claude-mem/claude-mem.db    # ~30 MB SQLite — your Hindsight memory
ls ~/.claude/sessions/            # past Claude Code sessions
ls ~/.codex/state_5.sqlite        # Codex session state
ls ~/.local/share/opencode/opencode.db  # OpenCode state DB
```

## Re-authenticate (one-time per tool)

Auth tokens were excluded from backups for security — they re-issue cleanly on first use:

```bash
# Claude Code:
claude               # first run prompts for OAuth in browser

# OpenCode:
opencode auth login  # browser flow

# Codex:
codex login          # browser flow
```

Existing sessions/memory remain intact across the re-auth — only the credential file needs to be regenerated.

## Path remapping for Codex trust list

Codex `config.toml` has 18 hardcoded trusted-project paths. WSL paths (`/home/nullsense/...`) will exist on Arch unchanged. Windows paths (`/mnt/c/Users/matas/...`) will not exist on Arch — **delete those entries on first run** or Codex will complain. Easy edit:

```bash
# After restore, prune dead WSL/Windows paths from Codex trust list:
sed -i '/\[projects\.".*\/mnt\/c\//,/^$/d' ~/.codex/config.toml
sed -i '/\[projects\.".*\/home\/nullsense\/Programming\/dream-slate-finance\//,/^$/d' ~/.codex/config.toml  # if not migrated
# Or just open and hand-edit:
$EDITOR ~/.codex/config.toml
```

The `claude-mem-search` MCP entry has a hardcoded path containing the plugin version (`12.4.8`). Will break on update. Either:
- Edit by hand to point at current version path, or
- Delete the entry and let it regenerate when claude-mem plugin re-installs.

## What's NOT in these backups (you'll need to redo)

- **Auth tokens** — re-login (intentional)
- **Per-machine MCP server installations from `npx -y @upstash/context7-mcp`** etc. — first run downloads them again
- **claude-mem plugin cache** at `~/.claude/plugins/cache/` — regenerates on first plugin load
- **Cached model lists, statsig, telemetry** — cosmetic state, regenerates

## If something looks off after restore

Check sizes match what's documented above (`du -sh ~/.claude ~/.codex ~/.local/share/opencode ~/.claude-mem`). If a tarball extracted clean but a tool acts confused, the most common failures:

| Symptom | Fix |
|---|---|
| Claude Code shows no past sessions | Permissions wrong on `~/.claude/sessions/` — `chmod 700 ~/.claude/sessions/` |
| Codex says "untrusted project" everywhere | The trust list paths still reference WSL — edit `~/.codex/config.toml` |
| OpenCode auth wedged | `rm ~/.local/share/opencode/auth.json` and re-run `opencode auth login` |
| claude-mem-search MCP fails to start in Codex | Path to the cjs script changed — fix in `~/.codex/config.toml` `[mcp_servers.claude-mem-search]` block |

## When to delete the Ventoy backups

After you've verified all four tools work on Arch with their restored state — at minimum a week of normal use, ideally after you've successfully run a session that touches old memory. Then:

```bash
rm /run/media/$USER/Ventoy/migration-backup/agent-state/*.tgz
```
