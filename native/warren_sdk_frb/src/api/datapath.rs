//! Proxy datapath session (roadmap P3).
//!
//! Wraps the engine's self-healing supervised proxy behind an opaque handle and
//! streams its connection-state transitions across the bridge. The datapath
//! logic lives entirely in the audited engine; this is endpoint exposure, a
//! state forwarder and teardown.

use std::net::SocketAddr;
use std::sync::Mutex;

use flutter_rust_bridge::frb;
use tokio::sync::watch::Receiver;
use warren_sdk::net::MapProto;
use warren_sdk::{ConnectionState, SupervisedForwardedPort, SupervisedProxyHandle};

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
    /// Every attempt failed; the supervisor gave up.
    Failed,
}

fn to_dto(state: ConnectionState) -> ConnectionStateDto {
    match state {
        ConnectionState::Connecting => ConnectionStateDto::Connecting,
        ConnectionState::Connected => ConnectionStateDto::Connected,
        ConnectionState::Reconnecting => ConnectionStateDto::Reconnecting,
        // `ConnectionState` is `#[non_exhaustive]`; treat anything else (only
        // `Failed` today) as a terminal failure rather than panicking.
        _ => ConnectionStateDto::Failed,
    }
}

/// An opaque, live proxy session.
pub struct WarrenSessionFrb {
    socks5: String,
    http: Option<String>,
    state_rx: Receiver<ConnectionState>,
    // Behind a Mutex<Option<>> because `shutdown` consumes the handle by value
    // while the bridge only ever hands us a shared reference.
    handle: Mutex<Option<SupervisedProxyHandle>>,
}

impl WarrenSessionFrb {
    #[frb(ignore)]
    pub(crate) fn new(handle: SupervisedProxyHandle) -> Self {
        let socks5 = handle.local_addr().to_string();
        let http = handle.http_addr().map(|addr| addr.to_string());
        let state_rx = handle.watch_state();
        Self {
            socks5,
            http,
            state_rx,
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

    /// Forwards a tunnel-side port via NAT-PMP, re-mapped automatically across
    /// reconnects. `local_target` is the local `ip:port` inbound connections are
    /// relayed to. The exit must run a NAT-PMP gateway.
    pub fn forward_port(
        &self,
        proto: MapProtoDto,
        internal_port: u16,
        local_target: String,
    ) -> Result<WarrenForwardedPortFrb, WarrenFfiError> {
        let target: SocketAddr = local_target.parse().map_err(|_| WarrenFfiError {
            kind: WarrenErrorKind::Tunnel,
            message: "invalid local target address".to_owned(),
        })?;
        let guard = self.handle.lock().expect("session mutex poisoned");
        let handle = guard.as_ref().ok_or(WarrenFfiError {
            kind: WarrenErrorKind::Tunnel,
            message: "session is disconnected".to_owned(),
        })?;
        let port = handle.forward_port(proto.to_engine(), internal_port, target);
        Ok(WarrenForwardedPortFrb::new(port))
    }

    /// Tears the connection down and releases its datapath resources.
    /// Idempotent: a second call is a no-op.
    pub fn disconnect(&self) {
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
    // Behind a Mutex<Option<>> because `shutdown` consumes the handle by value.
    port: Mutex<Option<SupervisedForwardedPort>>,
}

impl WarrenForwardedPortFrb {
    #[frb(ignore)]
    pub(crate) fn new(port: SupervisedForwardedPort) -> Self {
        Self {
            internal_port: port.internal_port(),
            external_rx: port.watch_external_port(),
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

    /// Tears the forward down. Idempotent: a second call is a no-op.
    pub fn shutdown(&self) {
        if let Some(port) = self.port.lock().expect("forward mutex poisoned").take() {
            port.shutdown();
        }
    }
}
