#!/usr/bin/env bash
# Cross-distro package layer for the agent stack. Sourced by bootstrap.sh.
# Maps the few system-package deps to pacman / apt / dnf, and checks the one
# hard cross-distro gotcha: unprivileged user namespaces (bwrap needs them).
set -euo pipefail

# System deps that are NOT mise-managed (universally packaged):
#   bubblewrap   — the sandbox (agent-isolated)
#   github-cli   — gh, the git credential helper + auth
#   openssh      — ssh-keygen / ssh-agent (signing + git-sign-agent)
#   git, curl    — base
# Per-distro package names where they differ.
detect_distro() {
    . /etc/os-release 2>/dev/null || true
    case "${ID:-}:${ID_LIKE:-}" in
        arch*|*:*arch*)        echo arch ;;
        debian*|ubuntu*|*:*debian*) echo debian ;;
        fedora*|rhel*|*:*fedora*|*:*rhel*) echo fedora ;;
        *) echo "unknown" ;;
    esac
}

install_system_deps() {
    local distro; distro="$(detect_distro)"
    case "$distro" in
        arch)   sudo pacman -S --needed --noconfirm bubblewrap github-cli openssh git curl ;;
        debian) sudo apt-get update && sudo apt-get install -y bubblewrap gh openssh-client git curl ;;
        fedora) sudo dnf install -y bubblewrap gh openssh-clients git curl ;;
        *) echo "distro.sh: unsupported distro; install manually: bubblewrap gh openssh git curl" >&2; return 1 ;;
    esac
}

# bwrap needs unprivileged user namespaces. Debian/Ubuntu (and some hardened
# kernels) restrict them via AppArmor/sysctl — detect and print the exact fix
# rather than letting agent-isolated fail cryptically later.
check_userns() {
    if ! unshare --user --map-root-user true 2>/dev/null; then
        echo "distro.sh: unprivileged user namespaces are RESTRICTED — bwrap will fail." >&2
        echo "  Debian/Ubuntu fix:  sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0" >&2
        echo "  (persist in /etc/sysctl.d/). Some distros need: sudo sysctl -w kernel.unprivileged_userns_clone=1" >&2
        return 1
    fi
}
