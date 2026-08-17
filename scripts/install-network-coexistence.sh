#!/usr/bin/env bash
# Install and apply the NetworkManager/systemd-resolved configuration needed
# for Docker bridges, ordinary uplinks, and Tailscale to coexist.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
SOURCE_ROOT="$REPO_ROOT/arch-install/etc/NetworkManager/conf.d"

if (( EUID != 0 )); then
    if ! sudo -n true 2>/dev/null; then
        echo "install-network-coexistence: run 'sudo -v' once, then retry" >&2
        exit 1
    fi
    exec sudo -n "$0" "$@"
fi

install -d -o root -g root -m 0755 /etc/NetworkManager/conf.d
install -o root -g root -m 0644 \
    "$SOURCE_ROOT/10-docker-bridges-unmanaged.conf" \
    /etc/NetworkManager/conf.d/10-docker-bridges-unmanaged.conf
install -o root -g root -m 0644 \
    "$SOURCE_ROOT/20-systemd-resolved.conf" \
    /etc/NetworkManager/conf.d/20-systemd-resolved.conf

# tailscaled caches its DNS-manager choice. Stop it before replacing
# resolv.conf so it cannot rewrite the new stub link using the old mode.
systemctl stop tailscaled.service
systemctl enable --now systemd-resolved.service
ln -sfn /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
systemctl restart NetworkManager.service

# NetworkManager already removed gateway addresses from existing Docker
# bridges before this fix. Restore them from Docker's authoritative IPAM data
# without restarting the daemon or any containers.
mapfile -t bridge_network_ids < <(docker network ls --filter driver=bridge -q)
while IFS=$'\t' read -r bridge_name gateway subnet; do
    [[ -n "$bridge_name" && -n "$gateway" && -n "$subnet" ]] || continue
    prefix=${subnet#*/}
    address="$gateway/$prefix"
    if ip link show dev "$bridge_name" >/dev/null 2>&1 \
        && ! ip -o -4 address show dev "$bridge_name" | awk '{print $4}' | grep -Fxq "$address"; then
        ip address add "$address" dev "$bridge_name"
    fi
done < <(
    docker network inspect "${bridge_network_ids[@]}" \
        | jq -r '.[]
            | select(.IPAM.Config[0].Gateway != null)
            | [
                (if .Name == "bridge" then "docker0"
                 elif .Options["com.docker.network.bridge.name"] != null
                 then .Options["com.docker.network.bridge.name"]
                 else "br-" + (.Id[0:12]) end),
                .IPAM.Config[0].Gateway,
                .IPAM.Config[0].Subnet
              ]
            | @tsv'
)

# Preserve the existing no-exit-node preference while restoring Tailscale and
# its split-DNS integration.
systemctl start tailscaled.service
tailscale set --accept-dns=true
tailscale up

echo "Network coexistence configuration installed."
