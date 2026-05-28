# Agent-Stack Deployment — Design Spec

**Status:** approved 2026-05-28 (SSH signing deferred — see §10)
**Goal:** make the AI-agent stack (bwrap sandbox + safety hooks + agent-vault +
MCP) reproducibly deployable on any Linux machine by a teammate, with pinned
versions, centralized config, and documented update paths.

## 1. Scope

- **In scope:** the *agent layer* — `agent-isolated`, `_agent-shim`, the
  `cc-safety-net` + `deny-secrets` hooks, `agent-vault` wiring, MCP via
  `mcp.yaml`/`mcp-sync`, and the external dependencies these need.
- **Assumed present:** a working Linux box with chezmoi initialized (the base
  OS / desktop / dotfiles are out of scope — that's `arch-install/RUNBOOK.md`).
- **Targets:** Arch, Debian/Ubuntu, Fedora (cross-distro Linux). Not macOS.
- **Non-goals:** whole-machine provisioning; macOS/seatbelt; replacing chezmoi.

## 2. Core boundary — chezmoi vs the installer

`chezmoi apply` already deploys the **runtime files** (the scripts/configs under
`bin/`, `dot_claude/hooks/`, `.chezmoidata/mcp.yaml`, `dot_local/bin/mcp-sync`,
the systemd unit). The agent-stack installer owns only what chezmoi cannot:

1. **External dependencies** — install + pin `bwrap`, `node`, `bun`,
   `infisical`, `cc-safety-net`, `agent-vault` (cross-distro).
2. **Service wiring** — enable `agent-vault.service`; declare the OpenCode
   plugin / Codex hook that aren't a plain `chezmoi apply`.
3. **Secret provisioning** — pull API keys from Infisical into agent-vault.
4. **Verification** — prove the whole stack is healthy.

Mental model: `chezmoi apply` lays down the files; `mise run bootstrap` makes
the machine able to *run* them.

## 3. Folder layout (in chezmoi source, non-deployed — like `arch-install/`)

```
agent-stack/
  DESIGN.md          # this file
  README.md          # team handoff entry point (quickstart + runbook)
  mise.toml          # [tools] = pin manifest; [tasks] = the CLI
  lib/
    distro.sh        # /etc/os-release detect → pacman|apt|dnf + package map
    doctor.sh        # health checks (invoked by the `doctor` task)
    provision.sh     # Infisical-identity → agent-vault key registration
```

This folder lives in the chezmoi repo (versioned, scanned by the existing
gitleaks/trufflehog pre-push hooks) but is **not** a deploy target, so nothing
is written to `$HOME` from here — it's tooling + docs.

## 4. Tooling — mise is the manifest AND the task runner

mise (already in use, 2026.5.x) pins and installs every tool it can via its
backends, and runs the deployment tasks. moon/justfile are unnecessary.

### 4.1 `[tools]` — the pin manifest

| Tool | mise source | Why |
|---|---|---|
| `node` | `core:node` | runtime for cc-safety-net / npx MCPs |
| `bun` | `core:bun` | fast runner for the cc-safety-net hook |
| `infisical` | `github:Infisical/cli` | secret pull + `infisical run` |
| `cc-safety-net` | `npm:cc-safety-net` | destructive-command guard (all agents) |
| `agent-vault` | `ubi:` or `aqua:` (Infisical release) | credential broker binary |

All entries are version-pinned (exact versions, not `latest`). `mise install`
in `agent-stack/` provisions them reproducibly. Bumping a version = edit one
line + `mise run update-tools`.

**Not mise-managed** (system packages, via `lib/distro.sh`): `bubblewrap`,
plus base `git`/`curl`. `codex`/`opencode` are installed per their own channels
(documented in README) — mise pins them only if a backend exists.

### 4.2 `[tasks]` — the CLI

| `mise run …` | Does |
|---|---|
| `bootstrap` | detect distro → install system deps (`distro.sh`) → `mise install` → `chezmoi apply` → enable `agent-vault.service` → `provision.sh` (keys) → wire safety-net (opencode plugin auto; print Codex TUI steps) → `doctor` |
| `doctor` | health board (see §6); non-zero exit on any failure |
| `update-mcp` | thin wrapper: "edit `.chezmoidata/mcp.yaml` then `chezmoi apply`" (fires `mcp-sync`) |
| `update-tools` | `mise install` to reconcile to pinned versions |

All tasks are **idempotent** (check-before-act; safe to re-run).

## 5. Cross-distro layer (`lib/distro.sh`)

- Detect distro from `/etc/os-release` `ID`/`ID_LIKE` → select `pacman`/`apt`/
  `dnf`.
- Map each system dependency to its per-distro package name.
- **Hard gotcha it must check:** unprivileged user namespaces (`bwrap` needs
  them). On Debian/Ubuntu (`kernel.apparmor_restrict_unprivileged_userns`) and
  some hardened kernels these are restricted — `doctor`/`bootstrap` detect this
  and print the exact `sysctl`/AppArmor fix rather than failing cryptically.

## 6. Verification (`doctor`)

Green/red board, modeled on `agent-isolated --self-test`:

- `bwrap` present + unprivileged userns works
- `agent-isolated --self-test` → 33/33
- `agent-vault.service` active + `127.0.0.1:14321/health` OK
- MCP endpoints reachable (exa/context7 HTTP; stdio MCP binaries resolve)
- hooks registered: `cc-safety-net` (claude settings.json + opencode plugin;
  codex flagged if not trusted), `deny-secrets` (claude)
- installed tool versions == `mise.toml` pins
- `~/.cache` writable inside the sandbox (regression guard for the EROFS fix)

## 7. Secrets — hybrid model

| Secret | Provisioning |
|---|---|
| API keys (Anthropic/OpenAI/Exa/…) | **automated**: `provision.sh` authenticates to Infisical with a per-member **machine-identity token**, pulls each key, scripts `agent-vault vault credential set` + `service add` |
| App env (`DATABASE_URL`…) | `infisical run` at agent launch (already wired in `_agent-shim`) |
| agent-vault master password | **manual** (per-machine): set + TPM2-seal per `AGENT-VAULT.md` §3 — bound to local TPM, cannot be centralized |
| Bitwarden login | **manual**: interactive unlock, per-machine |

Bootstrap automates everything automatable; README documents the two
irreducibly-local manual steps with exact commands. Chicken-and-egg: the
Infisical machine-identity token itself must reach the new machine through an
existing secure channel (documented: out-of-band, one-time).

## 8. Documentation (handoff)

`agent-stack/README.md` is the team entry point:
- **What this is** + the tiered architecture (1-paragraph summary, link to
  `../arch-install/AGENTS.md` for the full diagram).
- **Prereqs** (chezmoi initialized, Infisical identity token, Bitwarden).
- **Quickstart:** `cd agent-stack && mise run bootstrap`, then the two manual
  secret steps.
- **Update procedures** (§9).
- **Troubleshooting:** userns-restricted distros; `--ssh`-for-signed-commits;
  agent-vault daemon down; `bunx` cold-cache latency on first hook call.
- **Links:** `AGENTS.md` (architecture), `AGENT-VAULT.md` (broker deep-dive).

`AGENTS.md` remains the architecture reference; this README is the *operational*
runbook.

## 9. Update flows (explicit)

- **MCP servers:** edit `.chezmoidata/mcp.yaml` → `chezmoi apply` (fires
  `mcp-sync`, patches all three agents). Single source; already built.
- **Tool version:** edit the pin in `agent-stack/mise.toml` → `mise run
  update-tools`.
- **Rotate an API key:** rotate in Infisical → re-run `provision.sh` (or
  `mise run bootstrap`, idempotent) to re-pull.

## 10. Deferred — SSH commit signing (separate follow-up)

Default behavior today: `agent-isolated` scrubs `SSH_AUTH_SOCK` and masks the
agent socket; signed commits require the explicit `--ssh` flag. The intended
production answer — a **filtered signing agent** (dedicated commit-signing key
in a process-restricted socket, e.g. `authsock-filter`/`authsock-warden`, bound
by default so signing is safe-by-default while server-auth stays behind
`--ssh`) — is **out of scope for this spec** and will be designed separately.
For now the deployment documents `--ssh` as the signing path.

## 11. Open questions

- Codex safety-net trust step is interactive (TUI `/hooks` trust) — the
  installer can't fully automate it; README documents it. Acceptable.
- Whether to pin `codex`/`opencode` via mise (backend availability TBD) or
  document their native install channels.
