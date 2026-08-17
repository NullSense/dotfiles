# ~/.zshenv — sourced by EVERY zsh (interactive, login, cron, systemd user, IDE).
# Keep minimal; put interactive stuff in dot_zshrc.

# Bitwarden Desktop runs an SSH agent on this socket when its
# Settings → SSH Agent toggle is enabled. Putting it in zshenv (not zshrc)
# means git operations launched from non-interactive contexts (IDEs, cron,
# systemd user services) also use the agent, not whatever stale ssh-agent
# happens to be running.
# An inherited socket (`ssh -A` agent forwarding, or the ~/.ssh/agent.sock
# symlink tmux points at) wins when it's live — that's the remote-work path,
# where Bitwarden Desktop has no GUI to unlock. Note the Bitwarden socket FILE
# survives the app exiting, so testing `-S` on it alone would happily select a
# dead agent. Local logins have SSH_AUTH_SOCK unset and fall straight through.
if [ -n "$SSH_AUTH_SOCK" ] && [ "$SSH_AUTH_SOCK" != "$HOME/.bitwarden-ssh-agent.sock" ] && [ -S "$SSH_AUTH_SOCK" ]; then
    : # keep the inherited/forwarded agent
elif [ -S "$HOME/.bitwarden-ssh-agent.sock" ]; then
    export SSH_AUTH_SOCK="$HOME/.bitwarden-ssh-agent.sock"
fi

# Suppress zoxide's "init me last" doctor warning.
# zoxide IS init'd last in zshrc, but mise's hook-env runs on every chpwd
# (registered AFTER zoxide via mise's precmd), so zoxide's doctor sees a
# "later" hook and nags every shell. False positive — silence it.
export _ZO_DOCTOR=0

# Plannotator's CLI does not persist a browser in ~/.plannotator/config.json;
# it reads PLANNOTATOR_BROWSER (or a one-shot --browser flag). Pin the live
# Helium launcher so agent-started review sessions never fall back to Chromium.
export PLANNOTATOR_BROWSER="$HOME/.local/bin/helium"

# Omarchy — pinned to a release tag at ~/.local/share/omarchy.
# OMARCHY_PATH is read by every omarchy-* script for theme paths, defaults,
# and template rendering. PATH gets the omarchy bin dir prepended so all
# 273 omarchy-* helpers are callable from any shell, including non-
# interactive contexts (Hyprland exec-once, systemd user units, etc.).
if [ -d "$HOME/.local/share/omarchy" ]; then
    export OMARCHY_PATH="$HOME/.local/share/omarchy"
    case ":$PATH:" in
        *":$OMARCHY_PATH/bin:"*) ;;
        *) export PATH="$OMARCHY_PATH/bin:$PATH" ;;
    esac
fi

# Personal ~/bin (hand-rolled scripts: brightness-ctl, voice-*, helium-update,
# etc.) on PATH ahead of system bins — these wrap or override system tools.
case ":$PATH:" in
    *":$HOME/bin:"*) ;;
    *) export PATH="$HOME/bin:$PATH" ;;
esac

# Model-server wrappers (llama-* driven by llama-swap) live in ~/bin/llm-servers to
# keep ~/bin uncluttered; kept on PATH so they remain callable by name.
case ":$PATH:" in
    *":$HOME/bin/llm-servers:"*) ;;
    *) export PATH="$HOME/bin/llm-servers:$PATH" ;;
esac

# LM Studio CLI (lms). Single canonical location — was previously triplicated
# by the LM Studio installer in zshrc, bashrc, and profile.
if [ -d "$HOME/.lmstudio/bin" ]; then
    case ":$PATH:" in
        *":$HOME/.lmstudio/bin:"*) ;;
        *) export PATH="$PATH:$HOME/.lmstudio/bin" ;;
    esac
fi

# Agent Vault is per-process via `agent-vault vault run`, not blanket-exported
# in shells, so HTTPS_PROXY / NO_PROXY are not set here.
. "$HOME/.cargo/env"
