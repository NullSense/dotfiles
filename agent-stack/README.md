# Agent Stack — setup & operations runbook

Reproducible setup for the AI-agent toolchain (bwrap sandbox, multi-agent
safety hooks, agent-vault, MCP, signed-commit + HTTPS-push git auth) on any
Linux machine. This is the **operational** runbook; the **architecture** is in
[`../arch-install/AGENTS.md`](../arch-install/AGENTS.md), the credential broker
in [`../arch-install/AGENT-VAULT.md`](../arch-install/AGENT-VAULT.md), and the
design rationale in [`DESIGN.md`](./DESIGN.md).

## Prerequisites

- A Linux box (Arch / Debian-Ubuntu / Fedora) with **chezmoi initialized** from
  this dotfiles repo, **mise** installed, and **sudo**.
- A Bitwarden account (SSH auth key) and, optionally, Infisical access.
- Unprivileged user namespaces enabled (bwrap needs them — `bootstrap` checks).

## Quick start

```bash
cd ~/.local/share/chezmoi/agent-stack
mise install         # pinned tools (node, bun, infisical, cc-safety-net)
mise run bootstrap   # idempotent: system pkgs + chezmoi apply + signing + gh + services
mise run doctor      # green/red health board
```
`bootstrap` is safe to re-run. It prints the few steps a human must do (they
can't be automated): see below.

## Manual steps `bootstrap` will prompt for

1. **Register the signing key on GitHub** — `~/.ssh/id_ed25519_sign.pub` →
   GitHub → SSH and GPG keys → **New SSH key → type: Signing key** (not Auth).
2. **gh login** — `gh auth login` (choose **HTTPS**, answer **yes** to
   "Authenticate Git with your GitHub credentials").
3. **agent-vault** — install the binary + TPM2-seal its master per
   `../arch-install/AGENT-VAULT.md`, then `systemctl --user enable --now agent-vault`.
4. **Infisical** — `infisical login` (or a machine-identity token) so per-agent
   API keys provision.

## How the pieces fit (one screen)

- **Sandbox** — `~/bin/{claude,codex,opencode}` → `_agent-shim` → `infisical run`
  → `agent-isolated` (bwrap). Reads all of `$HOME` (secrets masked), writes
  scoped to projects + `~/Programming` + `~/.cache` + the **config surface**
  (chezmoi source, `~/.config`, `~/.local/{bin,share}`, dotfiles — writable so
  agents can manage dotfiles without losing edits).
- **Commit signing** — a dedicated **sign-only** ed25519 key in
  `git-sign-agent.service`; `gpg.ssh.program=~/bin/git-sign-ssh` forces git's
  signer to that agent on host *and* in-sandbox. The key is registered on GitHub
  as Signing-only, so it **cannot authenticate** anywhere. Bitwarden keeps your
  *auth* key (server SSH), exposed to agents only via `--ssh`.
- **Push** — HTTPS via gh's credential helper, host-side. SSH `git@github.com:`
  URLs are transparently rewritten to HTTPS (`insteadOf`). gh's token lives in
  the keyring, masked from sandboxes — so agents commit, **push happens
  host-side** (`!git push` / you).
- **Destructive guard** — `cc-safety-net` on Claude (settings.json hook) +
  OpenCode (plugin) + Codex (TUI plugin).

## Update flows

| Task | How |
|---|---|
| Add/remove an **MCP server** | edit `.chezmoidata/mcp.yaml` → `mise run update-mcp` (= `chezmoi apply`, fires `mcp-sync`) |
| Bump a **pinned tool** | edit `mise.toml` → `mise run update-tools` |
| Rotate an **API key** | rotate in Infisical → re-run `infisical login` / `mise run bootstrap` |
| Add a **sandbox capability** | edit `bin/executable_agent-isolated` → `chezmoi apply ~/bin/agent-isolated` → `--self-test` |

## Troubleshooting

- **`bwrap` fails / "user namespaces"** → `mise run doctor` prints the
  `sysctl` fix (Debian/Ubuntu restrict them by default).
- **Commit fails `Couldn't find key in agent`** → `git-sign-agent` isn't
  running (`systemctl --user status git-sign-agent`) or `gpg.ssh.program` isn't
  set to `~/bin/git-sign-ssh`.
- **`gh` "token in keyring is invalid" in new terminals** → GNOME keyring isn't
  unlocked at login; push will be flaky until fixed (PAM/SDDM keyring unlock).
- **Agent can't write a config / "edits vanished"** → should not happen anymore
  (config surface is RW); if it does, the path may be a masked secret dir.
- **`chezmoi re-add` / `edit`** auto-commits **and pushes** (autopush) — it
  commits *all* pending source changes, not just the file. Review `git status`
  in `~/.local/share/chezmoi` first.
