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
# A box whose forwarded NAT egress is filtered (e.g. a dev VM behind a per-app
# host firewall) can still validate the fail-closed contract: probe a host-side
# veth HTTP target instead of the internet. Off-netns reachability through the
# veth exercises the same OUTPUT-hook egress the kill-switch must cut; only the
# rooted live test (which needs the real API) is skipped in this mode.
LOCAL_TARGET="${WARREN_NETNS_LOCAL_TARGET:-0}"

log()  { echo "[netns-tun] $*"; }
fail() { echo "[netns-tun] FAIL: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "must run as root (netns/veth/TUN/nft)"

# The host's default uplink, so NAT masquerades the namespace out the right NIC.
UPLINK="$(ip route show default | awk '/default/ {print $5; exit}')"
[ -n "$UPLINK" ] || fail "no default route on the host to NAT through"

cleanup() {
    set +e
    [ -n "${HTTP_PID:-}" ] && kill "$HTTP_PID" 2>/dev/null
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

if [ "$LOCAL_TARGET" = "1" ]; then
    egress_ok() { ip netns exec "$NS" curl -s -m 4 "http://$HOST_IP:8080/" >/dev/null; }
    # Bind the target to all addresses, not the veth IP: on a box with broken DNS
    # `http.server --bind <ip>` stalls in getaddrinfo, while 0.0.0.0 binds at once
    # and still serves $HOST_IP over the veth. The netns OUTPUT hook under test is
    # unaffected by which local address the target listens on.
    python3 -m http.server 8080 --bind 0.0.0.0 >/dev/null 2>&1 &
    HTTP_PID=$!
    for _ in $(seq 1 25); do egress_ok && break; sleep 0.2; done
    egress_ok || fail "the namespace cannot reach the host-side veth target"
    log "namespace reaches the local veth target (local-target mode)"
else
    egress_ok() { ip netns exec "$NS" curl -s -m 8 https://1.1.1.1/cdn-cgi/trace >/dev/null; }
    # Sanity: the namespace can reach the internet before we hand it to the test.
    egress_ok || fail "the namespace has no internet egress (NAT/uplink misconfigured)"
    log "namespace has internet egress"
fi

# ---------------------------------------------------------------------------
# PHASE 1: kill-switch crash recovery (mnemonic-free, real nft, real egress).
# Validates the fail-closed contract on the Linux backend inside the netns:
# a lockdown disconnect blocks egress, SIGKILL leaves the block holding, and
# both escape paths (the next daemon's explicit disconnect, `warrend revert`)
# restore egress. Runs on every dispatch, WARREN_MNEMONIC or not.
# ---------------------------------------------------------------------------
WARREND="$ROOT/native/warrend/target/release/warrend"
[ -x "$WARREND" ] || fail "build the daemon first: (cd native/warrend && cargo build --release)"
DRIVE="$ROOT/scripts/ci-warrend-drive.py"
SOCK="/tmp/warrend-netns-ci.sock"
DLOG="/tmp/warrend-netns-ci.log"

wait_for_socket() {
    for _ in $(seq 1 100); do [ -S "$SOCK" ] && return 0; sleep 0.1; done
    fail "daemon socket never appeared at $SOCK"
}

log "phase1: the help output documents the manual escape"
"$WARREND" --help | grep -q "revert" || fail "warrend --help does not document revert"

log "phase1: lockdown disconnect installs the block"
rm -f "$SOCK"
ip netns exec "$NS" "$WARREND" "$SOCK" 2>"$DLOG" &
DPID=$!
wait_for_socket
# The daemon exits the moment its single owner hangs up, so the drive holds
# the connection open: the SIGKILL below must land on a LIVE daemon, not on
# the corpse of a clean lockdown-conditional exit.
timeout 120 ip netns exec "$NS" python3 "$DRIVE" "$SOCK" lockdown-disconnect-hold &
HOLD_PID=$!
for _ in $(seq 1 300); do
    ip netns exec "$NS" nft list table inet warrend_lockdown >/dev/null 2>&1 && break
    kill -0 "$HOLD_PID" 2>/dev/null || break
    sleep 0.2
done
ip netns exec "$NS" nft list table inet warrend_lockdown >/dev/null \
    || fail "lockdown table missing after a lockdown disconnect (daemon log: $(cat "$DLOG"))"
if egress_ok; then fail "egress NOT blocked under lockdown"; fi

log "phase1: SIGKILL of the live daemon leaves the block holding (fail-closed)"
kill -0 "$DPID" 2>/dev/null || fail "daemon already exited before SIGKILL (owner hold broken)"
kill -9 "$DPID" 2>/dev/null || true
wait "$DPID" 2>/dev/null || true
kill "$HOLD_PID" 2>/dev/null || true
wait "$HOLD_PID" 2>/dev/null || true
ip netns exec "$NS" nft list table inet warrend_lockdown >/dev/null \
    || fail "the lockdown block did not survive SIGKILL"
if egress_ok; then fail "egress open after SIGKILL: the block must hold"; fi

log "phase1: warrend revert restores the network with no daemon"
ip netns exec "$NS" "$WARREND" revert || fail "warrend revert failed"
if ip netns exec "$NS" nft list table inet warrend_lockdown >/dev/null 2>&1; then
    fail "revert left the lockdown table installed"
fi
egress_ok || fail "egress not restored by warrend revert"

log "phase1: a stale engine block is held at startup, cleared by an explicit disconnect"
ip netns exec "$NS" nft -f - <<'RULES'
add table inet warrenguard_killswitch_os
flush table inet warrenguard_killswitch_os
table inet warrenguard_killswitch_os {
	chain output {
		type filter hook output priority 0; policy drop;
		oifname "lo" accept
	}
}
RULES
if egress_ok; then fail "the fabricated stale engine block does not block"; fi
rm -f "$SOCK"
ip netns exec "$NS" "$WARREND" "$SOCK" 2>"$DLOG" &
DPID=$!
wait_for_socket
grep -q "fail-closed" "$DLOG" || fail "startup did not report the held stale block"
ip netns exec "$NS" nft list table inet warrenguard_killswitch_os >/dev/null \
    || fail "startup must HOLD a stale block, not clear it"
timeout 60 ip netns exec "$NS" python3 "$DRIVE" "$SOCK" disconnect \
    || fail "disconnect drive failed (daemon log: $(cat "$DLOG"))"
if ip netns exec "$NS" nft list table inet warrenguard_killswitch_os >/dev/null 2>&1; then
    fail "an explicit disconnect did not clear the stale block"
fi
egress_ok || fail "egress not restored after the reconciling disconnect"
kill "$DPID" 2>/dev/null || true
wait "$DPID" 2>/dev/null || true
log "phase1 PASS: fail-closed persistence + both recovery paths validated (nft backend)"

# Lets a Flutter-less box (e.g. a dev VM) validate the kill-switch contract alone.
if [ "${WARREN_NETNS_PHASE1_ONLY:-0}" = "1" ]; then
    log "WARREN_NETNS_PHASE1_ONLY=1: stopping after phase 1"
    exit 0
fi
if [ "$LOCAL_TARGET" = "1" ]; then
    log "local-target mode: skipping the rooted TUN test (needs real egress)"
    exit 0
fi

log "running the rooted TUN test inside the namespace"

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
