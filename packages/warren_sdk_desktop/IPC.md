# Warren desktop daemon IPC

Mode B (system VPN) runs the privileged datapath out of process, the same shape
as Mullvad and Tailscale: a long-lived **Warren daemon** owns the TUN device,
routing and killswitch; the app drives it over a local socket. This document is
the contract a daemon must implement; `warren_sdk_desktop` is the app-side
client.

## Transport

- Linux/macOS: a Unix domain socket, owned `root:root`, mode `0600` (or a group
  the user is in). Windows: a named pipe with an equivalent ACL.
- The socket path is fixed per OS (for example `/run/warren/warrend.sock`).
- Framing: each message is a 4-byte big-endian length prefix followed by that
  many bytes of UTF-8 JSON. See `FrameCodec` / `FrameReader`.

## Messages

App to daemon (requests):

| `type` | Fields | Meaning |
|---|---|---|
| `configure` | `mnemonic`, `apiBase`, `serverPubkeyPin`, `multihopRootPin?` | Bind identity + account API. The daemon derives and zeroizes the key; it never logs the mnemonic. |
| `connect` | `exitPubkeyHex`, `dnsOverTunnel` | Bring up a system-VPN session to the exit (Ed25519 id from `listExits`). |
| `disconnect` | none | Tear the session down. |

Daemon to app (events):

| `type` | Fields | Meaning |
|---|---|---|
| `state` | `state` (`connecting`/`connected`/`reconnecting`/`failed`/`disconnected`) | Connection-state transition. |
| `error` | `kind` (`identity`/`api`/`discovery`/`tunnel`/`privilege`), `message` (redacted) | A failure; never carries key, address or IP. |

## Daemon responsibilities (the privileged, gated half)

The daemon embeds the audited engine (`warren-sdk` + `warren-tun`) and is the
only component that needs privilege. It must:

1. Authenticate the peer (socket permissions) before honoring `configure`.
2. Build the engine client and the multihop tunnel, mapping engine errors to the
   `error` event categories above.
3. Own the TUN device, split-default routing, DNS push and the killswitch, and
   tear them all down on `disconnect` or daemon exit (fail-closed).
4. Bootstrap privilege per OS: polkit (Linux), a launchd helper (macOS) or a
   Windows service, with a single elevation.

These steps require root and real routing, so they are validated on a target
host, not in the SDK's automated tests. The app-side protocol and client in this
package are covered by unit tests against an in-memory daemon.
