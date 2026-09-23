# Warren desktop daemon IPC

Mode B (system VPN) runs the privileged datapath out of process, the same shape
as Mullvad and Tailscale: a long-lived **Warren daemon** owns the TUN device,
routing and killswitch; the app drives it over a local socket. This document is
the contract a daemon must implement; `warren_sdk_desktop` is the app-side
client.

## Transport

- Linux/macOS: a Unix domain socket. The daemon restricts it to its owner
  (mode `0660`) and, when launched via `sudo`, hands ownership to the invoking
  user (`SUDO_UID:SUDO_GID`) so an unprivileged app can drive it. Windows: a named
  pipe with an equivalent ACL.
- Filesystem permissions are only a backstop: the daemon authenticates every
  connection's peer uid (`getpeereid` / `SO_PEERCRED`) and accepts only the
  authorized owner, so a shared group or a permissive umask cannot let another
  user drive the root daemon.
- The app authenticates the daemon the same way before it sends anything:
  `connectDaemonSocket` reads the account serving the socket from the kernel
  (`LOCAL_PEERCRED` / `SO_PEERCRED`) and refuses any account but root with a
  `privilege/daemon-untrusted` error, failing closed where the platform cannot
  tell. The `configure` request carries the mnemonic, so a listener another
  local account planted at the socket path never receives it.
- The daemon serves exactly one session at a time. A second, concurrent
  connection is refused (it receives a `privilege` error and is dropped) rather
  than allowed to tear down the live tunnel; only the owner connection's close
  reverts routing.
- The daemon default dev socket path is `/tmp/warren-sdk-daemon.sock`; production
  uses a root-owned path (for example `/run/warren/warrend.sock`). The app default
  is `defaultDaemonSocketPath`.
- Framing: each message is a 4-byte big-endian length prefix followed by that
  many bytes of UTF-8 JSON, capped at 16 MiB. See `FrameCodec` / `FrameReader`.

## Messages

App to daemon (requests):

| `type` | Fields | Meaning |
|---|---|---|
| `configure` | `mnemonic`, `apiBase`, `serverPubkeyPin`, `multihopRootPin?`, `daita?`, `daitaMachine?`, `requestIpv6?` | Bind identity + account API and the client build options. The daemon derives and zeroizes the key; it never logs the mnemonic. |
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

1. Authenticate the peer by uid (`getpeereid` / `SO_PEERCRED`), not by socket
   permissions alone, before honoring `configure`, and refuse any second session.
2. Build the engine client and the multihop tunnel, mapping engine errors to the
   `error` event categories above.
3. Own the TUN device, split-default routing, DNS push and the killswitch, and
   tear them all down on `disconnect` or daemon exit (fail-closed).
4. Bootstrap privilege per OS: polkit (Linux), a launchd helper (macOS) or a
   Windows service, with a single elevation.

These steps require root and real routing, so they are validated on a target
host, not in the SDK's automated tests. The app-side protocol and client in this
package are covered by unit tests against an in-memory daemon.
