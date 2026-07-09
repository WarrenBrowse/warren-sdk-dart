//! In-tunnel egress liveness probe for the proxy datapath (warren-core
//! doc 62 item 5, mirrored from the desktop app).
//!
//! An exit that is drained or half-swapped during a fleet rollout keeps
//! ACKing QUIC keep-alives, so the supervisor's RX-silence dead-path
//! watch never fires and the session stays `Connected` while zero
//! traffic gets through. This probe proves real end-to-end egress: a
//! periodic TCP CONNECT through the session's own local SOCKS5 endpoint
//! to a fixed anycast address, which the engine tunnels through the
//! exit exactly like app traffic (it can never leak outside the
//! tunnel: it enters the datapath the same way every proxied byte
//! does).
//!
//! Verdict semantics mirror the desktop app: N consecutive failures
//! while the session is `Connected` publish `egress_dead = true`; a
//! single success clears it; any state other than `Connected` resets
//! the count and clears the verdict (those states already tell the
//! truth on their own). Env knobs are shared with the app:
//! `WARREN_EGRESS_PROBE` (`0` disables),
//! `WARREN_EGRESS_PROBE_INTERVAL_SECS`, `WARREN_EGRESS_PROBE_FAILURES`.

use std::net::SocketAddr;
use std::time::Duration;

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::watch;
use warren_sdk::ConnectionState;

const DEFAULT_INTERVAL: Duration = Duration::from_secs(25);
const INTERVAL_RANGE_SECS: std::ops::RangeInclusive<u64> = 5..=600;
const DEFAULT_FAILURE_THRESHOLD: u32 = 3;
const FAILURE_RANGE: std::ops::RangeInclusive<u32> = 1..=10;

/// Fixed anycast probe target (Cloudflare `1.1.1.1:443`): globally
/// reachable, indistinguishable from ordinary traffic, and the connect
/// originates from the exit's IP like every proxied byte.
const PROBE_TARGET: [u8; 4] = [1, 1, 1, 1];
const PROBE_PORT: u16 = 443;
/// Overall budget for one probe (SOCKS handshake + tunneled connect).
const PROBE_TIMEOUT: Duration = Duration::from_secs(6);

/// Resolved probe settings (env knobs applied once per session).
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct EgressProbeConfig {
    pub enabled: bool,
    pub interval: Duration,
    pub failure_threshold: u32,
}

impl EgressProbeConfig {
    pub fn from_env() -> Self {
        Self::resolve(
            std::env::var("WARREN_EGRESS_PROBE").ok().as_deref(),
            std::env::var("WARREN_EGRESS_PROBE_INTERVAL_SECS")
                .ok()
                .as_deref(),
            std::env::var("WARREN_EGRESS_PROBE_FAILURES")
                .ok()
                .as_deref(),
        )
    }

    /// Pure resolution: invalid or out-of-range values keep the
    /// default rather than clamping, so a typo never silently changes
    /// the probe cadence.
    fn resolve(enable: Option<&str>, interval: Option<&str>, failures: Option<&str>) -> Self {
        let enabled = enable.map(str::trim) != Some("0");
        let interval = match interval.map(|raw| raw.trim().parse::<u64>()) {
            Some(Ok(secs)) if INTERVAL_RANGE_SECS.contains(&secs) => Duration::from_secs(secs),
            _ => DEFAULT_INTERVAL,
        };
        let failure_threshold = match failures.map(|raw| raw.trim().parse::<u32>()) {
            Some(Ok(n)) if FAILURE_RANGE.contains(&n) => n,
            _ => DEFAULT_FAILURE_THRESHOLD,
        };
        Self {
            enabled,
            interval,
            failure_threshold,
        }
    }
}

/// IO surface consumed by [`run_scheduler`]; mocked in tests.
pub(crate) trait ProbeIo {
    /// Waits for the next tick. `false` = teardown, the loop exits.
    async fn next_tick(&mut self) -> bool;
    /// `true` while the datapath state is `Connected`.
    fn connected(&mut self) -> bool;
    /// One end-to-end probe through the tunnel. `true` = egress alive.
    async fn probe(&mut self) -> bool;
    /// Publishes the verdict (edge-triggered by the scheduler).
    fn publish(&mut self, egress_dead: bool);
}

/// Verdict scheduler: mirrors the desktop app (`talpid-warren-tunnel::
/// egress_probe`). Consecutive-failure counting, one-success clear,
/// non-connected states reset the count AND clear the verdict.
pub(crate) async fn run_scheduler<I: ProbeIo>(io: &mut I, failure_threshold: u32) {
    let mut consecutive_failures: u32 = 0;
    let mut dead = false;
    loop {
        if !io.next_tick().await {
            return;
        }
        if !io.connected() {
            // Reconnecting/Draining/Failed already tell the truth in the
            // state stream, and a redial may land on a different exit:
            // reset the count AND clear a stale dead verdict so the next
            // exit is judged fresh (never inherits the old one's).
            consecutive_failures = 0;
            if dead {
                dead = false;
                io.publish(false);
            }
            continue;
        }
        if io.probe().await {
            consecutive_failures = 0;
            if dead {
                dead = false;
                io.publish(false);
            }
        } else {
            consecutive_failures = consecutive_failures.saturating_add(1);
            if !dead && consecutive_failures >= failure_threshold {
                dead = true;
                io.publish(true);
            }
        }
    }
}

/// One TCP CONNECT probe through the local SOCKS5 endpoint: no-auth
/// greeting, then CONNECT to [`PROBE_TARGET`]:[`PROBE_PORT`]. A `0x00`
/// reply code means the engine established the connection through the
/// exit, proving end-to-end egress. Local dial errors against our own
/// listener are also failures: the proxy front-end dying is not
/// healthy egress either.
pub(crate) async fn probe_via_socks5(socks: SocketAddr) -> bool {
    tokio::time::timeout(PROBE_TIMEOUT, async {
        let mut stream = tokio::net::TcpStream::connect(socks).await.ok()?;
        stream.write_all(&[0x05, 0x01, 0x00]).await.ok()?;
        let mut greeting = [0u8; 2];
        stream.read_exact(&mut greeting).await.ok()?;
        if greeting != [0x05, 0x00] {
            return None;
        }
        let mut req = Vec::with_capacity(10);
        req.extend_from_slice(&[0x05, 0x01, 0x00, 0x01]);
        req.extend_from_slice(&PROBE_TARGET);
        req.extend_from_slice(&PROBE_PORT.to_be_bytes());
        stream.write_all(&req).await.ok()?;
        // Reply: VER REP RSV ATYP BND.ADDR BND.PORT; REP (byte 1) == 0
        // = success. Any non-zero REP (host unreachable, refused, ...)
        // means the engine could not egress through the exit.
        let mut reply = [0u8; 4];
        stream.read_exact(&mut reply).await.ok()?;
        (reply[0] == 0x05 && reply[1] == 0x00).then_some(())
    })
    .await
    .ok()
    .flatten()
    .is_some()
}

/// Production probe loop attached to one session: gates on the
/// engine's state watch, probes through the session's own SOCKS5
/// endpoint and publishes verdict edges on `egress_tx`. Exits when the
/// state channel closes (session torn down) via the tick returning
/// early on a closed channel being irrelevant: the task is aborted by
/// `WarrenSessionFrb::disconnect`, and the runtime drop covers leaks.
pub(crate) async fn run(
    socks: SocketAddr,
    state_rx: watch::Receiver<ConnectionState>,
    egress_tx: watch::Sender<bool>,
) {
    let cfg = EgressProbeConfig::from_env();
    if !cfg.enabled {
        return;
    }
    struct RealIo {
        interval: Duration,
        socks: SocketAddr,
        state_rx: watch::Receiver<ConnectionState>,
        egress_tx: watch::Sender<bool>,
    }
    impl ProbeIo for RealIo {
        async fn next_tick(&mut self) -> bool {
            // +/-15% jitter so a fleet of clients never probes in lockstep.
            let fraction = fastrand_fraction();
            tokio::time::sleep(self.interval.mul_f64(0.85 + 0.3 * fraction)).await;
            true
        }
        fn connected(&mut self) -> bool {
            matches!(*self.state_rx.borrow(), ConnectionState::Connected)
        }
        async fn probe(&mut self) -> bool {
            probe_via_socks5(self.socks).await
        }
        fn publish(&mut self, egress_dead: bool) {
            let _ = self.egress_tx.send(egress_dead);
        }
    }
    let mut io = RealIo {
        interval: cfg.interval,
        socks,
        state_rx,
        egress_tx,
    };
    run_scheduler(&mut io, cfg.failure_threshold).await;
}

/// Cheap uniform fraction in `[0, 1)` without a rand dependency: the
/// jitter only needs to decorrelate clients, not be unpredictable.
fn fastrand_fraction() -> f64 {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.subsec_nanos())
        .unwrap_or(0);
    f64::from(nanos % 1_000_000) / 1_000_000.0
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::VecDeque;

    #[test]
    fn config_defaults_and_knobs() {
        let cfg = EgressProbeConfig::resolve(None, None, None);
        assert!(cfg.enabled);
        assert_eq!(cfg.interval, DEFAULT_INTERVAL);
        assert_eq!(cfg.failure_threshold, DEFAULT_FAILURE_THRESHOLD);
        assert!(!EgressProbeConfig::resolve(Some("0"), None, None).enabled);
        let cfg = EgressProbeConfig::resolve(None, Some("40"), Some("2"));
        assert_eq!(cfg.interval, Duration::from_secs(40));
        assert_eq!(cfg.failure_threshold, 2);
        // Out-of-range values keep the defaults, never clamp.
        let cfg = EgressProbeConfig::resolve(None, Some("1"), Some("0"));
        assert_eq!(cfg.interval, DEFAULT_INTERVAL);
        assert_eq!(cfg.failure_threshold, DEFAULT_FAILURE_THRESHOLD);
    }

    /// Scripted mock: one entry per tick. `None` = not connected,
    /// `Some(ok)` = connected with that probe result.
    struct MockIo {
        script: VecDeque<Option<bool>>,
        published: Vec<bool>,
    }

    impl MockIo {
        fn scripted(script: impl IntoIterator<Item = Option<bool>>) -> Self {
            Self {
                script: script.into_iter().collect(),
                published: Vec::new(),
            }
        }
    }

    impl ProbeIo for MockIo {
        async fn next_tick(&mut self) -> bool {
            !self.script.is_empty()
        }
        fn connected(&mut self) -> bool {
            if self.script.front().expect("gated by next_tick").is_some() {
                true
            } else {
                self.script.pop_front();
                false
            }
        }
        async fn probe(&mut self) -> bool {
            self.script
                .pop_front()
                .flatten()
                .expect("probe only runs while connected")
        }
        fn publish(&mut self, egress_dead: bool) {
            self.published.push(egress_dead);
        }
    }

    #[tokio::test]
    async fn verdict_fires_only_at_threshold_and_clears_on_success() {
        let mut io = MockIo::scripted([Some(false), Some(false), Some(true)]);
        run_scheduler(&mut io, 3).await;
        assert!(
            io.published.is_empty(),
            "sub-threshold failures must never publish (rollout blip)"
        );

        let mut io = MockIo::scripted([Some(false), Some(false), Some(false), Some(true)]);
        run_scheduler(&mut io, 3).await;
        assert_eq!(
            io.published,
            vec![true, false],
            "threshold publishes dead once; one success clears it"
        );
    }

    #[tokio::test]
    async fn leaving_connected_resets_count_and_clears_the_verdict() {
        // dead verdict, then a reconnect window: the verdict must clear
        // (the state stream already reports Reconnecting) and the count
        // restarts on the new exit.
        let mut io = MockIo::scripted([Some(false), Some(false), None, Some(false)]);
        run_scheduler(&mut io, 2).await;
        assert_eq!(
            io.published,
            vec![true, false],
            "a non-connected tick clears the stale verdict; the single \
             post-redial failure must not re-fire at threshold 2"
        );
    }

    #[tokio::test]
    async fn never_probes_while_not_connected() {
        // All ticks disconnected: probe() would panic (script entries
        // are None), so completing without a panic proves the gate.
        let mut io = MockIo::scripted([None, None, None]);
        run_scheduler(&mut io, 1).await;
        assert!(io.published.is_empty());
    }

    /// Fake SOCKS5 server scripting one session: reads the greeting +
    /// request, answers with `reply_code`.
    async fn fake_socks5(reply_code: u8) -> SocketAddr {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind fake socks");
        let addr = listener.local_addr().expect("local addr");
        tokio::spawn(async move {
            if let Ok((mut stream, _)) = listener.accept().await {
                let mut greeting = [0u8; 3];
                if stream.read_exact(&mut greeting).await.is_err() {
                    return;
                }
                let _ = stream.write_all(&[0x05, 0x00]).await;
                let mut req = [0u8; 10];
                if stream.read_exact(&mut req).await.is_err() {
                    return;
                }
                let _ = stream
                    .write_all(&[0x05, reply_code, 0x00, 0x01, 0, 0, 0, 0, 0, 0])
                    .await;
            }
        });
        addr
    }

    #[tokio::test]
    async fn socks5_probe_succeeds_on_a_zero_reply() {
        let addr = fake_socks5(0x00).await;
        assert!(
            probe_via_socks5(addr).await,
            "REP=0x00 means the engine connected through the exit"
        );
    }

    #[tokio::test]
    async fn socks5_probe_fails_on_an_error_reply() {
        // 0x04 = host unreachable: the engine could not egress.
        let addr = fake_socks5(0x04).await;
        assert!(!probe_via_socks5(addr).await);
    }

    #[tokio::test]
    async fn socks5_probe_fails_when_the_listener_is_gone() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind");
        let addr = listener.local_addr().expect("local addr");
        drop(listener);
        assert!(
            !probe_via_socks5(addr).await,
            "a dead proxy front-end is not healthy egress"
        );
    }
}
