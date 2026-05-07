# Agent Vault — credential broker for AI agents

This is the third leg of the secrets stack:

| Layer | Tool | Holds |
|---|---|---|
| Human passwords / 2FA / SSH key | **Bitwarden** | Master credentials, browser logins, recovery codes |
| App secrets / env vars | **Infisical** | `DATABASE_URL`, `JWT_SECRET`, anything code reads at runtime |
| **Brokered HTTPS API credentials** | **Agent Vault** *(this doc)* | LLM / MCP API keys — never exposed to the agent process |

Agent Vault is an HTTPS-credential proxy. Instead of giving Claude/Codex/Cursor your `OPENAI_API_KEY` as an env var, you give them a session token + a localhost proxy URL. The proxy substitutes the real key on outbound requests. The agent's process never sees the key, so it can't end up in transcripts, scrollback, or swap.

## Why we use it

Running a company → real keys with real rotation cost. Testing many models → not every agent runtime is fully trusted. Defense in depth is cheap when you set it up once at install time vs. retrofitting after a leak.

When this matters:
- Compromised tool/dependency reads `printenv` or env files (npm postinstall, supply chain).
- Agent transcript leaks (provider breach, accidental sharing of a session, model outputs containing env values).
- Backup of `~/` to a non-encrypted destination.

When this doesn't help (still need normal operational hygiene):
- Live malicious process talking to localhost:14321 with a stolen session token.
- Process memory dump while daemon is running.
- Non-HTTPS secrets (`DATABASE_URL`, JWT signing keys) — those still go through Infisical → direnv directly.

## Architecture summary

```
┌──────────────────────────────────────────────────────────┐
│ Agent Vault daemon (systemd --user, started at sway up)  │
│   Master password: TPM2-sealed credential                │
│   Listens: 127.0.0.1:14321 (control), :14322 (MITM)      │
│   Stores: AES-256-GCM credentials in ~/.agent-vault/     │
└──────────────────────────────────────────────────────────┘
                          ↑
                          │ HTTPS_PROXY routes through here
                          │
┌──────────────────────────────────────────────────────────┐
│ Agents (claude, codex, your code)                        │
│   AGENT_VAULT_SESSION_TOKEN=av_sess_…                    │
│   HTTPS_PROXY=http://127.0.0.1:14321                     │
│   SSL_CERT_FILE=~/.agent-vault/ca/ca.crt.pem               │
│                                                          │
│ When agent calls api.openai.com:                         │
│   1. Request goes through HTTPS_PROXY                    │
│   2. Daemon intercepts, looks up matching credential     │
│   3. Daemon adds Authorization header with real key      │
│   4. Forwards to upstream                                │
│   5. Real key never touches agent's process              │
└──────────────────────────────────────────────────────────┘
```

## Two passwords — keep them separate

Agent Vault's first-run flow sets **two distinct passwords**:

| | Master password | Admin password |
|---|---|---|
| **Purpose** | Wraps the DEK that encrypts credentials at rest | Authenticates `matas234@gmail.com` to the web UI |
| **When entered** | Every daemon start (TPM2-sealed → never typed in normal use) | Every login to http://127.0.0.1:14321 |
| **Storage** | TPM2-sealed in `~/.config/credstore.encrypted/`; backup in Bitwarden | Bitwarden, typed by you |
| **If lost** | DB unreadable. Restore from Bitwarden + reseal. | Email reset (if SMTP) or reset DB and start over. |

**Both should differ from your LUKS passphrase and your sudo password.** Generate fresh diceware for each via Bitwarden's Generator.

## Initial setup (one-time, after binary is installed)

You only run this once. Future reboots are fully automated.

### 1. Generate two fresh passphrases in Bitwarden

In Bitwarden Desktop's Generator (8+ words, separator `-`):

- Save first as a Secure Note named **`agent-vault-master`** — this is the encryption password (TPM2-sealed for daemon use; this entry is for disaster recovery only).
- Save second as a Login named **`agent-vault-admin`** with email `matas234@gmail.com` — this is what you type into the web UI.

Confirm both are saved before proceeding (recoverable).

### 2. Rotate the existing setup-time passwords

The daemon you set up interactively used the same password for both. Rotate to the fresh ones now.

```bash
# Stop any running daemon (port :14321 must be free)
pkill -f 'agent-vault server' 2>/dev/null

# Rotate the master (re-wraps the DEK; existing credentials stay encrypted
# under the same DEK — fast, no re-encryption needed)
agent-vault master-password change
# Prompts for current password, then new. Use Bitwarden values.

# Start the daemon temporarily so we can rotate the admin password too
agent-vault server -d                   # detach mode
sleep 2
agent-vault auth login --email matas234@gmail.com
agent-vault account change-password
# Prompts for current admin password, then new admin password.

# Stop again — systemd will own it from here
pkill -f 'agent-vault server'
```

### 3. Seal the new master password with TPM2

```bash
mkdir -p ~/.config/credstore.encrypted

# read -rs reads silently; password never appears in scrollback or shell history
read -rs PW
printf '%s' "$PW" | systemd-creds encrypt \
    --user \
    --with-key=tpm2+host \
    --name=agent-vault-master \
    - \
    ~/.config/credstore.encrypted/agent-vault-master.cred
unset PW

# Verify the sealed file exists and is non-empty
ls -la ~/.config/credstore.encrypted/agent-vault-master.cred

# Optional: confirm round-trip works (user-scope decrypt)
systemd-creds decrypt --user --name=agent-vault-master \
    ~/.config/credstore.encrypted/agent-vault-master.cred -
# Should print the password (only succeeds on this machine in current SB state).
```

The `--user` flag is **critical**: agent-vault.service runs under user@1000.service, and the
user systemd manager cannot read the system-scope host-key file at
`/var/lib/systemd/credential.secret` (root-owned mode 600). Without `--user`, the service
fails at startup with `status=243/CREDENTIALS` and `Scope mismatch` in the journal.

Equally critical: the `--name=agent-vault-master` value embedded in the sealed file MUST
match the credential ID in the unit's `LoadCredentialEncrypted=agent-vault-master:...`
declaration, AND the path `$CREDENTIALS_DIRECTORY/agent-vault-master` in `ExecStart`.
A mismatch produces `Name in credential doesn't match expectations` (also
`status=243/CREDENTIALS`). All three references must be the same string.

What `--with-key=tpm2+host` does:
- **tpm2**: ciphertext bound to PCR 7 (Secure Boot policy). Only this TPM in this Secure-Boot state can unseal.
- **+host**: combined with the user-scope host-key file — defeats the "exfiltrate the TPM chip and the .cred file to another machine" attack.

### 4. Enable the systemd user service

The unit lives in `dot_config/systemd/user/agent-vault.service` (chezmoi-tracked). It's already deployed to `~/.config/systemd/user/agent-vault.service` if you ran `chezmoi apply`.

```bash
systemctl --user daemon-reload
systemctl --user enable --now agent-vault.service

# Verify
systemctl --user status agent-vault.service --no-pager
curl -s http://127.0.0.1:14321/health
```

Healthy output ends with `Active: active (running)`. Daemon survives reboots.

### 5. Register credentials in the vault

Two parts per provider:
1. **Credential**: name → value mapping in vault storage
2. **Service**: hostname pattern + auth scheme + which credential key to use

Use either the web UI at http://127.0.0.1:14321 (friendlier first time) or the CLI
commands below. Vault is named `default`.

For each upstream:

```bash
# Anthropic — uses x-api-key header
agent-vault vault credential set ANTHROPIC_API_KEY=sk-ant-XXX --vault default
agent-vault vault service add \
    --host api.anthropic.com --description "Anthropic API" \
    --auth-type api-key --api-key-key ANTHROPIC_API_KEY --api-key-header x-api-key \
    --vault default

# OpenAI — Authorization: Bearer
agent-vault vault credential set OPENAI_API_KEY=sk-XXX --vault default
agent-vault vault service add \
    --host api.openai.com --description "OpenAI API" \
    --auth-type bearer --token-key OPENAI_API_KEY --vault default

# Exa — x-api-key header
# IF using stdio exa-mcp-server (npx variant): register host api.exa.ai
# IF using hosted HTTP MCP at mcp.exa.ai/mcp: register host mcp.exa.ai
# (both use x-api-key with the same key)
agent-vault vault credential set EXA_API_KEY=XXX --vault default
agent-vault vault service add \
    --host mcp.exa.ai --description "Exa hosted MCP" \
    --auth-type api-key --api-key-key EXA_API_KEY --api-key-header x-api-key \
    --vault default

# Gemini — x-goog-api-key header
agent-vault vault credential set GEMINI_API_KEY=XXX --vault default
agent-vault vault service add \
    --host generativelanguage.googleapis.com --description "Gemini API" \
    --auth-type api-key --api-key-key GEMINI_API_KEY --api-key-header x-goog-api-key \
    --vault default

# GitHub — Authorization: Bearer
agent-vault vault credential set GITHUB_TOKEN=ghp_XXX --vault default
agent-vault vault service add \
    --host "*.github.com" --description "GitHub API" \
    --auth-type bearer --token-key GITHUB_TOKEN --vault default

# Context7 (Upstash) hosted MCP — header CONTEXT7_API_KEY
# Optional: works on free tier without auth (rate-limited).
# Get a key from https://context7.com/dashboard for higher limits.
agent-vault vault credential set CONTEXT7_API_KEY=XXX --vault default
agent-vault vault service add \
    --host mcp.context7.com --description "Context7 MCP" \
    --auth-type api-key --api-key-key CONTEXT7_API_KEY --api-key-header CONTEXT7_API_KEY \
    --vault default
```

**Critical:** for each credential value, also save the original in Bitwarden as a
secure note named `agent-vault-cred:<NAME>` (e.g. `agent-vault-cred:ANTHROPIC_API_KEY`).
This is your disaster-recovery copy — if the local DB is ever lost, you re-register
from Bitwarden.

To avoid putting keys in shell history, prefer the silent-prompt helper:

```bash
av-add-credential ANTHROPIC_API_KEY     # prompts silently for value, registers
```

(Helper script lives at `~/.local/bin/av-add-credential` if installed.)

### 6. How agents use the vault — wrapper aliases

The official, supported pattern is the `agent-vault vault run` wrapper. It
creates a vault-scoped session, sets `HTTPS_PROXY` and CA trust on the wrapped
process **only** (your normal shell stays clean), and installs the Agent
Vault skill into claude. Token dies when the agent exits.

Aliases hide the wrapping (defined in `~/bin/zshaliases`):

```bash
alias claude='agent-vault vault run --vault default -- claude'
alias codex='agent-vault vault run --vault default -- codex'
alias opencode='agent-vault vault run --vault default -- opencode'
```

So you just type `claude` and the broker is in the loop transparently.

**Why we DON'T use a global `~/.envrc`** — early in setup we tried exporting the
proxy/CA env vars at shell scope via direnv. Don't do this. It poisons every
tool in that shell:

- `paru` / `makepkg` → AUR builds fail because `curl` can't verify github.com
  against the AV MITM cert (only valid for hosts AV has service rules for)
- `git push` → fails to fetch via HTTPS for the same reason
- `npm install`, `pip install`, anything that talks to a real public host

The wrapper is purpose-built to scope these vars to the wrapped process only.
Trust the wrapper; don't reinvent it with direnv.

If you genuinely need shell-scoped broker access for an ad-hoc command, prefix
that one command:

```bash
agent-vault vault run --vault default -- curl https://api.openai.com/v1/models
```

Or for a transient subshell:

```bash
agent-vault vault run --vault default -- $SHELL
```

**Global ~/.envrc** (loads when you `cd` into anywhere under $HOME).

The exact env vars to set are non-obvious — easiest to derive from what
`agent-vault vault run --vault default -- env` prints. Three things that
are easy to get wrong:

- `HTTPS_PROXY` is **`https://`** (the proxy itself uses TLS), not `http://`
- The proxy authenticates via **basic auth in the URL**: `<token>:<vault>@host:port`
- The MITM CA is **`~/.agent-vault/mitm-ca.pem`**, not `ca/ca.crt.pem` (different file)
- `curl` ignores `SSL_CERT_FILE`; needs `CURL_CA_BUNDLE`
- Node 24+ needs `NODE_USE_ENV_PROXY=1` for HTTPS_PROXY to be honored

Working `.envrc`:

```bash
__AV_TOKEN="$(agent-vault vault token --vault default 2>/dev/null)"
if [[ -n "$__AV_TOKEN" ]]; then
    export AGENT_VAULT_SESSION_TOKEN="$__AV_TOKEN"
    export AGENT_VAULT_ADDR=http://127.0.0.1:14321
    export AGENT_VAULT_VAULT=default
    export HTTPS_PROXY="https://${__AV_TOKEN}:default@127.0.0.1:14322"
    export HTTP_PROXY="https://${__AV_TOKEN}:default@127.0.0.1:14322"
    export NO_PROXY=localhost,127.0.0.1
    export SSL_CERT_FILE="$HOME/.agent-vault/mitm-ca.pem"
    export REQUESTS_CA_BUNDLE="$SSL_CERT_FILE"
    export CURL_CA_BUNDLE="$SSL_CERT_FILE"
    export NODE_EXTRA_CA_CERTS="$SSL_CERT_FILE"
    export DENO_CERT="$SSL_CERT_FILE"
    export GIT_SSL_CAINFO="$SSL_CERT_FILE"
    export NODE_USE_ENV_PROXY=1
fi
unset __AV_TOKEN
```

After editing run `direnv allow ~`. Then verify with:
`bash -c 'cd ~ && eval "$(direnv export bash)" && curl -sS https://mcp.exa.ai/mcp -X POST -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}" | head -3'`
— should return the tool list with no auth header set anywhere on your end.

After this, anywhere you `cd` into under `$HOME` will load these. `claude`, `codex`, npm, python — everything launched from there gets the proxy treatment.

**Per-project .envrc** (for projects that ALSO need non-HTTPS secrets like `DATABASE_URL`):

```bash
cd ~/myapp
cat > .envrc <<'EOF'
source_up                                                       # inherit ~/.envrc (proxy)
eval $(infisical export --format=dotenv-export --silent)        # add Infisical secrets
EOF
direnv allow
```

## Daily use

```bash
cd ~/anywhere
claude                  # transparently routed through the proxy
                        # printenv ANTHROPIC_API_KEY shows nothing
                        # but `curl https://api.anthropic.com/...` works
```

To verify routing actually works:

```bash
# Direct curl (no key set in env) — should still succeed because of the proxy
curl -v https://api.openai.com/v1/models 2>&1 | head -20
# Look for: "* Connected to 127.0.0.1 (127.0.0.1) port 14322"
```

## Recovery scenarios

Match the same playbook as your LUKS Phase 3.5 — TPM2 unsealing fails predictably and recoverably.

| Event | Result | Recovery |
|---|---|---|
| BIOS / firmware update | PCR 7 shifts → `agent-vault.service` fails | `journalctl --user -u agent-vault` confirms TPM error → re-run **Step 3** (re-seal) with the password from Bitwarden |
| Re-roll Secure Boot keys (sbctl reset) | PCR 7 shifts | Same as above |
| `/var/lib/systemd/credential.secret` lost | Host-key gone | Same as above |
| Daemon panic / OOM | systemd restarts after 5s | Auto |
| Move SSD to a different machine | TPM2 doesn't recognize | Re-seal on new machine — credentials stay valid, only the wrapping key changes |
| **Lose Bitwarden vault** | No master password recovery path | DB unreadable. Wipe `~/.agent-vault/`, start over. Same risk profile as losing your LUKS recovery passphrase. |

## MCPs through Agent Vault

MCPs are **clients**, not entities Agent Vault registers. The picture:

```
shell (HTTPS_PROXY set by direnv)
   ↓ inherits
claude
   ↓ spawns subprocess (env inherited)
exa-mcp-server                       ← not registered in Agent Vault
   ↓ HTTPS call
api.exa.ai                           ← THIS is the service. AV intercepts here.
```

Register the upstream API the MCP talks to as a service in Agent Vault, and
the MCP transparently benefits because it inherits HTTPS_PROXY from claude.

### Auth-header override

Agent Vault **overrides** any auth header the MCP sends. So if a MCP requires
its own credential env var to be set (many do — they check at startup before
making any HTTP call), set it to a clear placeholder string instead of the
real key:

```json
"mcpServers": {
  "exa": {
    "command": "...npx...",
    "args": ["-y", "exa-mcp-server"],
    "env": {
      "EXA_API_KEY": "injected-by-agent-vault"
    }
  }
}
```

The MCP starts (env check passes), sends the garbage value as the auth header,
Agent Vault replaces it with the real credential at the proxy boundary, the
real value reaches the upstream. The garbage never leaves the machine, and
the real value never enters the MCP's process — even if the MCP logs its env,
no real key leaks.

### Caveats

- **HTTPS_PROXY-respecting libraries only.** Most modern HTTP clients (Node's
  `fetch`, Python `requests`/`httpx`, Go's `net/http`, Rust's `reqwest`) honor
  HTTPS_PROXY by default. Some Go binaries with bundled CAs and Rust apps with
  rustls hardcoded roots bypass it — those won't be intercepted.
- **Streaming / SSE / WebSocket.** Most work because they're TCP+TLS underneath
  and the proxy handles them, but exotic protocols may not.
- **The MCP must inherit claude's env.** If you spawn the MCP with `env-clear`
  semantics (rare; some sandboxing setups), HTTPS_PROXY is dropped → Agent
  Vault is bypassed → MCP needs the real env var.

## Browser MCPs need to bypass AV

Agent Vault is a **credential broker**, not a generic egress proxy. It blocks
HTTPS requests to hosts that don't have a registered service (security
feature — prevents an agent from being tricked into exfiltrating to an
arbitrary domain).

Browser MCPs (playwright, chrome-devtools) navigate to *arbitrary* websites —
that's the whole point. If they inherit `HTTPS_PROXY` from a claude wrapped
by AV, every navigation to news.ycombinator.com / docs.example.com / etc.
gets blocked with `ERR_EMPTY_RESPONSE`.

Fix: launch browser MCPs with the proxy env unset. In `~/.claude.json`:

```json
"playwright": {
  "type": "stdio",
  "command": "env",
  "args": [
    "-u", "HTTPS_PROXY", "-u", "HTTP_PROXY",
    "npx", "-y", "@playwright/mcp@latest",
    "--executable-path", "/usr/bin/chromium",
    "--headless"
  ]
}
```

The `env -u` strips proxy vars before exec'ing the actual MCP. The subprocess
gets the rest of claude's environment but no AV proxy → direct internet.

Apply the same pattern to any future "general browsing" MCP. Credentialed
MCPs (talk to ONE known upstream API) should keep AV in the loop; general
browsing tools should bypass.

## Curl-specific gotcha

When the proxy URL is `https://...` (it is in our setup), curl validates
the **proxy's** TLS cert separately from the upstream's. None of `SSL_CERT_FILE`,
`CURL_CA_BUNDLE`, or `REQUESTS_CA_BUNDLE` cover the proxy connection — those
only apply to upstream. To verify the proxy's MITM cert, curl needs:

```bash
curl --proxy-cacert "$SSL_CERT_FILE" --cacert "$SSL_CERT_FILE" ...
```

There's no env-var equivalent for `--proxy-cacert` in current curl. This
**only affects curl CLI** — Node (`NODE_EXTRA_CA_CERTS`), Python requests
(`REQUESTS_CA_BUNDLE`), Deno (`DENO_CERT`), and most other HTTP clients
honor their proxy CA via the same env var that covers upstream certs. So
agents (claude, codex) work transparently; curl tests need the explicit flag.

For convenience, alias:

```bash
alias curlav='curl --cacert "$SSL_CERT_FILE" --proxy-cacert "$SSL_CERT_FILE"'
```

## Operational notes

- **The MITM proxy port is 14322**, not 14321. 14321 is the control/management API; 14322 is the HTTP_PROXY target. Easy to confuse.
- **Session tokens are short-lived** by default. The global `.envrc` mints a fresh one each shell — fine for interactive use. For long-running daemons that span sessions, use `agent-vault vault token --vault default --ttl=24h` or similar.
- **CA cert trust** — anything that does its own TLS pinning (some Go binaries with bundled CAs, Rust apps with rustls hardcoded roots) bypasses `SSL_CERT_FILE` and the proxy can't intercept. Test with each new tool.
- **DATABASE_URL and friends are NOT brokered.** Agent Vault only handles HTTPS APIs. Connection strings still go through Infisical → direnv as plain env vars.

## Files this setup creates

| Path | Purpose | chezmoi-tracked? |
|---|---|---|
| `~/.local/bin/agent-vault` | Binary | No (downloaded once) |
| `~/.agent-vault/agent-vault.db` | Encrypted credential DB | No (regenerated on rotation) |
| `~/.agent-vault/ca/ca.crt.pem` | MITM proxy CA cert | No (regenerated on rotation) |
| `~/.config/credstore.encrypted/agent-vault-master.cred` | TPM2-sealed master pw | No (machine-specific, can't be portable) |
| `~/.config/systemd/user/agent-vault.service` | Service unit | **Yes** — `dot_config/systemd/user/agent-vault.service` |
| `~/.envrc` | Global proxy env loader | Worth tracking — add to chezmoi later |

## See also

- `RUNBOOK.md` Phase 9.95 — Infisical + direnv ergonomic path (where this slots in)
- `RUNBOOK.md` Phase 3.5 — TPM2 LUKS auto-unlock (same trust chain as this credential seal)
- [Agent Vault docs](https://infisical.com/docs/agent-vault)
