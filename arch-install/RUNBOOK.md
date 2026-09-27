# Workstation recovery runbook

## Restore dotfiles

```bash
git clone https://github.com/NullSense/dotfiles.git ~/.dotfiles
~/.dotfiles/install.sh --install
~/.dotfiles/scripts/bootstrap-omarchy.sh
systemctl --user daemon-reload
```

Run `~/.dotfiles/install.sh --check` before enabling services. Existing
conflicting files are preserved under `~/.local/state/dotfiles-backups/`.

## Restore commit signing and GitHub authentication

Commit signing uses a dedicated key at `~/.ssh/id_ed25519_sign`, loaded by
`git-sign-agent.service`. `~/bin/git-sign-ssh` directs signing to that service's
socket independently of the interactive SSH authentication agent. Register
the public key with GitHub as a **Signing key**; keep the private key outside
this repository and never authorize it for server login.

Restore the existing signing key from private backup before starting the
service. If replacing a lost key, update `user.signingkey` in `~/.gitconfig`,
`~/.config/git/allowed_signers`, and the registered GitHub signing key together.
The service loads its key non-interactively; its setup is documented in
`home/.config/systemd/user/git-sign-agent.service`.

```bash
systemctl --user enable --now git-sign-agent.service
systemctl --user is-active git-sign-agent.service
git config --global --get gpg.ssh.program
git -C ~/.dotfiles log --show-signature -1
```

The signing program should resolve to `~/bin/git-sign-ssh`. For
`Couldn't find key in agent`, inspect `git-sign-agent.service` and confirm
that the wrapper is configured before changing the interactive SSH agent.
The log command checks the existing commit's signature; it does not prove
that a new commit can be signed.

GitHub HTTPS authentication is separate: `~/.gitconfig` uses
`gh auth git-credential`. Check `gh auth status`; on a fresh installation,
complete `gh auth login` with HTTPS and then `gh auth setup-git`. If an
interactive session reports an invalid keyring token, check that the desktop
keyring was unlocked at login before replacing credentials.

## Restore credential services

Agent Vault requires three user-scoped encrypted credentials:

- `agent-vault-master`
- `infisical-client-id`
- `infisical-client-secret`

Hermes requires encrypted credentials for its Agent Vault identity, Home
Assistant WebSocket token, and LiteLLM virtual key. Never place plaintext
values in this repository, unit files, or process arguments.

After restoring encrypted credentials:

```bash
systemctl --user enable --now agent-vault.service
systemctl --user restart hermes-gateway.service
systemctl --user is-active agent-vault.service hermes-gateway.service
agent-vault vault credential-store show hermes
```

The `hermes` vault must report `Credential store: infisical` and a healthy
last sync. The legacy `default` vault remains builtin for interactive tools.

## MCP gateway

LiteLLM is the single MCP gateway. Its inventory is
`~/.config/litellm/config-mcp.yaml`; clients point only to
`http://127.0.0.1:4001/mcp/`. The MCP instance must stay unauthenticated and
bound exclusively to loopback. Restart and verify it with:

```bash
systemctl --user restart litellm-mcp.service
ss -ltn 'sport = :4001'
codex mcp list
hermes mcp list
```

## System tuning

`scripts/install-system-tuning.sh` writes reviewed files under `/etc` using
sudo. It is intentionally explicit and is never run by the dotfile installer.
It also installs the NetworkManager Docker-bridge exclusions, enables
`systemd-resolved`, and restarts Tailscale after the resolver stub is active.

After applying it, verify the network without a standalone probe script:

```bash
readlink -f /etc/resolv.conf
resolvectl status
tailscale status
ip -brief address show docker0
systemctl --user is-active litellm.service llama-swap.service
```

## Safety

- Repository pushes are public and secret-scanned.
- Agent binaries run directly; no custom wrapper or outer bubblewrap layer is
  part of this setup.
- Do not restore old `agent-isolated`, URL opener, or per-agent launcher files
  from Git history.
