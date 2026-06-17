#!/usr/bin/env bash
#
# ci-netns-linux-tun.sh - run the rooted Mode B (system-VPN TUN) test inside a
# Linux network namespace, so the daemon's split-default route + nft killswitch
# are confined to the namespace and never touch the runner's host routing.
#
# WHY A NETNS
# -----------
# The rooted test makes the `warrend` daemon capture ALL traffic by rewriting the
# default route and installing a killswitch. Doing that on the host of a shared
# self-hosted runner would hijack the runner's own connectivity and break the
# job (and every other job on that machine). A network namespace gives the daemon
# its own routing table + nft table; with a veth pair + NAT it still reaches the
# real exit, the discovery API and 1.1.1.1, but the blast radius is the namespace.
#
# This mirrors warren-core's bench/scripts/netns-e2e-dataplane.sh, adapted for the
# SDK daemon (which talks to a REAL exit over the internet, hence the NAT egress
# the hermetic core harness does not need).
#
# STATUS: EXPERIMENTAL, NOT YET VALIDATED on a real Linux runner. The Linux TUN
# datapath in the engine is compile-checked + unit-tested but, unlike macOS, has
# not been live-validated end to end. Run it, read the output, fix what breaks.
#
# REQUIREMENTS: Linux, root, `ip`/`iptables`/`nft`, the built engine dylib
# (native/warren_sdk_frb) + daemon (native/warrend), fvm Flutter, and the WARREN_*
# env (WARREN_ROOTED=1, WARREN_MNEMONIC, WARREN_API_BASE, WARREN_SERVER_PIN). With
# no WARREN_MNEMONIC the test self-skips (still green).
#
# Usage (as root): sudo -E scripts/ci-netns-linux-tun.sh
set -euo pipefail

# `fvm flutter` locally (the repo pins Flutter via fvm); CI sets FLUTTER=flutter
# because subosito/flutter-action installs the SDK directly.
FLUTTER="${FLUTTER:-fvm flutter}"
NS="warren-tun-ci"
VETH_H="wtci-h"
VETH_N="wtci-n"
HOST_IP="172.31.9.1"
NS_IP="172.31.9.2"
NS_CIDR="172.31.9.0/30"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

log()  { echo "[netns-tun] $*"; }
fail() { echo "[netns-tun] FAIL: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "must run as root (netns/veth/TUN/nft)"

# The host's default uplink, so NAT masquerades the namespace out the right NIC.
UPLINK="$(ip route show default | awk '/default/ {print $5; exit}')"
[ -n "$UPLINK" ] || fail "no default route on the host to NAT through"

cleanup() {
    set +e
    iptables -t nat -D POSTROUTING -s "$NS_CIDR" -o "$UPLINK" -j MASQUERADE 2>/dev/null
    iptables -D FORWARD -i "$VETH_H" -j ACCEPT 2>/dev/null
    iptables -D FORWARD -o "$VETH_H" -j ACCEPT 2>/dev/null
    ip netns pids "$NS" 2>/dev/null | xargs -r kill -9 2>/dev/null
    ip netns del "$NS" 2>/dev/null
    ip link del "$VETH_H" 2>/dev/null
    rm -rf "/etc/netns/$NS"
}
trap cleanup EXIT

log "creating netns $NS (veth + NAT via $UPLINK)"
ip netns add "$NS"
ip link add "$VETH_H" type veth peer name "$VETH_N"
ip link set "$VETH_N" netns "$NS"
ip addr add "$HOST_IP/30" dev "$VETH_H"
ip link set "$VETH_H" up
ip netns exec "$NS" ip link set lo up
ip netns exec "$NS" ip addr add "$NS_IP/30" dev "$VETH_N"
ip netns exec "$NS" ip link set "$VETH_N" up
ip netns exec "$NS" ip route add default via "$HOST_IP"

# NAT the namespace to the internet so the daemon can reach the real exit.
echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -t nat -A POSTROUTING -s "$NS_CIDR" -o "$UPLINK" -j MASQUERADE
iptables -A FORWARD -i "$VETH_H" -j ACCEPT
iptables -A FORWARD -o "$VETH_H" -j ACCEPT

# DNS for the namespace (the API base is resolved before the tunnel is up).
mkdir -p "/etc/netns/$NS"
echo "nameserver 1.1.1.1" > "/etc/netns/$NS/resolv.conf"

# Sanity: the namespace can reach the internet before we hand it to the test.
ip netns exec "$NS" curl -s -m 10 https://1.1.1.1/cdn-cgi/trace >/dev/null \
    || fail "the namespace has no internet egress (NAT/uplink misconfigured)"
log "namespace has internet egress; running the rooted TUN test inside it"

# Run the whole test inside the namespace: discovery (in-process engine), the
# daemon (its route+killswitch land in THIS namespace), and the egress probe.
cd "$ROOT/packages/warren_sdk"
# shellcheck disable=SC2086  # $FLUTTER may be "fvm flutter" (two words) by design.
ip netns exec "$NS" env \
    "PATH=$PATH" \
    "WARREN_ROOTED=${WARREN_ROOTED:-1}" \
    "WARREN_MNEMONIC=${WARREN_MNEMONIC:-}" \
    "WARREN_API_BASE=${WARREN_API_BASE:-https://api.warrenbrowse.com}" \
    "WARREN_SERVER_PIN=${WARREN_SERVER_PIN:-}" \
    $FLUTTER test test/daemon_tun_rooted_live_test.dart --concurrency=1
