//! Proxy datapath session.
//!
//! Wraps the engine's self-healing supervised proxy behind an opaque handle and
//! streams its connection-state transitions across the bridge. The datapath
//! logic lives entirely in the audited engine; this is endpoint exposure, a
//! state forwarder and teardown.

use std::net::SocketAddr;
use std::sync::Mutex;

use flutter_rust_bridge::frb;
use tokio::sync::watch::Receiver;
use warren_sdk::api::BanReasonCode;
use warren_sdk::net::MapProto;
use warren_sdk::transport::FatalCause;
use warren_sdk::{
    ConnectionState, MigrationEvent, MigrationOutcome, PortFollowConfig, PortFollowOutcome,
    PortFollowPolicy, SupervisedForwardedPort, SupervisedProxyHandle,
};

use crate::api::error::{WarrenErrorKind, WarrenFfiError};
use crate::frb_generated::StreamSink;

/// Lifecycle state of a connection, mirrored for Dart as a plain enum.
pub enum ConnectionStateDto {
    /// The initial connect attempt is in flight.
    Connecting,
    /// A connection is established.
    Connected,
    /// A previous attempt failed; a retry is in flight after backoff.
    Reconnecting,
    /// The exit signalled a planned maintenance drain and the supervisor is
    /// proactively migrating off it (ADR 36). Distinct from failure-driven
    /// `Reconnecting` so an app can show a "switching server" hint; followed by
    /// `Connected`.
    Draining,
    /// Every attempt failed; the supervisor gave up.
    Failed,
}

/// Why the supervisor stopped for good, mirrored for Dart as a plain enum.
///
/// The engine owns this classification; the bridge maps it, it never re-decides.
/// Read alongside the terminal [`ConnectionStateDto::Failed`] via
/// [`WarrenSessionFrb::fatal_cause`]: a present cause is precisely the "no redial
/// or other exit helps, tell the user" signal, so a consumer stops retrying
/// instead of looping `Reconnecting` forever. A `Failed` reached by mere retry
/// exhaustion carries NO cause (the accessor returns `None`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum WarrenFatalCauseDto {
    /// The identity has no active subscription, or is not in the exit allowlist.
    /// The user must provision or renew; retrying reproduces it.
    NotAuthorized,
    /// The account already holds its maximum simultaneous devices.
    DeviceLimit,
    /// The exit closed with the opaque policy-rejection code and no sealed cause
    /// arrived: definitive, but the specific reason is unknown to the client.
    PolicyRefused,
    /// The wallet is banned (on the signed revocation list): suspended until
    /// the ban lapses or is lifted. Renewing does not help.
    Banned,
}

fn fatal_to_dto(cause: FatalCause) -> WarrenFatalCauseDto {
    match cause {
        FatalCause::NotAuthorized => WarrenFatalCauseDto::NotAuthorized,
        FatalCause::DeviceLimit => WarrenFatalCauseDto::DeviceLimit,
        FatalCause::PolicyRefused => WarrenFatalCauseDto::PolicyRefused,
        FatalCause::Banned => WarrenFatalCauseDto::Banned,
        // `FatalCause` is `#[non_exhaustive]`. A future fatal kind is still a
        // definitive refusal (never retryable), so surface it as the opaque
        // `PolicyRefused` rather than dropping the "stop" signal.
        _ => WarrenFatalCauseDto::PolicyRefused,
    }
}

fn to_dto(state: ConnectionState) -> ConnectionStateDto {
    match state {
        ConnectionState::Connecting => ConnectionStateDto::Connecting,
        ConnectionState::Connected => ConnectionStateDto::Connected,
        ConnectionState::Reconnecting => ConnectionStateDto::Reconnecting,
        // A maintenance drain is a planned migration, NOT a failure: the
        // supervised proxy never gives up, so mapping this to `Failed` would show
        // a spurious terminal error during a routine exit drain.
        ConnectionState::Draining => ConnectionStateDto::Draining,
        ConnectionState::Failed => ConnectionStateDto::Failed,
        // `ConnectionState` is `#[non_exhaustive]`. A future lifecycle state is
        // most likely transient, so fall back to `Reconnecting` rather than a
        // terminal `Failed`.
        _ => ConnectionStateDto::Reconnecting,
    }
}

/// How a forwarded port follows the client across reconnects and maintenance
/// migrations, mirrored for Dart as a plain enum (doc 59).
pub enum PortFollowPolicyDto {
    /// Re-suggest the last granted external port; on a conflict degrade once to
    /// a server-assigned port instead of failing (the default).
    FollowBestEffort,
    /// Never degrade silently: on a conflict the mapping stays unset for the
    /// epoch and the pin is re-requested on the next one.
    KeepPortOrStay,
    /// No follow: every epoch asks for a fresh server-assigned port.
    Disabled,
}

impl PortFollowPolicyDto {
    fn to_engine(&self) -> PortFollowPolicy {
        match self {
            PortFollowPolicyDto::FollowBestEffort => PortFollowPolicy::FollowBestEffort,
            PortFollowPolicyDto::KeepPortOrStay => PortFollowPolicy::KeepPortOrStay,
            PortFollowPolicyDto::Disabled => PortFollowPolicy::Disabled,
        }
    }
}

/// Progress of one maintenance migration, mirrored as a plain enum.
pub enum MigrationOutcomeDto {
    /// The drain advisory arrived; the supervisor is moving off the exit.
    Migrating,
    /// The post-drain reconnect landed on the new exit.
    Completed,
    /// Every candidate conflicted with a pinned port rule: the migration was
    /// cancelled and the client stays on the draining exit, keeping its port.
    CancelledPortConflict,
}

/// A maintenance-migration lifecycle event: the drain advisory's fields plus
/// where the migration stands, richer than the bare `Draining` state.
pub struct MigrationEventDto {
    /// Unix seconds after which the draining exit hard-closes stragglers;
    /// `u64::MAX` means a soft drain with no deadline.
    pub deadline_unix_secs: u64,
    /// Opaque operator reason code from the drain advisory (0 = maintenance).
    pub reason_code: u8,
    /// Where the migration stands.
    pub outcome: MigrationOutcomeDto,
}

fn migration_to_dto(event: MigrationEvent) -> MigrationEventDto {
    MigrationEventDto {
        deadline_unix_secs: event.deadline_unix_secs,
        reason_code: event.reason_code,
        outcome: match event.outcome {
            MigrationOutcome::Migrating => MigrationOutcomeDto::Migrating,
            MigrationOutcome::Completed => MigrationOutcomeDto::Completed,
            MigrationOutcome::CancelledPortConflict => MigrationOutcomeDto::CancelledPortConflict,
            // `MigrationOutcome` is `#[non_exhaustive]`. An unknown future
            // outcome is most likely a new in-progress stage, so degrade to
            // `Migrating` rather than claim completion or cancellation.
            _ => MigrationOutcomeDto::Migrating,
        },
    }
}

/// Discriminant of a [`PortFollowOutcomeDto`]. Flattened (kind plus optional
/// ports) instead of a payload-carrying enum so the bridge stays on plain
/// generated data classes like the rest of this API.
pub enum PortFollowOutcomeKindDto {
    /// The previously-granted external port was re-granted on this exit.
    Kept,
    /// The exit granted a different external port (first grant, server pick,
    /// or a best-effort degrade after a conflict).
    Changed,
    /// A pinned port was refused and the rule did not degrade: no mapping
    /// exists this epoch, the pin stays requested for the next one.
    ConflictStayed,
    /// The mapping could not be established this epoch; the supervisor keeps
    /// retrying.
    Failed,
    /// The exit refused the mapping as not authorized: it presented no port
    /// entitlement, or one the exit would not spend (warren-core doc 105). The
    /// supervisor keeps retrying.
    NotAuthorized,
    /// The account is banned, so the issuer refuses its port entitlements and
    /// every enforcing exit refuses its mappings. The supervisor keeps
    /// retrying, which a lifted ban answers.
    Banned,
}

/// Why an account is banned, mirrored for Dart as a plain enum.
pub enum BanReasonDto {
    /// Three port-forward abuse strikes inside the sliding window.
    PortForwardingAbuse,
    /// Any other revocation, and any reason this build does not know.
    Other,
}

/// Mirrors the engine's ban reason for Dart.
pub(crate) fn ban_reason_dto(code: &BanReasonCode) -> BanReasonDto {
    match code {
        BanReasonCode::PortForwardingAbuse => BanReasonDto::PortForwardingAbuse,
        // `BanReasonCode` is `#[non_exhaustive]`: a reason this build does not
        // know is still a ban.
        _ => BanReasonDto::Other,
    }
}

/// What happened to a forwarded port on its latest (re)establish.
pub struct PortFollowOutcomeDto {
    /// The outcome discriminant.
    pub kind: PortFollowOutcomeKindDto,
    /// For `Changed`: the previous external port, absent on the first grant.
    pub previous_port: Option<u16>,
    /// For `Kept`/`Changed`: the granted external port. For `ConflictStayed`:
    /// the pinned port that stays requested. Absent otherwise.
    pub port: Option<u16>,
    /// For `NotAuthorized`: whether the refused request carried an
    /// entitlement. Absent otherwise.
    pub entitlement_presented: Option<bool>,
    /// For `Banned`: why. Absent otherwise.
    pub ban_reason: Option<BanReasonDto>,
    /// For `Banned`: when the ban lapses on its own, Unix seconds. Absent
    /// otherwise, and for a ban that does not lapse.
    pub ban_lapses_at_unix_secs: Option<u64>,
}

fn outcome_to_dto(outcome: PortFollowOutcome) -> PortFollowOutcomeDto {
    let bare = |kind, previous_port, port| PortFollowOutcomeDto {
        kind,
        previous_port,
        port,
        entitlement_presented: None,
        ban_reason: None,
        ban_lapses_at_unix_secs: None,
    };
    match outcome {
        PortFollowOutcome::Kept { port } => bare(PortFollowOutcomeKindDto::Kept, None, Some(port)),
        PortFollowOutcome::Changed { previous, port } => {
            bare(PortFollowOutcomeKindDto::Changed, previous, Some(port))
        }
        PortFollowOutcome::ConflictStayed { pinned } => {
            bare(PortFollowOutcomeKindDto::ConflictStayed, None, Some(pinned))
        }
        PortFollowOutcome::NotAuthorized {
            entitlement_presented,
        } => PortFollowOutcomeDto {
            entitlement_presented: Some(entitlement_presented),
            ..bare(PortFollowOutcomeKindDto::NotAuthorized, None, None)
        },
        PortFollowOutcome::Banned {
            reason_code,
            lapses_at_unix_secs,
        } => PortFollowOutcomeDto {
            ban_reason: Some(ban_reason_dto(&reason_code)),
            ban_lapses_at_unix_secs: lapses_at_unix_secs,
            ..bare(PortFollowOutcomeKindDto::Banned, None, None)
        },
        // `Failed`, plus any `#[non_exhaustive]` future variant: no port is
        // known, and "still retrying" is the safe reading for an unknown
        // outcome (the supervisor never kills a forward loop).
        _ => bare(PortFollowOutcomeKindDto::Failed, None, None),
    }
}

/// An opaque, live proxy session.
pub struct WarrenSessionFrb {
    socks5: String,
    http: Option<String>,
    /// What every client of the listeners presents; they refuse anyone else.
    credentials: warren_sdk::net::ProxyCredentials,
    state_rx: Receiver<ConnectionState>,
    migration_rx: Receiver<Option<MigrationEvent>>,
    /// The definitive cause latched when the supervisor gives up, or `None`
    /// while it is healing. Set once, alongside the terminal `Failed` state.
    fatal_rx: Receiver<Option<FatalCause>>,
    /// In-tunnel egress verdict (doc 62 item 5): `true` while the
    /// liveness probe reports the exit not forwarding.
    egress_rx: Receiver<bool>,
    /// Probe task, aborted on disconnect. `None` when no tokio runtime
    /// was current at session creation (plain unit tests).
    probe_task: Mutex<Option<tokio::task::JoinHandle<()>>>,
    // Behind a Mutex<Option<>> because `shutdown` consumes the handle by value
    // while the bridge only ever hands us a shared reference.
    handle: Mutex<Option<SupervisedProxyHandle>>,
}

impl WarrenSessionFrb {
    #[frb(ignore)]
    pub(crate) fn new(handle: SupervisedProxyHandle) -> Self {
        let socks5 = handle.local_addr().to_string();
        let http = handle.http_addr().map(|addr| addr.to_string());
        let credentials = handle.credentials().clone();
        let state_rx = handle.watch_state();
        let migration_rx = handle.watch_migration();
        let fatal_rx = handle.watch_fatal();
        // Egress liveness probe (doc 62 item 5): a drained/half-swapped
        // exit keeps the QUIC session alive while forwarding nothing;
        // the probe TCP-connects through this session's own SOCKS5
        // endpoint and publishes the verdict on `egress_rx`.
        let (egress_tx, egress_rx) = tokio::sync::watch::channel(false);
        let probe_task = tokio::runtime::Handle::try_current().ok().map(|rt| {
            let socks_addr = handle.local_addr();
            let probe_state_rx = handle.watch_state();
            rt.spawn(warren_sdk::socks_egress::run_socks5_egress_probe(
                socks_addr,
                credentials.clone(),
                probe_state_rx,
                egress_tx,
            ))
        });
        Self {
            socks5,
            http,
            credentials,
            state_rx,
            migration_rx,
            fatal_rx,
            egress_rx,
            probe_task: Mutex::new(probe_task),
            handle: Mutex::new(Some(handle)),
        }
    }

    /// The bound local SOCKS5 endpoint, for example `127.0.0.1:51234`.
    pub fn socks5_endpoint(&self) -> String {
        self.socks5.clone()
    }

    /// The bound local HTTP CONNECT endpoint, if one was requested.
    pub fn http_endpoint(&self) -> Option<String> {
        self.http.clone()
    }

    /// The username every client of the endpoints presents (RFC 1929 on
    /// SOCKS5, `Proxy-Authorization: Basic` on HTTP CONNECT).
    pub fn proxy_username(&self) -> String {
        self.credentials.username().to_owned()
    }

    /// The password every client of the endpoints presents. A per-session
    /// secret: keep it out of logs and anything another account can read.
    pub fn proxy_password(&self) -> String {
        self.credentials.password().to_owned()
    }

    /// Streams connection-state transitions, emitting the current state first so
    /// a late listener is never left without one.
    pub async fn states(&self, sink: StreamSink<ConnectionStateDto>) {
        let mut rx = self.state_rx.clone();
        if sink.add(to_dto(*rx.borrow())).is_err() {
            return;
        }
        while rx.changed().await.is_ok() {
            let state = *rx.borrow();
            if sink.add(to_dto(state)).is_err() {
                break;
            }
        }
    }

    /// The definitive cause the supervisor stopped on, or `None` while it is
    /// still healing (or gave up on mere retry exhaustion, which is transient
    /// and carries no cause). Read it when the state stream reaches `Failed`:
    /// the supervisor latches the cause BEFORE publishing `Failed`, so a present
    /// value there means no redial or other exit will help. A consumer surfaces
    /// it (expired subscription, device limit) and stops instead of looping
    /// `Reconnecting`.
    pub fn fatal_cause(&self) -> Option<WarrenFatalCauseDto> {
        self.fatal_rx.borrow().map(fatal_to_dto)
    }

    /// Streams maintenance-migration events (doc 59): the drain advisory's
    /// deadline and reason plus the outcome (migrating, completed, cancelled
    /// for a pinned-port conflict). Emits the latest event first, if any, so a
    /// late listener still sees an in-flight migration.
    pub async fn migration_events(&self, sink: StreamSink<MigrationEventDto>) {
        let mut rx = self.migration_rx.clone();
        if let Some(event) = *rx.borrow() {
            if sink.add(migration_to_dto(event)).is_err() {
                return;
            }
        }
        while rx.changed().await.is_ok() {
            let event = *rx.borrow();
            if let Some(event) = event {
                if sink.add(migration_to_dto(event)).is_err() {
                    break;
                }
            }
        }
    }

    /// Forwards a tunnel-side port via NAT-PMP, re-mapped automatically across
    /// reconnects. `local_target` is the local `ip:port` inbound connections are
    /// relayed to. The exit must run a NAT-PMP gateway.
    pub fn forward_port(
        &self,
        proto: MapProtoDto,
        internal_port: u16,
        local_target: String,
    ) -> Result<WarrenForwardedPortFrb, WarrenFfiError> {
        self.forward_port_with_policy(
            proto,
            internal_port,
            local_target,
            PortFollowPolicyDto::FollowBestEffort,
            None,
        )
    }

    /// Like [`Self::forward_port`], with an explicit follow policy (doc 59).
    /// `pinned_external_port` pins the external port for `KeepPortOrStay`;
    /// `None` pins the first port the exit grants. Observe what happened on
    /// each rebuild via [`WarrenForwardedPortFrb::outcomes`].
    pub fn forward_port_with_policy(
        &self,
        proto: MapProtoDto,
        internal_port: u16,
        local_target: String,
        policy: PortFollowPolicyDto,
        pinned_external_port: Option<u16>,
    ) -> Result<WarrenForwardedPortFrb, WarrenFfiError> {
        let target: SocketAddr = local_target.parse().map_err(|_| WarrenFfiError {
            kind: WarrenErrorKind::Tunnel,
            message: "invalid local target address".to_owned(),
            ban: None,
        })?;
        let guard = self.handle.lock().expect("session mutex poisoned");
        let handle = guard.as_ref().ok_or(WarrenFfiError {
            kind: WarrenErrorKind::Tunnel,
            message: "session is disconnected".to_owned(),
            ban: None,
        })?;
        let config = PortFollowConfig {
            policy: policy.to_engine(),
            pinned_external_port,
            ..PortFollowConfig::default()
        };
        let port =
            handle.forward_port_with_policy(proto.to_engine(), internal_port, target, config);
        Ok(WarrenForwardedPortFrb::new(port))
    }

    /// Whether the in-tunnel egress liveness probe currently reports
    /// the exit not forwarding (doc 62 item 5). `false` in every state
    /// other than a Connected session with dead egress.
    pub fn egress_dead(&self) -> bool {
        *self.egress_rx.borrow()
    }

    /// Streams the egress verdict (doc 62 item 5), emitting the current
    /// value first so a late listener is never left without one. `true`
    /// while the exit stopped forwarding despite a live session (e.g. a
    /// drained or half-swapped exit during a fleet rollout); cleared by
    /// one successful probe or by leaving the Connected state.
    pub async fn egress_health(&self, sink: StreamSink<bool>) {
        let mut rx = self.egress_rx.clone();
        if sink.add(*rx.borrow()).is_err() {
            return;
        }
        while rx.changed().await.is_ok() {
            let dead = *rx.borrow();
            if sink.add(dead).is_err() {
                break;
            }
        }
    }

    /// Tears the connection down and releases its datapath resources.
    /// Idempotent: a second call is a no-op.
    pub fn disconnect(&self) {
        if let Some(task) = self.probe_task.lock().expect("probe mutex poisoned").take() {
            task.abort();
        }
        if let Some(handle) = self.handle.lock().expect("session mutex poisoned").take() {
            handle.shutdown();
        }
    }
}

/// Transport protocol for a forwarded port, mirrored to Dart as a plain enum.
pub enum MapProtoDto {
    /// TCP.
    Tcp,
    /// UDP.
    Udp,
}

impl MapProtoDto {
    fn to_engine(&self) -> MapProto {
        match self {
            MapProtoDto::Tcp => MapProto::Tcp,
            MapProtoDto::Udp => MapProto::Udp,
        }
    }
}

/// An opaque, self-healing forwarded port. Its external port can change across
/// reconnects, so observe it via [`Self::external_ports`] rather than caching
/// [`Self::external_port`]. Dropping or [`Self::shutdown`]ing it tears the
/// mapping down.
pub struct WarrenForwardedPortFrb {
    internal_port: u16,
    external_rx: Receiver<Option<u16>>,
    outcome_rx: Receiver<Option<PortFollowOutcome>>,
    // Behind a Mutex<Option<>> because `shutdown` consumes the handle by value.
    port: Mutex<Option<SupervisedForwardedPort>>,
}

impl WarrenForwardedPortFrb {
    #[frb(ignore)]
    pub(crate) fn new(port: SupervisedForwardedPort) -> Self {
        Self {
            internal_port: port.internal_port(),
            external_rx: port.watch_external_port(),
            outcome_rx: port.watch_outcome(),
            port: Mutex::new(Some(port)),
        }
    }

    /// The local internal port being forwarded.
    pub fn internal_port(&self) -> u16 {
        self.internal_port
    }

    /// The current external port remote peers reach the app on, or `None` while
    /// the tunnel is down or before the first mapping is granted.
    pub fn external_port(&self) -> Option<u16> {
        *self.external_rx.borrow()
    }

    /// Streams external-port changes (re-mappings across reconnects), emitting
    /// the current value first so a late listener always gets one.
    pub async fn external_ports(&self, sink: StreamSink<Option<u16>>) {
        let mut rx = self.external_rx.clone();
        if sink.add(*rx.borrow()).is_err() {
            return;
        }
        while rx.changed().await.is_ok() {
            let value = *rx.borrow();
            if sink.add(value).is_err() {
                break;
            }
        }
    }

    /// Streams follow outcomes (doc 59): what happened to this rule's external
    /// port on each (re)establish (kept, changed, held back by a conflict, or
    /// failed). Emits the latest outcome first, if any, so a late listener is
    /// not left without one.
    pub async fn outcomes(&self, sink: StreamSink<PortFollowOutcomeDto>) {
        let mut rx = self.outcome_rx.clone();
        if let Some(outcome) = *rx.borrow() {
            if sink.add(outcome_to_dto(outcome)).is_err() {
                return;
            }
        }
        while rx.changed().await.is_ok() {
            let outcome = *rx.borrow();
            if let Some(outcome) = outcome {
                if sink.add(outcome_to_dto(outcome)).is_err() {
                    break;
                }
            }
        }
    }

    /// Tears the forward down. Idempotent: a second call is a no-op.
    pub fn shutdown(&self) {
        if let Some(port) = self.port.lock().expect("forward mutex poisoned").take() {
            port.shutdown();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{
        fatal_to_dto, outcome_to_dto, BanReasonDto, PortFollowOutcomeKindDto, WarrenFatalCauseDto,
    };
    use warren_sdk::api::BanReasonCode;
    use warren_sdk::transport::FatalCause;
    use warren_sdk::PortFollowOutcome;

    #[test]
    fn an_entitlement_refusal_crosses_the_bridge_with_what_was_presented() {
        let dto = outcome_to_dto(PortFollowOutcome::NotAuthorized {
            entitlement_presented: true,
        });

        assert!(matches!(dto.kind, PortFollowOutcomeKindDto::NotAuthorized));
        assert_eq!(dto.entitlement_presented, Some(true));
        assert_eq!(dto.port, None);
    }

    #[test]
    fn a_ban_crosses_the_bridge_with_its_reason_and_lapse() {
        let dto = outcome_to_dto(PortFollowOutcome::Banned {
            reason_code: BanReasonCode::PortForwardingAbuse,
            lapses_at_unix_secs: Some(1_790_000_000),
        });

        assert!(matches!(dto.kind, PortFollowOutcomeKindDto::Banned));
        assert!(matches!(
            dto.ban_reason,
            Some(BanReasonDto::PortForwardingAbuse)
        ));
        assert_eq!(dto.ban_lapses_at_unix_secs, Some(1_790_000_000));
    }

    #[test]
    fn fatal_cause_kinds_stay_distinct_across_the_bridge() {
        // Each engine fatal cause maps to its OWN Dart-facing kind: a consumer
        // must tell "renew the subscription" (NotAuthorized) from "too many
        // devices" (DeviceLimit) from an opaque refusal, to react correctly.
        assert_eq!(
            fatal_to_dto(FatalCause::NotAuthorized),
            WarrenFatalCauseDto::NotAuthorized
        );
        assert_eq!(
            fatal_to_dto(FatalCause::DeviceLimit),
            WarrenFatalCauseDto::DeviceLimit
        );
        assert_eq!(
            fatal_to_dto(FatalCause::PolicyRefused),
            WarrenFatalCauseDto::PolicyRefused
        );
        assert_eq!(
            fatal_to_dto(FatalCause::Banned),
            WarrenFatalCauseDto::Banned
        );
        // The taxonomy must not collapse to one kind: a subscription rejection
        // has to stay distinguishable from a device-limit one for the client.
        assert_ne!(
            WarrenFatalCauseDto::NotAuthorized,
            WarrenFatalCauseDto::DeviceLimit
        );
        assert_ne!(
            WarrenFatalCauseDto::DeviceLimit,
            WarrenFatalCauseDto::PolicyRefused
        );
        assert_ne!(
            WarrenFatalCauseDto::NotAuthorized,
            WarrenFatalCauseDto::PolicyRefused
        );
    }
}
