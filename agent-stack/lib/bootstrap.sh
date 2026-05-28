#!/usr/bin/env bash
# Idempotent agent-stack bootstrap. Run via `mise run bootstrap` from
# agent-stack/. Safe to re-run. Steps that need a human (gh login, GitHub UI,
# TPM2 seal) are printed, not faked.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/distro.sh"

say() { printf '\n\033[1;34m== %s\033[0m\n' "$*"; }
todo() { printf '  \033[33m→ TODO (you):\033[0m %s\n' "$*"; }

say "1/6 System packages (bubblewrap, gh, openssh, git, curl)"
install_system_deps
check_userns || todo "Fix user namespaces (above) before agents can sandbox."

say "2/6 Pinned tools via mise"
mise install   # node, bun, infisical, cc-safety-net per mise.toml

say "3/6 Deploy runtime files (chezmoi)"
chezmoi apply  # agent-isolated, _agent-shim, hooks, mcp.yaml→mcp-sync, units

say "4/6 Commit-signing: dedicated sign-only key + agent"
if [[ ! -f "$HOME/.ssh/id_ed25519_sign" ]]; then
    ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519_sign" -C "git signing key" -N ''
    todo "Register ~/.ssh/id_ed25519_sign.pub on GitHub as a *Signing key* (not Authentication)."
fi
systemctl --user daemon-reload
systemctl --user enable --now git-sign-agent.service
git config --global gpg.format ssh
git config --global commit.gpgsign true
git config --global gpg.ssh.program "$HOME/bin/git-sign-ssh"
git config --global gpg.ssh.allowedSignersFile "$HOME/.config/git/allowed_signers"
git config --global user.signingkey "$(cat "$HOME/.ssh/id_ed25519_sign.pub")"
grep -qF "$(cut -d' ' -f2 "$HOME/.ssh/id_ed25519_sign.pub")" "$HOME/.config/git/allowed_signers" 2>/dev/null \
    || echo "$(git config user.email) $(cat "$HOME/.ssh/id_ed25519_sign.pub")" >> "$HOME/.config/git/allowed_signers"

say "5/6 Push auth: HTTPS via gh credential helper"
git config --global url."https://github.com/".insteadOf git@github.com:
git config --global --add url."https://github.com/".insteadOf ssh://git@github.com/
if gh auth status >/dev/null 2>&1; then
    gh auth setup-git
else
    todo "Run: gh auth login   (HTTPS; 'Authenticate Git with your GitHub credentials? Yes')"
fi

say "6/6 Secrets (manual / external)"
todo "agent-vault: install binary + TPM2-seal master per ../arch-install/AGENT-VAULT.md, then: systemctl --user enable --now agent-vault"
todo "Infisical: 'infisical login' (or machine-identity token) so per-agent API keys provision."

say "Verifying"
bash "$HERE/doctor.sh" || true
