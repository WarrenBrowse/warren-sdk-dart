//! Warren SDK desktop system-VPN daemon (Mode B).
//!
//! Owns the privileged TUN datapath through the audited `warren-sdk` engine and
//! serves the SDK IPC protocol (see [`protocol`]) over a Unix socket. Exactly one
//! IPC connection, from the authorized owner uid, drives one session: the tunnel
//! is torn down when that connection closes, so a crashed app never leaves the
//! datapath up (fail-closed). A second, concurrent connection is refused rather
//! than allowed to tear down the live session.
//!
//! The active tunnel is held in a shared slot and torn down on SIGINT/SIGTERM as
//! well, so stopping the daemon always restores the host's routing and pf state.
//!
//! Run as root (TUN needs privilege). The socket path is the first argument, or
//! `/tmp/warren-sdk-daemon.sock` by default for development.

mod protocol;

use std::os::fd::AsRawFd;
use std::path::Path;
use std::sync::{Arc, Mutex};

use anyhow::{Context, Result};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{UnixListener, UnixStream};
use warren_sdk::discovery::VerifiedExit;
use warren_sdk::identity::WarrenIdentity;
use warren_sdk::{DefaultClient, SdkError, TunDatapathHandle, WarrenClient};
use zeroize::Zeroize;

use protocol::{ConnState, Event, Request};

const DEFAULT_SOCKET: &str = "/tmp/warren-sdk-daemon.sock";
const MAX_FRAME: usize = 16 * 1024 * 1024;

/// The single active tunnel. Dropping it reverts routing and the killswitch, so
/// holding it here lets both a connection close and a shutdown signal restore the
/// host's network.
type SharedTunnel = Arc<Mutex<Option<TunDatapathHandle>>>;

#[tokio::main]
async fn main() -> Result<()> {
    let socket_path = std::env::args()
        .nth(1)
        .unwrap_or_else(|| DEFAULT_SOCKET.to_owned());

    if Path::new(&socket_path).exists() {
        std::fs::remove_file(&socket_path).ok();
    }
    let listener = UnixListener::bind(&socket_path)
        .with_context(|| format!("binding the daemon socket at {socket_path}"))?;
    restrict_socket(&socket_path)?;
    eprintln!("warrend listening on {socket_path}");

    // The only peer allowed to drive the root daemon: the invoking user under
    // sudo, otherwise root itself. Filesystem permissions are a backstop, not the
    // trust boundary; every connection is checked against this uid.
    let authorized_uid = std::env::var("SUDO_UID")
        .ok()
        .and_then(|v| v.parse::<u32>().ok())
        .unwrap_or_else(|| unsafe { libc::geteuid() });

    let tunnel: SharedTunnel = Arc::new(Mutex::new(None));

    // Restore the network on a shutdown signal before exiting (a SIGKILL still
    // cannot be caught, but a normal stop is always clean).
    {
        let tunnel = Arc::clone(&tunnel);
        let socket_path = socket_path.clone();
        tokio::spawn(async move {
            shutdown_signal().await;
            eprintln!("warrend: shutting down, restoring network");
            drop(tunnel.lock().expect("tunnel mutex").take());
            std::fs::remove_file(&socket_path).ok();
            std::process::exit(0);
        });
    }

    // One session owner at a time. Only the owner connection's close tears the
    // tunnel down; extra connections are refused so a rogue open/close cannot
    // revert routing and leak the owner's traffic.
    let mut has_owner = false;
    loop {
        let (mut stream, _) = listener.accept().await?;

        match peer_uid(&stream) {
            Some(uid) if uid == authorized_uid => {}
            _ => {
                let _ = send(&mut stream, &Event::error("privilege", "unauthorized peer")).await;
                continue;
            }
        }

        if has_owner {
            let _ = send(
                &mut stream,
                &Event::error("privilege", "the daemon already has an active session"),
            )
            .await;
            continue;
        }
        has_owner = true;

        let tunnel = Arc::clone(&tunnel);
        let socket_path = socket_path.clone();
        tokio::spawn(async move {
            if let Err(error) = serve_connection(&mut stream, &tunnel).await {
                eprintln!("warrend: connection ended: {error}");
            }
            // The owner connection closed: tear the tunnel down and exit, so a
            // stopped client never leaves a privileged daemon (or a captured
            // network) behind.
            drop(tunnel.lock().expect("tunnel mutex").take());
            std::fs::remove_file(&socket_path).ok();
            std::process::exit(0);
        });
    }
}

/// The uid of the process on the other end of the control socket, or `None` if it
/// cannot be determined.
#[cfg(target_os = "linux")]
fn peer_uid(stream: &UnixStream) -> Option<u32> {
    let mut cred = libc::ucred {
        pid: 0,
        uid: 0,
        gid: 0,
    };
    let mut len = std::mem::size_of::<libc::ucred>() as libc::socklen_t;
    let rc = unsafe {
        libc::getsockopt(
            stream.as_raw_fd(),
            libc::SOL_SOCKET,
            libc::SO_PEERCRED,
            &mut cred as *mut _ as *mut libc::c_void,
            &mut len,
        )
    };
    (rc == 0).then_some(cred.uid)
}

/// The uid of the process on the other end of the control socket, or `None` if it
/// cannot be determined.
#[cfg(not(target_os = "linux"))]
fn peer_uid(stream: &UnixStream) -> Option<u32> {
    let mut uid: libc::uid_t = 0;
    let mut gid: libc::gid_t = 0;
    let rc = unsafe { libc::getpeereid(stream.as_raw_fd(), &mut uid, &mut gid) };
    (rc == 0).then_some(uid)
}

async fn shutdown_signal() {
    use tokio::signal::unix::{signal, SignalKind};
    let mut term = signal(SignalKind::terminate()).expect("install SIGTERM handler");
    let mut interrupt = signal(SignalKind::interrupt()).expect("install SIGINT handler");
    tokio::select! {
        _ = term.recv() => {}
        _ = interrupt.recv() => {}
    }
}

/// Restricts the control socket to its owner (mode 0660) and, when the daemon
/// was launched via sudo, hands ownership to the invoking user so an unprivileged
/// app can drive it without making the socket world-accessible.
fn restrict_socket(socket_path: &str) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;

    std::fs::set_permissions(socket_path, std::fs::Permissions::from_mode(0o660))?;
    let uid = std::env::var("SUDO_UID")
        .ok()
        .and_then(|v| v.parse::<u32>().ok());
    let gid = std::env::var("SUDO_GID")
        .ok()
        .and_then(|v| v.parse::<u32>().ok());
    if uid.is_some() || gid.is_some() {
        std::os::unix::fs::chown(socket_path, uid, gid)?;
    }
    Ok(())
}

/// Per-connection state: the configured engine client. The tunnel itself lives in
/// the shared slot so signals and connection close can both tear it down.
#[derive(Default)]
struct Session {
    client: Option<DefaultClient>,
}

async fn serve_connection(stream: &mut UnixStream, tunnel: &SharedTunnel) -> Result<()> {
    let mut session = Session::default();
    while let Some(mut frame) = read_frame(stream).await? {
        // A configure frame carries the raw mnemonic; wipe the buffer as soon as
        // it is parsed so the seed does not linger on the heap of this root
        // process (parsing has already copied any fields it keeps).
        let parsed = serde_json::from_slice::<Request>(&frame);
        frame.zeroize();
        let request: Request = match parsed {
            Ok(request) => request,
            Err(_) => {
                send(stream, &Event::error("tunnel", "malformed request")).await?;
                continue;
            }
        };
        // Teardown is not instantaneous (routing + pf revert): announce it so
        // the client can hold a "draining, killswitch still up" state instead
        // of reading the eventual Disconnected as already true.
        if matches!(request, Request::Disconnect) {
            send(stream, &Event::state(ConnState::Draining)).await?;
        }
        match handle(&mut session, tunnel, request).await {
            Ok(Some(event)) => send(stream, &event).await?,
            Ok(None) => {}
            Err(event) => send(stream, &event).await?,
        }
    }
    Ok(())
}

/// Handles one request, returning an event to send back (or an error event).
async fn handle(
    session: &mut Session,
    tunnel: &SharedTunnel,
    request: Request,
) -> Result<Option<Event>, Event> {
    match request {
        Request::Configure {
            mut mnemonic,
            api_base,
            server_pubkey_pin,
            multihop_root_pin,
            daita,
            daita_machine,
            request_ipv6,
        } => {
            let identity_result = WarrenIdentity::from_mnemonic(&mnemonic);
            // The engine keeps only the zeroized derived key; wipe our own copy
            // whether or not derivation succeeded.
            mnemonic.zeroize();
            let identity =
                identity_result.map_err(|_| Event::error("identity", "invalid mnemonic"))?;
            let mut builder = WarrenClient::builder()
                .identity(identity)
                .api_base(api_base)
                .server_pubkey_pin(server_pubkey_pin);
            if let Some(root) = multihop_root_pin {
                builder = builder.multihop_root_pubkey_pin(root);
            }
            if request_ipv6 {
                builder = builder.request_ipv6();
            }
            if daita {
                builder = builder.daita();
                if let Some(machine) = daita_machine {
                    builder = builder.daita_machine(machine);
                }
            }
            // System-VPN obfuscation: this daemon's workspace patches quinn to the
            // WarrenGuard fork, so inject the engine's obfuscated QUIC-Initial
            // config (ClientHello split + first-datagram padding) to match
            // warren-app's anti-DPI handshake. The SDK itself stays on upstream.
            builder = builder
                .transport_config(warrenguard_transport_core::warren_transport_config_client());
            let client = builder
                .build()
                .map_err(|e| Event::error("api", e.to_string()))?;
            session.client = Some(client);
            Ok(None)
        }
        Request::Connect {
            exit_pubkey_hex,
            dns_over_tunnel,
        } => {
            // A full TUN captures all traffic (including DNS) by construction, so
            // the flag is accepted for protocol parity but does not change the
            // datapath here.
            let _ = dns_over_tunnel;
            let client = session
                .client
                .as_ref()
                .ok_or_else(|| Event::error("tunnel", "configure must precede connect"))?;
            let exit = find_exit(client, &exit_pubkey_hex).await?;
            // Datapath scope of the cover/probe defenses on this TUN path: the
            // engine idle-cover IS armed here, because `start_tun_multihop`
            // shares the engine multihop dial (`connect_multihop_with_bypass`,
            // driven by the `cover_defenses()` knob) with the userland proxy.
            // What this path does NOT run is the in-tunnel egress liveness probe:
            // that probe lives in the in-process proxy glue (`warren_sdk_frb`)
            // and connects through the session's SOCKS5 endpoint, which a full
            // TUN has no equivalent of. Surfacing a "dead egress" signal here
            // would mean an equivalent probe over the TUN datapath (or exposing
            // the engine `warren_transport::egress_probe` on this handle),
            // reported on the IPC protocol; not wired yet, and deferred while the
            // privileged TUN datapath is under separate review.
            // An empty name lets the OS pick the TUN interface.
            let handle = client
                .start_tun_multihop(&exit, "")
                .await
                .map_err(map_sdk_error)?;
            // Replacing any prior tunnel drops it first (reverting its routes).
            *tunnel.lock().expect("tunnel mutex") = Some(handle);
            Ok(Some(Event::state(ConnState::Connected)))
        }
        Request::Disconnect => {
            drop(tunnel.lock().expect("tunnel mutex").take());
            Ok(Some(Event::state(ConnState::Disconnected)))
        }
    }
}

async fn find_exit(client: &DefaultClient, exit_pubkey_hex: &str) -> Result<VerifiedExit, Event> {
    let target: [u8; 32] = hex::decode(exit_pubkey_hex)
        .ok()
        .and_then(|bytes| bytes.try_into().ok())
        .ok_or_else(|| Event::error("discovery", "invalid exit id"))?;
    let exits = client
        .fetch_multihop_directory()
        .await
        .map_err(map_sdk_error)?;
    exits
        .into_iter()
        .find(|candidate| candidate.exit_ed25519_pubkey == target)
        .ok_or_else(|| Event::error("discovery", "exit not in multihop directory"))
}

fn map_sdk_error(error: SdkError) -> Event {
    let kind = match error {
        SdkError::Discovery(_)
        | SdkError::Selector(_)
        | SdkError::StaleRelayList
        | SdkError::RolledBackRelayList { .. }
        | SdkError::MultihopDirectory(_) => "discovery",
        SdkError::Api(_) => "api",
        _ => "tunnel",
    };
    Event::error(kind, error_chain(&error))
}

/// Renders an error with its `#[source]` chain (system causes like a TUN open or
/// routing failure). These are OS-level reasons, not identity material.
fn error_chain(error: &dyn std::error::Error) -> String {
    let mut message = error.to_string();
    let mut source = error.source();
    while let Some(cause) = source {
        message.push_str(": ");
        message.push_str(&cause.to_string());
        source = cause.source();
    }
    message
}

/// Reads one length-prefixed frame, or `None` at clean EOF.
async fn read_frame(stream: &mut UnixStream) -> Result<Option<Vec<u8>>> {
    let mut len_buf = [0u8; 4];
    match stream.read_exact(&mut len_buf).await {
        Ok(_) => {}
        Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => return Ok(None),
        Err(e) => return Err(e.into()),
    }
    let len = u32::from_be_bytes(len_buf) as usize;
    anyhow::ensure!(len <= MAX_FRAME, "frame too large: {len}");
    let mut payload = vec![0u8; len];
    stream.read_exact(&mut payload).await?;
    Ok(Some(payload))
}

async fn send(stream: &mut UnixStream, event: &Event) -> Result<()> {
    let payload = serde_json::to_vec(event)?;
    stream
        .write_all(&(payload.len() as u32).to_be_bytes())
        .await?;
    stream.write_all(&payload).await?;
    stream.flush().await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Reads one framed daemon event from `stream` as JSON.
    async fn read_event(stream: &mut UnixStream) -> serde_json::Value {
        let mut len_buf = [0u8; 4];
        stream.read_exact(&mut len_buf).await.expect("frame length");
        let mut payload = vec![0u8; u32::from_be_bytes(len_buf) as usize];
        stream
            .read_exact(&mut payload)
            .await
            .expect("frame payload");
        serde_json::from_slice(&payload).expect("event json")
    }

    async fn send_frame(stream: &mut UnixStream, payload: &[u8]) {
        stream
            .write_all(&(payload.len() as u32).to_be_bytes())
            .await
            .expect("frame length");
        stream.write_all(payload).await.expect("frame payload");
    }

    #[tokio::test]
    async fn disconnect_reports_draining_then_disconnected() {
        // The client must be able to distinguish "teardown in progress, the
        // killswitch still holds" from "the network is fully restored": a
        // single final event would read as done while routing/pf revert is
        // still running.
        let (mut daemon_end, mut client_end) = UnixStream::pair().expect("socketpair");
        let tunnel: SharedTunnel = Arc::new(Mutex::new(None));
        let serve = tokio::spawn(async move { serve_connection(&mut daemon_end, &tunnel).await });

        send_frame(&mut client_end, br#"{"type":"disconnect"}"#).await;

        let first = read_event(&mut client_end).await;
        assert_eq!(
            first,
            serde_json::json!({"type": "state", "state": "draining"}),
            "teardown must be announced before the network revert runs"
        );
        let second = read_event(&mut client_end).await;
        assert_eq!(
            second,
            serde_json::json!({"type": "state", "state": "disconnected"}),
            "disconnected is only sent once the datapath handle is dropped"
        );

        drop(client_end);
        serve
            .await
            .expect("serve task")
            .expect("clean end at client EOF");
    }

    #[tokio::test]
    async fn peer_uid_reports_the_connected_process_uid() {
        // Both ends of a socketpair belong to this process, so the peer uid the
        // daemon reads must be our own euid. A broken read would return None or a
        // different uid and let the authorization gate misfire.
        let (end, _other) = UnixStream::pair().expect("socketpair");
        let expected = unsafe { libc::geteuid() };
        assert_eq!(peer_uid(&end), Some(expected));
    }
}
