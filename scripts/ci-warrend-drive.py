#!/usr/bin/env python3
"""Drive a warrend IPC socket for the netns CI crash-recovery phases.

Speaks the daemon's length-prefixed JSON protocol directly so the
mnemonic-free phases need no Flutter runtime. The mnemonic below is the
standard public BIP39 test vector, not an account secret: configure only
derives an identity locally, no network call is made.
"""

import json
import socket
import struct
import sys

MNEMONIC = ("abandon " * 11) + "about"
API_BASE = "https://api.warrenbrowse.com"
SERVER_PIN = "4c2c9253c426ae4db4cc88703f9ac802a020420c7fea6479c87af530ada72c3e"


def send(sock, obj):
    data = json.dumps(obj).encode()
    sock.sendall(struct.pack(">I", len(data)) + data)


def recv_event(sock):
    header = sock.recv(4, socket.MSG_WAITALL)
    if len(header) < 4:
        raise SystemExit("daemon closed the socket mid-conversation")
    (length,) = struct.unpack(">I", header)
    payload = sock.recv(length, socket.MSG_WAITALL)
    return json.loads(payload)


def expect_state(sock, state):
    event = recv_event(sock)
    if event.get("type") != "state" or event.get("state") != state:
        raise SystemExit(f"expected state {state!r}, daemon sent: {event!r}")


def main():
    socket_path, mode = sys.argv[1], sys.argv[2]
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(30)
    sock.connect(socket_path)
    if mode == "lockdown-disconnect":
        send(
            sock,
            {
                "type": "configure",
                "mnemonic": MNEMONIC,
                "apiBase": API_BASE,
                "serverPubkeyPin": SERVER_PIN,
                "lockdown": True,
            },
        )
        # A successful configure sends no event; the next events answer the
        # disconnect. A configure failure surfaces here as an unexpected
        # error event instead of draining.
        send(sock, {"type": "disconnect"})
        expect_state(sock, "draining")
        expect_state(sock, "disconnected")
    elif mode == "disconnect":
        send(sock, {"type": "disconnect"})
        expect_state(sock, "draining")
        expect_state(sock, "disconnected")
    else:
        raise SystemExit(f"unknown mode {mode!r}")
    sock.close()
    print(f"drive {mode}: ok")


if __name__ == "__main__":
    main()
