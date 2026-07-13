# dotfiles

Arch Linux + Hyprland + Wayland. **One repo, one source of truth.** Managed by [chezmoi](https://www.chezmoi.io/).

```
github.com/NullSense/dotfiles                   ← THIS IS THE ONLY REPO
├── arch-install/         ─────────── install-from-zero pipeline (live USB → working desktop)
│   ├── RUNBOOK.md                              top-to-bottom guide; read first
│   ├── RECOVER-AGENT-STATE.md                  Hindsight + Claude/Codex/OpenCode restore
│   ├── user_configuration.json                 archinstall 4.x config (inline disk_config + ~130 packages + custom_commands)
│   ├── user_credentials.json                   passwords (CHANGE_ME placeholder; gitignored when filled)
│   ├── preflight-on-usb.sh                     live-USB hardware probe
│   ├── validate.sh                             config sanity check
│   ├── post-install.sh                         after first boot: paru, mise, AUR, swapfile, services
│   ├── hardware-optimize.sh                    UKI cmdline, AMD GPU udev, gamemode
│   ├── setup-secure-boot.sh                    sbctl flow
│   ├── setup-inference.sh                      llama.cpp + ComfyUI Docker
│   ├── verify-system.sh                        post-install health check
│   └── fix-boot-after-windows.sh               recovery
│
├── dot_claude/        chezmoi → ~/.claude/             Claude Code: CLAUDE.md, mcp.json, statusline, skills, commands, memory, hooks (destructive-guard)
├── dot_codex/         chezmoi → ~/.codex/              Codex CLI: config.toml, rules
├── dot_config/        chezmoi → ~/.config/             hypr/, waybar/, ghostty/, mako/, opencode/, systemd/user/, agent-isolated/, etc.
├── dot_local/         chezmoi → ~/.local/              user-installed binaries (hypr-waybar-bridge, sudo-pill-daemon, etc.)
├── dot_lmstudio/      chezmoi → ~/.lmstudio/           LM Studio config presets (voice-rewrite, coding, general)
├── dot_zshrc          chezmoi → ~/.zshrc
├── dot_zshenv         chezmoi → ~/.zshenv              minimal: SSH_AUTH_SOCK, PATH, OMARCHY_PATH
├── dot_bashrc         chezmoi → ~/.bashrc
├── dot_gitconfig      chezmoi → ~/.gitconfig           SSH-signed commits/tags, github HTTPS→SSH rewrite
├── dot_profile        chezmoi → ~/.profile
├── dot_envrc          chezmoi → ~/.envrc               direnv root
├── dot_tmux.conf      chezmoi → ~/.tmux.conf
├── private_dot_ssh/   chezmoi → ~/.ssh/                (mode 700; private_ prefix preserves permissions)
├── bin/               chezmoi → ~/bin/                 user shell scripts deployed to PATH (agent-isolated, full-reload, restart-waybar, …)
├── dot_git-template/  chezmoi → ~/.git-template/       global git hooks: pre-commit (gitleaks + infisical) + pre-push (trufflehog --results=verified)
├── root/              chezmoi → /root/ (system files; opt-in)
│
├── .chezmoiignore                              tells chezmoi which paths to NOT deploy (e.g. arch-install/)
├── .gitignore                                  excludes user_credentials.json, *.bak, etc.
└── SECRETS.md                                  how secrets are managed (Bitwarden + Infisical)
```

## Two phases, one source

### Phase 1 — fresh-machine install (live USB)

Use the `arch-install/` subdir. It is **NOT** deployed by chezmoi (`.chezmoiignore` excludes it) — it lives in the repo because that's where it belongs, but it's tooling for a state where chezmoi hasn't run yet.

Three equivalent ways to reach it on a live USB:

```bash
# A. clone over the network (preferred when wifi works):
git clone --depth=1 https://github.com/NullSense/dotfiles.git
cd dotfiles/arch-install

# B. copy from Ventoy USB (offline-safe; same files):
cp -r /run/media/$USER/Ventoy/migration-backup/arch-install ~/install
cd ~/install

# C. via chezmoi (if chezmoi is installed in the live env):
chezmoi init https://github.com/NullSense/dotfiles.git --no-tty
cd ~/.local/share/chezmoi/arch-install
```

Then read `arch-install/RUNBOOK.md` and run:
```bash
nano user_credentials.json     # fill in real passwords
./preflight-on-usb.sh
./validate.sh
sudo archinstall --config user_configuration.json --creds user_credentials.json --silent
```

After archinstall reboots into the new system:
```bash
chezmoi init --apply https://github.com/NullSense/dotfiles.git
cd ~/.local/share/chezmoi/arch-install
./post-install.sh
./hardware-optimize.sh
./verify-system.sh
```

### Phase 2 — daily dotfile management

Standard chezmoi:
```bash
chezmoi edit ~/.zshrc        # edit source
chezmoi diff                 # preview
chezmoi apply                # deploy
chezmoi cd && git push       # publish
chezmoi update               # pull latest from origin and apply
```

## Why is `arch-install/` in the dotfiles repo and not separate?

It used to be `github.com/NullSense/arch-install` — that was friction. Both are "things needed to bootstrap a machine," and splitting them meant two clones, two places to remember, two diff windows.

This is the de-facto pattern for "Arch + chezmoi" repos in the wild — see [cogikyo/dotfiles](https://github.com/cogikyo/dotfiles) (`etc/arch.json` + `install.sh` at root), [AnshumanTripathi/dotfiles](https://github.com/AnshumanTripathi/dotfiles) (`.chezmoidata/packages.yaml` + `.chezmoiscripts/`), and [rghamilton3/dotfiles](https://github.com/rghamilton3/dotfiles) (per-platform `run_once_*` scripts).

## Secrets

See `SECRETS.md`. TL;DR:
- **Bitwarden** for human-typed secrets (passwords, SSH keys, 2FA codes) — see `arch-install/RUNBOOK.md` Phase 9.95 for the Bitwarden-as-SSH-agent flow
- **Infisical** for app/process secrets (env vars, API keys), via `direnv` per-project — see RUNBOOK Phase 9.95's "Infisical cold start"
- **`.gitignore`** prevents `user_credentials.json` from leaking
- The repo is **public**; nothing here decrypts to plaintext credentials

## Security model

Three layers of defense, top to bottom:

### 1. Authentication backbone — Bitwarden Desktop SSH agent

```
Bitwarden Desktop  →  ~/.bitwarden-ssh-agent.sock  →  SSH_AUTH_SOCK (set in dot_zshenv)
                                                       ├─ ssh / git push over ssh
                                                       └─ git commit/tag signing  (gpg.format=ssh)
```

- `~/.zshenv` exports `SSH_AUTH_SOCK` conditionally — present even in non-interactive contexts (cron, systemd user units, IDEs).
- `[url "git@github.com:"] insteadOf = https://github.com/` in `dot_gitconfig` forces SSH for github so HTTPS auth never falls through.
- `gpg.format = ssh` + `gpg.ssh.allowedSignersFile = ~/.config/git/allowed_signers` — GPG is **not** used for git; the SSH key is the trust root for everything.
- Locking BW Desktop (timeout or manual) clears all SSH operations until you unlock — intentional trade-off.

### 2. Per-invocation isolation — `agent-isolated` (bubblewrap) via PATH shims

Every coding-agent CLI (`claude`, `codex`, `opencode`) is auto-wrapped by `~/bin/agent-isolated`. The wrapping is enforced by **on-disk binary shims** at `~/bin/{claude,codex,opencode}` that PATH-shadow the real binaries — `~/bin/` is first in `$PATH` per `dot_zshenv`. Each shim execs `~/bin/_agent-shim` which lifts known wrapper flags and dispatches through `agent-isolated`.

Why shims, not zsh functions: a function only intercepts zsh invocations. Anything else — `command claude`, `/usr/bin/env claude`, any non-zsh shell, an `exec()` syscall from a program, a systemd unit — would bypass the wrapper. Real binaries on `$PATH` catch all PATH-based lookups regardless of context.

The agent runs with `tmpfs /` + `tmpfs $HOME`, plus a curated allowlist of read-only paths and read-write workspaces. It **cannot** see raw private keys/passwords — `~/.ssh/id_*`, `~/.gnupg`, `~/.config/rbw`, the rbw socket, browser profiles, the chezmoi `private_*` sources, atuin history, the cliphist DB, or any secret-bearing env var. Since **2026-07-13** it **can** (by default) use the Bitwarden SSH **auth** agent socket (`SSH_AUTH_SOCK` → `git push`/`ssh git@github.com`), `~/.ssh/known_hosts`, and `~/.config/gh` — so agents do git + `gh` directly. GitHub git is routed over SSH via gitconfig `insteadOf`, so no token is needed for git. `claude-raw`/`AGENT_UNSANDBOX=1` exposes everything.

Defaults-on (since 2026-07-13): Bitwarden SSH auth key, `agent-vault` HTTPS credential injection, docker socket, GPU nodes.

Escape-hatches (opt-in per invocation):
- `claude --ssh`          → no-op now (auth agent bound by default); kept for compat
- `claude --gpg`          → binds `$XDG_RUNTIME_DIR/gnupg`
- `claude --rbw`          → binds the rbw socket + config + binary
- `claude --no-agent-vault` / `--no-docker` / `--no-gpu` → opt OUT of a default-on surface

Bypasses (deliberate, no longer accidental):
- `AGENT_UNSANDBOX=1 claude …` — env-var gate inside `agent-isolated`
- `~/.local/bin/claude …` (or `/usr/bin/codex`, `/usr/bin/opencode`) — invoke the real binary by full path

`command claude` does **not** bypass: it still resolves through `$PATH` and hits the shim. Closing this hole was the reason for moving from zsh functions to shims.

Self-test: `~/bin/agent-isolated --self-test` runs 26 verifications (20 negative — secrets must be hidden, 6 positive — required surfaces must be reachable).

### 3. Secret scanning at commit & push time

Global git template at `dot_git-template/hooks/` deploys event-driven scanners to **every git repo** on the machine (existing repos via `git init` retrofit; new ones via `git config --global init.templateDir`):

| Hook | Tools | What it scans | Latency | Bypass |
|---|---|---|---|---|
| `pre-commit` | gitleaks + infisical scan, chained | staged diff only | <100ms | `git commit --no-verify` |
| `pre-push` | trufflehog `--results=verified` | commits being pushed (range `${remote_sha}..${local_sha}`) | seconds (calls real provider APIs to verify keys are live) | `git push --no-verify` |

Layer logic:
- **gitleaks** (regex + entropy, 150 rules) — fast, catches the obvious patterns at commit time
- **infisical scan** (gitleaks rules + their own) — complementary, runs alongside gitleaks at commit time
- **trufflehog** — slower (verification calls AWS STS/GitHub/Stripe/etc. with the *found* key from your machine, never from a third party) — runs only at push time so latency is acceptable. `--results=verified` filters out regex false positives: a hit means a live credential, not a test fixture.

Trufflehog gracefully no-ops if the binary is missing (`command -v` guard), so a broken install doesn't block pushes — gitleaks at commit time still applies.

### 4. CVE visibility — `arch-audit-gtk` tray indicator

System-tray indicator polling [security.archlinux.org](https://security.archlinux.org) (the official Arch Security Team tracker) every 2–6 hours with random jitter for privacy. Green = no known unpatched CVEs in installed packages; yellow/red = there are some. xdg-autostarts on login; pacman post-transaction hook re-checks after every upgrade. Package maintainer (`kpcyrd`) is an Arch + Debian + Alpine packager with a background in reproducible builds and supply-chain security.

No timer, no logs to read, no email — purely passive visibility.

### 5. Network / DNS layer — AdGuard via Tailscale + firewalld

Three sub-layers; all cross-agent, none process-aware (which is fine because layer 2 above gives process-level FS isolation):

```
agent process → DNS via Tailscale MagicDNS (100.100.100.100) → AdGuard at router → filtered answer
                ↓ if connection allowed
                firewalld (host-level conn-state firewall, default-deny inbound)
                ↓
                public internet
```

Tested working: `dig @100.100.100.100 doubleclick.net` returns `0.0.0.0` (sinkholed); `dig @1.1.1.1 doubleclick.net` returns the real IP (control). Every device on the tailnet inherits this — phones, laptops, the OnePlus 8T homelab node.

AdGuard additionally blocks DoH endpoints (`dns.google`, `cloudflare-dns.com`, `dns.quad9.net`, `mozilla.cloudflare-dns.com`) so apps attempting to bypass system DNS fall back to the system resolver and pick up your filter.

**Why no OpenSnitch:** evaluated 2026-05-11, rejected. The nftables conflict with firewalld is real (issue #1393), the default-deny ask-on-every-connection flow breaks normal workflows, and the marginal value over (bwrap default-deny network) + (AdGuard) + (firewalld) is small. The leftover `inet filter`/`inet nat`/`inet mangle` tables from the brief install are dead and clear on reboot.

**Why no third-party AI-agent firewalls:** evaluated 2026-05-11, all rejected as supply-chain risk. AgentWall, AgentShield, Rampart, Greywall, Pipelock/PipeLab, mcp-firewall — all were 2-3 months old at evaluation, single-developer, no third-party audits. Installing any of them would give an unknown party a proxy in front of every agent's traffic. Net-negative for security.

### Ad-hoc audit tools (manual, on demand)

| Tool | Use case | Command |
|---|---|---|
| `mitmproxy` | inspect what an agent actually sends during a session | `mitmproxy --mode local --intercept process=claude` |
| `trufflehog filesystem` | one-off verified-secrets scan of a project tree | `trufflehog filesystem ~/projects --results=verified` |
| `infisical scan` | per-project / per-workflow secret scan | `infisical scan` (in repo) |
| `arch-audit` | full CVE list with rule details | `arch-audit --show-cve` |

None of these run on a timer. They exist for incident response and curiosity.

### What runs automatically vs manually

| Layer | Mode | Trigger |
|---|---|---|
| Bitwarden SSH agent | automatic | always-on, GUI-managed; 5min vault timeout |
| `agent-isolated` bwrap shim | automatic | every `claude` / `codex` / `opencode` invocation via PATH |
| gitleaks + infisical pre-commit | automatic | every `git commit` (all repos with template hook) |
| trufflehog pre-push | automatic | every `git push` (all repos with template hook) |
| arch-audit-gtk | automatic | 2–6h jittered + pacman post-tx hook |
| AdGuard | automatic | every DNS lookup on tailnet |
| firewalld | automatic | always-on |
| mitmproxy | manual | when you want to audit a session |
| trufflehog filesystem | manual | quarterly or post-incident |
| infisical scan | manual | per-workflow |
| `arch-audit-gtk` deep dive | manual | when tray pill goes yellow/red |

### Verifying the stack

```sh
~/bin/agent-isolated --self-test            # 26-check sandbox verification
stat -c '%a %n' ~/.bitwarden-ssh-agent.sock # expect 700
ssh-add -l                                  # expect your keys listed
git log --show-signature -1                 # expect "Good signature" via SSH
ls -la ~/.git-template/hooks/               # expect pre-commit + pre-push, both +x
gitleaks version && infisical --version     # both pre-commit scanners present
trufflehog --version                        # pre-push scanner present
dig @100.100.100.100 doubleclick.net        # expect 0.0.0.0 (AdGuard sinkhole)
pgrep -a arch-audit-gtk                     # expect process running (or check tray)
```

### Known gaps (as of 2026-05-11)

| Gap | Impact | Status |
|---|---|---|
| MCP servers not unified across Claude / Codex / OpenCode / Hermes | each has its own MCP config file; drift possible | open; chezmoi-template approach discussed, not yet implemented |
| MCP server periodic scan with [MCP-Scan](https://github.com/invariantlabs-ai/mcp-scan) | tool-poisoning / rug-pull detection not automated | deferred; run `npx @invariant-ai/mcp-scan` ad-hoc when adding a new MCP server |
| AUR `trufflehog-bin` PKGBUILD wrapper path bug | requires `sed` fix or pacman hook to re-patch after upgrades | mitigated by local pacman hook; bug to be reported to maintainer |
| `mitmproxy` CA cert not installed in any trust store | first-time use will fail TLS until cert is added | deferred; only matters when actually using mitmproxy |
| `StartLimitIntervalSec=` in waybar.service / dropdown-terminal.service | should be in `[Unit]` not `[Service]`; silently ignored where it is | known; 1-line fix per file |
| Pre-existing `MM` drift on `dot_claude/CLAUDE.md` | both source and target diverged; risk of silent overwrite on next `chezmoi apply` | open; resolve before next apply per the rules in CLAUDE.md |
| `~/.gnupg` cleanup | conditional rm-rf never confirmed | open; check `ls ~/.gnupg/` |
