//! Warren SDK desktop system-VPN daemon (Mode B).
//!
//! Owns the privileged TUN datapath through the audited `warren-sdk` engine and
//! serves the SDK IPC protocol (see [`protocol`]) over a Unix socket. Exactly one
//! IPC connection, from the authorized owner uid, drives one session: a second,
//! concurrent connection is refused rather than allowed to tear down the live
//! session.
//!
//! # Kill-switch posture (shared contract)
//!
//! The stop-time firewall posture follows the cross-client matrix
//! (`warren_contract::killswitch`, mirrored in [`posture`]):
//!
//! - USER-INTENDED stops (IPC `disconnect`, SIGINT/SIGTERM) tear the rules
//!   down and restore the host network, UNLESS lockdown mode is configured on,
//!   in which case a warrend-owned block-all artifact keeps holding.
//! - ABNORMAL ends fail CLOSED: the owner connection vanishing mid-session, a
//!   panic (release builds abort), or a SIGKILL all leave the installed
//!   kernel ruleset blocking off-tunnel traffic. No leak, no connectivity.
//!
//! Fail-closed never means bricked: the next daemon start reconciles the stale
//! state ([`netblock::startup_reconcile`]) and `warrend revert` is the manual
//! escape that needs no healthy daemon (see [`HELP`]).
//!
//! Run as root (TUN needs privilege). The socket path is the first argument, or
//! `/tmp/warren-sdk-daemon.sock` by default for development.

mod cmd;
mod netblock;
mod posture;
mod protocol;

use std::os::fd::AsRawFd;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use anyhow::{Context, Result};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{UnixListener, UnixStream};
use warren_sdk::discovery::VerifiedExit;
use warren_sdk::identity::WarrenIdentity;
use warren_sdk::{DefaultClient, SdkError, TunDatapathHandle, WarrenClient};
use zeroize::Zeroize;

use cmd::{CmdRunner, SystemRunner};
use posture::{stop_action, StopAction, StopTrigger};
use protocol::{ConnState, Event, Request};

const DEFAULT_SOCKET: &str = "/tmp/warren-sdk-daemon.sock";
const MAX_FRAME: usize = 16 * 1024 * 1024;

const HELP: &str = "\
warrend - Warren SDK desktop system-VPN daemon (Mode B)

USAGE:
    warrend [SOCKET_PATH]    run the daemon (default /tmp/warren-sdk-daemon.sock)
    warrend revert           tear down any Warren network block left behind
                             (kill-switch firewall rules, lockdown block, DNS
                             override) WITHOUT needing a running daemon.
                             Run as root.
    warrend --help           print this help

The daemon fails CLOSED: if it dies unexpectedly while a session is up, the
kill-switch rules keep blocking off-tunnel traffic so nothing leaks. To get
the network back: reconnect (the next daemon start adopts or replaces the
stale rules), disconnect explicitly, or run `warrend revert` as the manual
escape. A clean stop (disconnect, SIGINT/SIGTERM) restores the network unless
lockdown mode is configured on.
";

/// The single active tunnel. Dropping it reverts routing, DNS and the
/// kill-switch; the stop paths below decide per the shared posture matrix
/// whether to drop it (restore) or leak it (hold the block).
type SharedTunnel = Arc<Mutex<Option<TunDatapathHandle>>>;

fn main() -> Result<()> {
    let arg = std::env::args().nth(1);
    match arg.as_deref() {
        Some("--help" | "-h" | "help") => {
            print!("{HELP}");
            Ok(())
        }
        Some("revert") => run_revert(),
        _ => run_daemon(arg.unwrap_or_else(|| DEFAULT_SOCKET.to_owned())),
    }
}

/// The `warrend revert` manual escape: clears every Warren block this host can
/// carry and reconciles DNS, with no daemon and no session state required.
fn run_revert() -> Result<()> {
    if unsafe { libc::geteuid() } != 0 {
        eprintln!("warrend revert: not running as root; firewall/DNS commands will likely fail");
    }
    let report = netblock::revert_network(netblock::platform_backend(), &SystemRunner)?;
    println!("engine kill-switch rules: {:?}", report.engine_block);
    println!("lockdown block: {:?}", report.lockdown_block);
    if report.dns_actions.is_empty() {
        println!("dns: clean");
    } else {
        for action in &report.dns_actions {
            println!("dns: {action}");
        }
    }
    println!("network restored");
    Ok(())
}

#[tokio::main]
async fn run_daemon(socket_path: String) -> Result<()> {
    ensure_not_already_serving(&socket_path).await?;

    // A dead predecessor's leftovers: report the held block (fail-closed, only
    // a user intent clears it) and reconcile the DNS override now, so the next
    // connect's control-plane dial can resolve names.
    let runner: Arc<dyn CmdRunner> = Arc::new(SystemRunner);
    let backend = netblock::platform_backend();
    match netblock::startup_reconcile(backend, runner.as_ref()) {
        Ok(report) => {
            if report.engine_block {
                eprintln!(
                    "warrend: a dead predecessor's kill-switch rules are installed; holding \
                     them (fail-closed). Connect to adopt, disconnect or `warrend revert` to clear."
                );
            }
            if report.lockdown_block {
                eprintln!("warrend: the lockdown block is installed; holding it.");
            }
            for action in &report.dns_actions {
                eprintln!("warrend: dns reconcile: {action}");
            }
        }
        Err(error) => eprintln!("warrend: startup reconcile failed (continuing): {error}"),
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
    let lockdown = Arc::new(AtomicBool::new(false));

    // A shutdown signal is a user-intended stop: restore the network unless
    // lockdown is on, in which case the installed rules are deliberately
    // leaked so the kernel keeps blocking after the process is gone.
    {
        let tunnel = Arc::clone(&tunnel);
        let lockdown = Arc::clone(&lockdown);
        let socket_path = socket_path.clone();
        let runner = Arc::clone(&runner);
        tokio::spawn(async move {
            shutdown_signal().await;
            let held = tunnel.lock().expect("tunnel mutex").take();
            match stop_action(StopTrigger::DaemonShutdown, lockdown.load(Ordering::SeqCst)) {
                StopAction::RestoreNetwork => {
                    eprintln!("warrend: shutting down, restoring network");
                    drop(held);
                    // Sweep anything a predecessor left behind too; a no-op
                    // right after a clean revert.
                    if let Err(error) =
                        netblock::revert_network(netblock::platform_backend(), runner.as_ref())
                    {
                        eprintln!("warrend: shutdown sweep failed: {error}");
                    }
                }
                StopAction::HoldBlock => {
                    eprintln!("warrend: shutting down under lockdown, the block stays installed");
                    if let Some(handle) = held {
                        // The kernel-side rules outlive the process; skipping
                        // the RAII teardown is exactly what keeps them.
                        std::mem::forget(handle);
                    }
                }
            }
            std::fs::remove_file(&socket_path).ok();
            std::process::exit(0);
        });
    }

    // One session owner at a time. Only the owner connection drives the
    // session; extra connections are refused so a rogue open/close cannot
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
        let lockdown = Arc::clone(&lockdown);
        let socket_path = socket_path.clone();
        let runner = Arc::clone(&runner);
        tokio::spawn(async move {
            if let Err(error) = serve_connection(&mut stream, &tunnel, &runner, &lockdown).await {
                eprintln!("warrend: connection ended: {error}");
            }
            // The owner connection is gone. A clean disconnect already emptied
            // the slot; a live handle here means the owner vanished
            // mid-session, which must never open the network (shared matrix:
            // OwnerConnectionLost is Blocking regardless of lockdown), so the
            // teardown is skipped and the kernel rules keep holding.
            let held = tunnel.lock().expect("tunnel mutex").take();
            if let Some(handle) = held {
                match stop_action(
                    StopTrigger::OwnerConnectionLost,
                    lockdown.load(Ordering::SeqCst),
                ) {
                    StopAction::HoldBlock => {
                        eprintln!(
                            "warrend: owner vanished mid-session; failing CLOSED (rules stay; \
                             reconnect, or `warrend revert` to restore the network)"
                        );
                        std::mem::forget(handle);
                    }
                    StopAction::RestoreNetwork => drop(handle),
                }
            }
            std::fs::remove_file(&socket_path).ok();
            std::process::exit(0);
        });
    }
}

/// Refuses to start when a live daemon already serves `socket_path` (its
/// session state, including any DNS snapshot, must not be reconciled away
/// under it); removes the socket file when it is a dead leftover.
async fn ensure_not_already_serving(socket_path: &str) -> Result<()> {
    if !Path::new(socket_path).exists() {
        return Ok(());
    }
    let probe = tokio::time::timeout(
        std::time::Duration::from_secs(1),
        UnixStream::connect(socket_path),
    )
    .await;
    if matches!(probe, Ok(Ok(_))) {
        anyhow::bail!("another warrend is already serving {socket_path}; refusing to start");
    }
    std::fs::remove_file(socket_path).ok();
    Ok(())
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
/// the shared slot so signals and connection close can both act on it.
#[derive(Default)]
struct Session {
    client: Option<DefaultClient>,
}

async fn serve_connection(
    stream: &mut UnixStream,
    tunnel: &SharedTunnel,
    runner: &Arc<dyn CmdRunner>,
    lockdown: &Arc<AtomicBool>,
) -> Result<()> {
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
        match handle(&mut session, tunnel, runner, lockdown, request).await {
            Ok(Some(event)) => send(stream, &event).await?,
            Ok(None) => {}
            Err(event) => send(stream, &event).await?,
        }
    }
    Ok(())
}

/// Runs one blocking netblock step off the async runtime.
async fn run_netblock<T, F>(runner: &Arc<dyn CmdRunner>, step: F) -> Result<T>
where
    T: Send + 'static,
    F: FnOnce(netblock::Backend, &dyn CmdRunner) -> Result<T> + Send + 'static,
{
    let runner = Arc::clone(runner);
    tokio::task::spawn_blocking(move || step(netblock::platform_backend(), runner.as_ref()))
        .await
        .context("join netblock task")?
}

/// Handles one request, returning an event to send back (or an error event).
async fn handle(
    session: &mut Session,
    tunnel: &SharedTunnel,
    runner: &Arc<dyn CmdRunner>,
    lockdown: &Arc<AtomicBool>,
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
            lockdown: lockdown_requested,
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
            lockdown.store(lockdown_requested, Ordering::SeqCst);
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
            // A held block (a dead predecessor's kill-switch, or the lockdown
            // block) would drop this connect's own control-plane dial. The
            // connect is the user's intent to protect via a NEW session, so
            // lift the stale block first; a failed connect re-blocks below
            // instead of leaving the network open.
            let had_block = if tunnel.lock().expect("tunnel mutex").is_none() {
                run_netblock(runner, netblock::clear_blocks_for_dial)
                    .await
                    .map_err(|e| Event::error("tunnel", e.to_string()))?
            } else {
                false
            };
            let connected = connect_session(client, &exit_pubkey_hex).await;
            match connected {
                Ok(handle) => {
                    // Datapath scope note: the engine idle-cover IS armed on
                    // this TUN path (shared multihop dial); the in-tunnel
                    // egress liveness probe is not, it lives in the in-process
                    // proxy glue and has no TUN equivalent yet.
                    // Replacing any prior tunnel drops it first (reverting its
                    // routes).
                    *tunnel.lock().expect("tunnel mutex") = Some(handle);
                    Ok(Some(Event::state(ConnState::Connected)))
                }
                Err(event) => {
                    if had_block || lockdown.load(Ordering::SeqCst) {
                        // The network was blocked before this attempt (or
                        // lockdown demands it): a failed connect must not
                        // leave it open.
                        if let Err(error) = run_netblock(runner, |b, r| b.install_lockdown(r)).await
                        {
                            eprintln!("warrend: re-block after failed connect failed: {error}");
                        }
                    }
                    Err(event)
                }
            }
        }
        Request::Disconnect => {
            let lockdown_on = lockdown.load(Ordering::SeqCst);
            match stop_action(StopTrigger::UserDisconnect, lockdown_on) {
                StopAction::HoldBlock => {
                    // Install the standalone lockdown block BEFORE the engine
                    // teardown: its artifact is warrend's own (distinct table /
                    // anchor), so the engine's RAII revert cannot clear it and
                    // there is no instant with the network open. On failure the
                    // session is deliberately kept up: no leak beats a broken
                    // disconnect, and the caller can retry.
                    run_netblock(runner, |b, r| b.install_lockdown(r))
                        .await
                        .map_err(|e| {
                            Event::error(
                                "tunnel",
                                format!("lockdown block install failed, session kept up: {e}"),
                            )
                        })?;
                    drop(tunnel.lock().expect("tunnel mutex").take());
                    // Normalize: with the lockdown artifact holding, a stale
                    // engine block (dead predecessor) has no reason to stay.
                    if let Err(error) = run_netblock(runner, |b, r| b.clear_engine_block(r)).await {
                        eprintln!("warrend: stale engine block sweep failed: {error}");
                    }
                }
                StopAction::RestoreNetwork => {
                    drop(tunnel.lock().expect("tunnel mutex").take());
                    // Sweep whatever is left: a dead predecessor's rules, a
                    // previous lockdown block, a stale DNS override. A no-op
                    // right after the drop reverted a live session.
                    if let Err(error) = run_netblock(runner, netblock::revert_network).await {
                        eprintln!("warrend: disconnect sweep failed: {error}");
                    }
                }
            }
            Ok(Some(Event::state(ConnState::Disconnected)))
        }
    }
}

/// Resolves the exit and brings the TUN datapath up.
async fn connect_session(
    client: &DefaultClient,
    exit_pubkey_hex: &str,
) -> Result<TunDatapathHandle, Event> {
    let exit = find_exit(client, exit_pubkey_hex).await?;
    // An empty name lets the OS pick the TUN interface.
    client
        .start_tun_multihop(&exit, "")
        .await
        .map_err(map_sdk_error)
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
    use cmd::testing::RecordingRunner;

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

    /// Wires a serve loop over a socketpair with a recording runner.
    fn spawn_serve(
        lockdown_preset: bool,
    ) -> (
        UnixStream,
        Arc<RecordingRunner>,
        tokio::task::JoinHandle<Result<()>>,
    ) {
        let (mut daemon_end, client_end) = UnixStream::pair().expect("socketpair");
        let tunnel: SharedTunnel = Arc::new(Mutex::new(None));
        let recording = Arc::new(RecordingRunner::default());
        let runner: Arc<dyn CmdRunner> = recording.clone();
        let lockdown = Arc::new(AtomicBool::new(lockdown_preset));
        let serve = tokio::spawn(async move {
            serve_connection(&mut daemon_end, &tunnel, &runner, &lockdown).await
        });
        (client_end, recording, serve)
    }

    /// True when `calls` contains a firewall BLOCK-INSTALL invocation for this
    /// host's backend (nft ruleset pipe, or pf anchor load).
    fn block_install_ran(calls: &[cmd::testing::RecordedCall]) -> bool {
        calls.iter().any(|(program, args, stdin)| {
            (program == "nft" && args == &["-f", "-"] && stdin.is_some())
                || (program == "pfctl" && args.contains(&"-f".to_owned()) && stdin.is_some())
        })
    }

    /// True when `calls` contains a teardown of the ENGINE artifact for this
    /// host's backend.
    fn engine_teardown_ran(calls: &[cmd::testing::RecordedCall]) -> bool {
        calls.iter().any(|(program, args, _)| {
            (program == "nft" && args.iter().any(|a| a == netblock::ENGINE_NFT_TABLE))
                || (program == "pfctl" && args.iter().any(|a| a == netblock::ENGINE_PF_ANCHOR))
        })
    }

    #[tokio::test]
    async fn disconnect_reports_draining_then_disconnected() {
        // The client must be able to distinguish "teardown in progress, the
        // killswitch still holds" from "the network is fully restored": a
        // single final event would read as done while routing/pf revert is
        // still running.
        let (mut client_end, _recording, serve) = spawn_serve(false);

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
    async fn disconnect_without_lockdown_sweeps_stale_blocks_and_restores() {
        // A disconnect is the user intent that clears a dead predecessor's
        // held block (shared matrix: UserDisconnect without lockdown = Open).
        let (mut client_end, recording, serve) = spawn_serve(false);

        send_frame(&mut client_end, br#"{"type":"disconnect"}"#).await;
        let _draining = read_event(&mut client_end).await;
        let _disconnected = read_event(&mut client_end).await;

        let calls = recording.calls();
        assert!(
            engine_teardown_ran(&calls),
            "the stale engine block must be swept on an explicit disconnect; calls: {calls:?}"
        );
        assert!(
            !block_install_ran(&calls),
            "no block may be installed on a plain disconnect; calls: {calls:?}"
        );

        drop(client_end);
        serve.await.expect("serve task").expect("clean end");
    }

    #[tokio::test]
    async fn disconnect_under_lockdown_installs_the_block_before_reporting_disconnected() {
        // Lockdown: the network must never be open after a disconnect. The
        // standalone block is installed (own artifact, so the engine teardown
        // cannot clear it) and only then is the session torn down.
        let (mut client_end, recording, serve) = spawn_serve(true);

        send_frame(&mut client_end, br#"{"type":"disconnect"}"#).await;
        let _draining = read_event(&mut client_end).await;
        let disconnected = read_event(&mut client_end).await;
        assert_eq!(
            disconnected,
            serde_json::json!({"type": "state", "state": "disconnected"})
        );

        let calls = recording.calls();
        assert!(
            block_install_ran(&calls),
            "the lockdown block must be installed; calls: {calls:?}"
        );
        let install_pos = calls
            .iter()
            .position(|(_, args, stdin)| {
                (args == &["-f", "-"] || args.contains(&"-f".to_owned())) && stdin.is_some()
            })
            .expect("install call");
        let engine_sweep_pos = calls.iter().position(|(program, args, _)| {
            (program == "nft"
                && args.first().map(String::as_str) == Some("delete")
                && args.iter().any(|a| a == netblock::ENGINE_NFT_TABLE))
                || (program == "pfctl"
                    && args.contains(&"-F".to_owned())
                    && args.iter().any(|a| a == netblock::ENGINE_PF_ANCHOR))
        });
        if let Some(sweep) = engine_sweep_pos {
            assert!(
                install_pos < sweep,
                "the lockdown block must be up BEFORE the engine artifact is \
                 swept, else there is an open instant; calls: {calls:?}"
            );
        }

        drop(client_end);
        serve.await.expect("serve task").expect("clean end");
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
