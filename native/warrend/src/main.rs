//! Warren SDK desktop system-VPN daemon (Mode B).
//!
//! Owns the privileged TUN datapath through the audited `warren-sdk` engine and
//! serves the SDK IPC protocol (see [`protocol`]) over a Unix socket. One IPC
//! connection drives one session: the tunnel is torn down when the connection
//! closes, so a crashed app never leaves the datapath up (fail-closed).
//!
//! Run as root (TUN needs privilege). The socket path is the first argument, or
//! `/tmp/warren-sdk-daemon.sock` by default for development.

mod protocol;

use std::path::Path;

use anyhow::{Context, Result};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{UnixListener, UnixStream};
use warren_sdk::discovery::VerifiedExit;
use warren_sdk::identity::WarrenIdentity;
use warren_sdk::{DefaultClient, SdkError, WarrenClient};

use protocol::{ConnState, Event, Request};

const DEFAULT_SOCKET: &str = "/tmp/warren-sdk-daemon.sock";
const MAX_FRAME: usize = 16 * 1024 * 1024;

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

    loop {
        let (stream, _) = listener.accept().await?;
        // One session per connection; a panic in one must not take the daemon
        // down, so each connection runs in its own task.
        tokio::spawn(async move {
            if let Err(error) = serve_connection(stream).await {
                eprintln!("warrend: connection ended: {error}");
            }
        });
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

/// Per-connection state. Dropping `tunnel` reverts routing and the killswitch.
#[derive(Default)]
struct Session {
    client: Option<DefaultClient>,
    tunnel: Option<warren_sdk::TunDatapathHandle>,
}

async fn serve_connection(mut stream: UnixStream) -> Result<()> {
    let mut session = Session::default();
    while let Some(frame) = read_frame(&mut stream).await? {
        let request: Request = match serde_json::from_slice(&frame) {
            Ok(request) => request,
            Err(_) => {
                send(&mut stream, &Event::error("tunnel", "malformed request")).await?;
                continue;
            }
        };
        match handle(&mut session, request).await {
            Ok(Some(event)) => send(&mut stream, &event).await?,
            Ok(None) => {}
            Err(event) => send(&mut stream, &event).await?,
        }
    }
    // Connection closed: the session (and its tunnel) drops here, tearing the
    // datapath down.
    Ok(())
}

/// Handles one request, returning an event to send back (or an error event).
async fn handle(session: &mut Session, request: Request) -> Result<Option<Event>, Event> {
    match request {
        Request::Configure {
            mnemonic,
            api_base,
            server_pubkey_pin,
            multihop_root_pin,
        } => {
            let identity = WarrenIdentity::from_mnemonic(&mnemonic)
                .map_err(|_| Event::error("identity", "invalid mnemonic"))?;
            let mut builder = WarrenClient::builder()
                .identity(identity)
                .api_base(api_base)
                .server_pubkey_pin(server_pubkey_pin)
                .request_ipv6();
            if let Some(root) = multihop_root_pin {
                builder = builder.multihop_root_pubkey_pin(root);
            }
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
            // An empty name lets the OS pick the TUN interface.
            let handle = client
                .start_tun_multihop(&exit, "")
                .await
                .map_err(map_sdk_error)?;
            session.tunnel = Some(handle);
            Ok(Some(Event::state(ConnState::Connected)))
        }
        Request::Disconnect => {
            session.tunnel = None;
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
