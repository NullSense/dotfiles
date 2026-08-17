#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
SOURCE_ROOT="$REPO_ROOT/arch-install/etc/NetworkManager/conf.d"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

grep -Fxq '[keyfile]' "$SOURCE_ROOT/10-docker-bridges-unmanaged.conf" \
    || fail "Docker bridge config has no [keyfile] section"
grep -Fxq 'unmanaged-devices=interface-name:=docker0;interface-name:br-*' \
    "$SOURCE_ROOT/10-docker-bridges-unmanaged.conf" \
    || fail "Docker bridge unmanaged-device policy is missing"
grep -Fxq 'dns=systemd-resolved' "$SOURCE_ROOT/20-systemd-resolved.conf" \
    || fail "NetworkManager is not configured for systemd-resolved"
bash -n "$REPO_ROOT/scripts/install-network-coexistence.sh"

if [[ ${1:-} != --live ]]; then
    echo "PASS: network coexistence sources"
    exit 0
fi

cmp -s "$SOURCE_ROOT/10-docker-bridges-unmanaged.conf" \
    /etc/NetworkManager/conf.d/10-docker-bridges-unmanaged.conf \
    || fail "live Docker bridge config differs from the repository source"
cmp -s "$SOURCE_ROOT/20-systemd-resolved.conf" \
    /etc/NetworkManager/conf.d/20-systemd-resolved.conf \
    || fail "live resolver config differs from the repository source"
systemctl is-active --quiet systemd-resolved.service \
    || fail "systemd-resolved is not active"
[[ $(readlink -f /etc/resolv.conf) == /run/systemd/resolve/stub-resolv.conf ]] \
    || fail "/etc/resolv.conf does not use the systemd-resolved stub"

mapfile -t bridge_network_ids < <(docker network ls --filter driver=bridge -q)
while IFS=$'\t' read -r bridge_name gateway subnet; do
    [[ -n "$bridge_name" && -n "$gateway" && -n "$subnet" ]] || continue
    prefix=${subnet#*/}
    ip -o -4 address show dev "$bridge_name" | awk '{print $4}' | grep -Fxq "$gateway/$prefix" \
        || fail "$bridge_name is missing Docker gateway $gateway/$prefix"
    [[ $(nmcli -g GENERAL.STATE device show "$bridge_name") == '10 (unmanaged)' ]] \
        || fail "$bridge_name is still managed by NetworkManager"
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

[[ $(tailscale status --json | jq -r '.BackendState') == Running ]] \
    || fail "Tailscale is not running"
[[ $(tailscale status --json | jq -r '.ExitNodeStatus == null') == true ]] \
    || fail "an exit node is unexpectedly active"
getent ahostsv4 archlinux.org >/dev/null \
    || fail "ordinary DNS resolution failed"
self_dns=$(tailscale status --json | jq -r '.Self.DNSName | rtrimstr(".")')
getent ahostsv4 "$self_dns" >/dev/null \
    || fail "Tailscale MagicDNS resolution failed"

echo "PASS: live Docker, uplink DNS, and Tailscale coexistence"
