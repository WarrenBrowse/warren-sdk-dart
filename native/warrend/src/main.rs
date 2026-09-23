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

use std::ffi::OsString;
use std::os::fd::AsRawFd;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use anyhow::{Context, Result};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{UnixListener, UnixStream};
use warren_sdk::discovery::VerifiedExit;
use warren_sdk::identity::WarrenIdentity;
use warren_sdk::{SdkError, TunDatapathHandle, WarrenClient};
use zeroize::Zeroize;

/// The control-plane HTTP transport warrend's client egresses through.
///
/// On Linux it is the socket-marked transport: its TCP sockets carry the Warren
/// tunnel fwmark so the tightened `meta mark` connecting guard permits warrend's
/// OWN control-plane fetch while every other process, even root-owned, stays
/// blocked. Off Linux (macOS pf guard is still owner-uid) the bundled reqwest
/// transport is used unchanged. warrend runs as root, so `SO_MARK` succeeds.
#[cfg(target_os = "linux")]
type CpTransport = warren_sdk::api::MarkedTransport;
#[cfg(not(target_os = "linux"))]
type CpTransport = warren_sdk::api::ReqwestTransport;

/// warrend's high-level client over [`CpTransport`].
type CpClient = WarrenClient<CpTransport>;

/// Builds the control-plane transport for the current platform (marked on Linux).
fn build_cp_transport() -> Result<CpTransport, warren_sdk::api::TransportError> {
    #[cfg(target_os = "linux")]
    {
        CpTransport::marked()
    }
    #[cfg(not(target_os = "linux"))]
    {
        CpTransport::try_new()
    }
}

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

/// The only directories the daemon, and every tool the engine spawns on its
/// behalf, resolve programs from. The daemon runs as root and sudo passes the
/// caller's PATH through unless the host sets `secure_path` (macOS does not), so
/// an inherited PATH would let the launching account pick what root runs as
/// `pfctl`, `route`, `networksetup` or `nft`.
const DAEMON_PATH: &str = "/usr/sbin:/usr/bin:/sbin:/bin";

/// What the daemon keeps from the environment it was launched with: sudo's
/// record of the invoking account, which names the peer allowed to drive it.
const KEPT_VARIABLES: [&str; 2] = ["SUDO_UID", "SUDO_GID"];

/// The environment the daemon runs with, derived from the one it inherited.
fn daemon_environment(
    inherited: impl IntoIterator<Item = (OsString, OsString)>,
) -> Vec<(OsString, OsString)> {
    let mut environment: Vec<(OsString, OsString)> = inherited
        .into_iter()
        .filter(|(key, _)| KEPT_VARIABLES.iter().any(|kept| key == kept))
        .collect();
    environment.push(("PATH".into(), DAEMON_PATH.into()));
    environment
}

/// Replaces the process environment with [`daemon_environment`]. Runs first in
/// `main`, while the process is still single-threaded: the environment is
/// process-global and mutating it is unsound once another thread may read it.
fn reset_environment() {
    let environment = daemon_environment(std::env::vars_os());
    for (key, _) in std::env::vars_os() {
        std::env::remove_var(key);
    }
    for (key, value) in environment {
        std::env::set_var(key, value);
    }
}

fn main() -> Result<()> {
    reset_environment();
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
    client: Option<CpClient>,
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

/// The firewall side of a connect, as the orchestration needs it. Abstracted so
/// the fail-closed ordering (guard up before any teardown; the prior session
/// torn down before the new one installs its rules) is unit-testable with a fake:
/// a real [`TunDatapathHandle`] needs a privileged device, and the collision the
/// orchestration prevents lives in that handle's RAII drop.
#[allow(async_fn_in_trait)]
trait ConnectFirewall {
    /// Whether a dead predecessor's engine kill-switch block is installed.
    async fn engine_held(&self) -> Result<bool>;
    /// Install the connecting guard: block all but loopback, DHCP and warrend's
    /// own uid, so the dial egresses while every other app stays blocked.
    async fn install_guard(&self) -> Result<()>;
    /// Drop the connecting guard once the session's engine kill-switch protects.
    async fn clear_guard(&self) -> Result<()>;
    /// Remove a dead predecessor's engine block so warrend's own root dial is not
    /// dropped by its chain.
    async fn clear_stale_engine(&self) -> Result<()>;
    /// Install the strict lockdown block (fail closed after a failed dial).
    async fn install_lockdown(&self) -> Result<()>;
    /// Restore the host network (a non-lockdown reconnect whose dial failed).
    async fn restore(&self) -> Result<()>;
}

/// Production [`ConnectFirewall`]: the real nft/pf backend via the command runner.
struct RealFirewall<'a> {
    runner: &'a Arc<dyn CmdRunner>,
}

impl ConnectFirewall for RealFirewall<'_> {
    async fn engine_held(&self) -> Result<bool> {
        run_netblock(self.runner, |b, r| b.engine_block_present(r)).await
    }
    async fn install_guard(&self) -> Result<()> {
        run_netblock(self.runner, |b, r| b.install_connecting_guard(r)).await
    }
    async fn clear_guard(&self) -> Result<()> {
        run_netblock(self.runner, |b, r| b.clear_lockdown(r).map(|_| ())).await
    }
    async fn clear_stale_engine(&self) -> Result<()> {
        run_netblock(self.runner, |b, r| b.clear_engine_block(r).map(|_| ())).await
    }
    async fn install_lockdown(&self) -> Result<()> {
        run_netblock(self.runner, |b, r| b.install_lockdown(r)).await
    }
    async fn restore(&self) -> Result<()> {
        run_netblock(self.runner, netblock::revert_network)
            .await
            .map(|_| ())
    }
}

/// Orchestrates the firewall around one connect, fail-closed at every step.
///
/// The window this closes: the old code LIFTED the whole firewall before the
/// control-plane dial (every app on the host could egress during a lockdown
/// connect), and on a replace-connect it installed the new session's rules
/// BEFORE dropping the old handle whose RAII flush targets the SAME engine
/// kill-switch table, so the old teardown wiped the successor's protection.
///
/// Both are fixed here: a connecting guard (warrend's OWN table, permitting only
/// loopback, DHCP and warrend's uid) goes up before anything is torn down, and on
/// a reconnect the prior session is dropped BEFORE the new one is brought up, so
/// the shared engine table is never flushed out from under the successor.
///
/// On success the handle is stored in `slot` and the guard is dropped (the
/// session's own engine kill-switch then protects). On failure the network is
/// held closed (lockdown or a held block) or restored (a non-lockdown reconnect,
/// now disconnected).
async fn connect_orchestrated<H, Fut>(
    slot: &Arc<Mutex<Option<H>>>,
    fw: &impl ConnectFirewall,
    lockdown: bool,
    bring_up: impl FnOnce() -> Fut,
) -> Result<(), Event>
where
    Fut: std::future::Future<Output = Result<H, Event>>,
{
    let reconnect = slot.lock().expect("tunnel mutex").is_some();
    // A block already in force before this connect: a dead predecessor's engine
    // block, or lockdown mode. Only then must the dial stay protected rather than
    // running with the firewall fully open (the plain non-lockdown connect keeps
    // dialing in the open, unchanged). A reconnect always needs the guard: the
    // swap tears the live session down and must not leak in between.
    let engine_held = if reconnect {
        false
    } else {
        fw.engine_held()
            .await
            .map_err(|e| Event::error("tunnel", e.to_string()))?
    };
    let guard = reconnect || engine_held || lockdown;

    if guard {
        // Fail-closed ordering: the connecting guard goes up BEFORE any teardown,
        // so there is never an instant with the network open.
        fw.install_guard()
            .await
            .map_err(|e| Event::error("tunnel", e.to_string()))?;
    }
    if reconnect {
        // Drop the prior session BEFORE the new one installs its rules: both share
        // the engine's single kill-switch table, so the old RAII teardown would
        // otherwise flush the successor's protection (a leak on every reconnect).
        // The guard installed above bridges the gap.
        let prior = slot.lock().expect("tunnel mutex").take();
        drop(prior);
    } else if engine_held {
        // The guard now protects, so the dead predecessor's engine block (which
        // would drop warrend's own root dial) can go.
        fw.clear_stale_engine()
            .await
            .map_err(|e| Event::error("tunnel", e.to_string()))?;
    }

    match bring_up().await {
        Ok(handle) => {
            *slot.lock().expect("tunnel mutex") = Some(handle);
            if guard {
                // The session's engine kill-switch now protects; drop the bridging
                // guard so it does not shadow the live datapath. Best-effort: a
                // failure over-blocks (fail-closed), it never opens the network.
                if let Err(error) = fw.clear_guard().await {
                    eprintln!("warrend: clearing the connecting guard failed: {error}");
                }
            }
            Ok(())
        }
        Err(event) => {
            if guard {
                let result = if lockdown || engine_held {
                    fw.install_lockdown().await
                } else {
                    // Non-lockdown reconnect: the prior session is gone, so the
                    // host is now disconnected, which under non-lockdown means the
                    // network is restored.
                    fw.restore().await
                };
                if let Err(error) = result {
                    eprintln!(
                        "warrend: fail-closed cleanup after a failed connect failed: {error}"
                    );
                }
            }
            Err(event)
        }
    }
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
            let transport = build_cp_transport().map_err(|e| Event::error("api", e.to_string()))?;
            let client = builder
                .build_with_transport(transport)
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
            // The dial no longer LIFTS the firewall (that opened the whole host on
            // every lockdown connect). A connecting guard protects the window and,
            // on a reconnect, the prior session is torn down before the new one
            // installs its rules so the shared engine kill-switch table is not
            // flushed out from under the successor. Datapath scope note: the engine
            // idle-cover IS armed on this TUN path; the in-tunnel egress liveness
            // probe is not (it lives in the in-process proxy glue).
            let fw = RealFirewall { runner };
            connect_orchestrated(tunnel, &fw, lockdown.load(Ordering::SeqCst), || {
                connect_session(client, &exit_pubkey_hex)
            })
            .await
            .map(|()| Some(Event::state(ConnState::Connected)))
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
    client: &CpClient,
    exit_pubkey_hex: &str,
) -> Result<TunDatapathHandle, Event> {
    let exit = find_exit(client, exit_pubkey_hex).await?;
    // An empty name lets the OS pick the TUN interface.
    client
        .start_tun_multihop(&exit, "")
        .await
        .map_err(map_sdk_error)
}

async fn find_exit(client: &CpClient, exit_pubkey_hex: &str) -> Result<VerifiedExit, Event> {
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

    #[test]
    fn the_daemon_environment_keeps_only_the_sudo_invoker_and_a_fixed_path() {
        // Proxy and certificate variables would steer the root daemon's own
        // control-plane client; only sudo's record of the invoker survives.
        let inherited = [
            ("PATH", "/Users/someone/bin:/usr/bin"),
            ("SUDO_UID", "501"),
            ("SUDO_GID", "20"),
            ("HOME", "/Users/someone"),
            ("HTTPS_PROXY", "http://127.0.0.1:8080"),
            ("SSL_CERT_FILE", "/Users/someone/ca.pem"),
        ]
        .map(|(key, value)| (OsString::from(key), OsString::from(value)));

        let mut environment = daemon_environment(inherited);
        environment.sort();

        let expected = [
            ("PATH", DAEMON_PATH),
            ("SUDO_GID", "20"),
            ("SUDO_UID", "501"),
        ]
        .map(|(key, value)| (OsString::from(key), OsString::from(value)));
        assert_eq!(environment, expected);
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

/// Behavioral tests for the connect firewall orchestration. A real
/// [`TunDatapathHandle`] needs a privileged device, so a fake session models the
/// one thing that matters for these invariants: the engine's SINGLE kill-switch
/// table, which a session's bring-up installs and its RAII drop flushes. Two
/// sessions sharing that one table is exactly the replace-connect collision, so
/// the fake reproduces it faithfully and the tests fail if the ordering fix is
/// reverted.
#[cfg(test)]
mod connect_orchestration_tests {
    use super::*;

    /// A shared, ordered timeline plus the two pieces of protection state.
    #[derive(Default)]
    struct Timeline {
        events: Mutex<Vec<&'static str>>,
        /// The engine's ONE kill-switch table: bring-up installs it, a session's
        /// RAII drop flushes it UNCONDITIONALLY (like `nft delete table`), which
        /// is why a successor sharing the table can be wiped by a predecessor.
        engine_table_present: AtomicBool,
        /// A warrend-owned block (connecting guard or strict lockdown) holds.
        warrend_block: AtomicBool,
    }

    impl Timeline {
        fn push(&self, e: &'static str) {
            self.events.lock().expect("events").push(e);
        }
        fn events(&self) -> Vec<&'static str> {
            self.events.lock().expect("events").clone()
        }
        /// The host is protected iff SOME block holds (the engine table or a
        /// warrend block). The whole point of the guard is that this is never
        /// false across a swap.
        fn protected(&self) -> bool {
            self.engine_table_present.load(Ordering::SeqCst)
                || self.warrend_block.load(Ordering::SeqCst)
        }
    }

    /// A fake datapath session: its bring-up installed the engine table, its drop
    /// flushes it (unconditional, mirroring the engine's `nft delete table`).
    struct FakeSession {
        tl: Arc<Timeline>,
    }

    impl Drop for FakeSession {
        fn drop(&mut self) {
            self.tl.engine_table_present.store(false, Ordering::SeqCst);
            self.tl.push("session_teardown");
        }
    }

    struct FakeFirewall {
        tl: Arc<Timeline>,
        engine_held: bool,
    }

    impl ConnectFirewall for FakeFirewall {
        async fn engine_held(&self) -> Result<bool> {
            Ok(self.engine_held)
        }
        async fn install_guard(&self) -> Result<()> {
            self.tl.warrend_block.store(true, Ordering::SeqCst);
            self.tl.push("guard_install");
            Ok(())
        }
        async fn clear_guard(&self) -> Result<()> {
            self.tl.warrend_block.store(false, Ordering::SeqCst);
            self.tl.push("guard_clear");
            Ok(())
        }
        async fn clear_stale_engine(&self) -> Result<()> {
            self.tl.engine_table_present.store(false, Ordering::SeqCst);
            self.tl.push("clear_stale_engine");
            Ok(())
        }
        async fn install_lockdown(&self) -> Result<()> {
            self.tl.warrend_block.store(true, Ordering::SeqCst);
            self.tl.push("install_lockdown");
            Ok(())
        }
        async fn restore(&self) -> Result<()> {
            self.tl.warrend_block.store(false, Ordering::SeqCst);
            self.tl.push("restore");
            Ok(())
        }
    }

    fn slot_with(session: Option<FakeSession>) -> Arc<Mutex<Option<FakeSession>>> {
        Arc::new(Mutex::new(session))
    }

    /// Index of the first occurrence of `e` in the timeline.
    fn at(events: &[&'static str], e: &str) -> usize {
        events
            .iter()
            .position(|x| *x == e)
            .unwrap_or_else(|| panic!("event {e:?} never happened in {events:?}"))
    }

    #[tokio::test]
    async fn reconnect_tears_the_prior_session_down_before_the_new_one_installs_its_rules() {
        // The replace-connect collision: the old and new sessions share the ONE
        // engine kill-switch table, so if the new rules are installed before the
        // old handle drops, the old RAII teardown flushes the successor's
        // protection. The fix drops the prior session FIRST, bridged by the guard.
        let tl = Arc::new(Timeline::default());
        // A live prior session: its engine table is up.
        tl.engine_table_present.store(true, Ordering::SeqCst);
        let slot = slot_with(Some(FakeSession { tl: tl.clone() }));
        let fw = FakeFirewall {
            tl: tl.clone(),
            engine_held: false,
        };

        let bring = {
            let tl = tl.clone();
            move || async move {
                tl.engine_table_present.store(true, Ordering::SeqCst);
                tl.push("new_up");
                Ok(FakeSession { tl })
            }
        };
        connect_orchestrated(&slot, &fw, false, bring)
            .await
            .expect("reconnect succeeds");

        let events = tl.events();
        assert!(
            at(&events, "guard_install") < at(&events, "session_teardown"),
            "the guard must be up BEFORE the prior session is torn down: {events:?}"
        );
        assert!(
            at(&events, "session_teardown") < at(&events, "new_up"),
            "the prior session must be torn down BEFORE the new one installs its \
             rules, else the old teardown flushes the successor's table: {events:?}"
        );
        assert!(
            tl.engine_table_present.load(Ordering::SeqCst),
            "the new session's kill-switch table must survive the swap (this goes \
             red if the fix is reverted to install-before-teardown): {events:?}"
        );
        assert!(
            slot.lock().expect("slot").is_some(),
            "the new session must be stored"
        );
    }

    #[tokio::test]
    async fn a_lockdown_connect_guards_the_dial_instead_of_lifting_the_firewall() {
        // Item 1: a lockdown connect must NOT open the whole host for the dial. The
        // connecting guard holds for the whole dial and is only dropped once the
        // session's own kill-switch is up, so the host is protected throughout.
        let tl = Arc::new(Timeline::default());
        let slot = slot_with(None);
        let fw = FakeFirewall {
            tl: tl.clone(),
            engine_held: false,
        };
        let bring = {
            let tl = tl.clone();
            move || async move {
                tl.engine_table_present.store(true, Ordering::SeqCst);
                tl.push("new_up");
                Ok(FakeSession { tl })
            }
        };
        connect_orchestrated(&slot, &fw, true, bring)
            .await
            .expect("connect succeeds");

        let events = tl.events();
        assert_eq!(
            events,
            ["guard_install", "new_up", "guard_clear"],
            "a lockdown connect installs the guard, dials, then drops the guard \
             once the session protects, and never lifts the firewall: {events:?}"
        );
        assert!(
            at(&events, "guard_install") < at(&events, "new_up"),
            "the guard must protect the dial window: {events:?}"
        );
    }

    #[tokio::test]
    async fn a_failed_lockdown_connect_holds_the_block_closed() {
        // Fail-closed: a lockdown dial that fails must leave the network blocked.
        let tl = Arc::new(Timeline::default());
        let slot = slot_with(None);
        let fw = FakeFirewall {
            tl: tl.clone(),
            engine_held: false,
        };
        let bring = || async { Err(Event::error("tunnel", "dial failed")) };
        let result = connect_orchestrated(&slot, &fw, true, bring).await;
        assert!(result.is_err(), "the failure must surface");
        assert!(
            tl.events().contains(&"install_lockdown"),
            "a failed lockdown connect must install the strict block: {:?}",
            tl.events()
        );
        assert!(
            tl.protected(),
            "the host must stay protected after a failed lockdown connect"
        );
        assert!(slot.lock().expect("slot").is_none(), "no session is stored");
    }

    #[tokio::test]
    async fn a_plain_connect_with_no_block_held_dials_in_the_open_unchanged() {
        // A plain non-lockdown connect with nothing held keeps its prior behaviour:
        // no guard, dial in the open. Installing a guard here would newly block a
        // non-lockdown user's apps during connect (a behaviour regression).
        let tl = Arc::new(Timeline::default());
        let slot = slot_with(None);
        let fw = FakeFirewall {
            tl: tl.clone(),
            engine_held: false,
        };
        let bring = {
            let tl = tl.clone();
            move || async move {
                tl.engine_table_present.store(true, Ordering::SeqCst);
                tl.push("new_up");
                Ok(FakeSession { tl })
            }
        };
        connect_orchestrated(&slot, &fw, false, bring)
            .await
            .expect("connect succeeds");
        assert_eq!(
            tl.events(),
            ["new_up"],
            "no guard is installed for a plain connect with nothing held: {:?}",
            tl.events()
        );
    }

    #[tokio::test]
    async fn a_fresh_connect_over_a_stale_engine_block_guards_then_clears_it() {
        // A dead predecessor's engine block would drop warrend's own root dial, so
        // the guard goes up first (protecting), then the stale block is cleared.
        let tl = Arc::new(Timeline::default());
        tl.engine_table_present.store(true, Ordering::SeqCst);
        let slot = slot_with(None);
        let fw = FakeFirewall {
            tl: tl.clone(),
            engine_held: true,
        };
        let bring = {
            let tl = tl.clone();
            move || async move {
                tl.engine_table_present.store(true, Ordering::SeqCst);
                tl.push("new_up");
                Ok(FakeSession { tl })
            }
        };
        connect_orchestrated(&slot, &fw, false, bring)
            .await
            .expect("connect succeeds");
        let events = tl.events();
        assert!(
            at(&events, "guard_install") < at(&events, "clear_stale_engine"),
            "the guard must be up before the stale engine block is cleared, so the \
             host is never open: {events:?}"
        );
        assert!(
            at(&events, "clear_stale_engine") < at(&events, "new_up"),
            "the stale block must be cleared before the dial (else the dial is \
             blocked by the dead chain): {events:?}"
        );
    }
}
