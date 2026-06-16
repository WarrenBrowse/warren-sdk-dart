//! Proxy datapath session (roadmap P3).
//!
//! Wraps the engine's self-healing supervised proxy behind an opaque handle and
//! streams its connection-state transitions across the bridge. The datapath
//! logic lives entirely in the audited engine; this is endpoint exposure, a
//! state forwarder and teardown.

use std::sync::Mutex;

use flutter_rust_bridge::frb;
use tokio::sync::watch::Receiver;
use warren_sdk::{ConnectionState, SupervisedProxyHandle};

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

    /// Tears the connection down and releases its datapath resources.
    /// Idempotent: a second call is a no-op.
    pub fn disconnect(&self) {
        if let Some(handle) = self.handle.lock().expect("session mutex poisoned").take() {
            handle.shutdown();
        }
    }
}
