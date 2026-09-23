//! The daemon IPC wire protocol.
//!
//! Byte-for-byte compatible with the Dart `warren_sdk_desktop` messages: a
//! length-prefixed (4-byte big-endian) UTF-8 JSON object with a `type`
//! discriminator. Field names match the Dart side (camelCase).

use std::fmt;

use serde::{Deserialize, Serialize};

/// A request from the app to the daemon.
#[derive(Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Request {
    /// Bind an identity and account API in the daemon.
    Configure {
        mnemonic: String,
        #[serde(rename = "apiBase")]
        api_base: String,
        #[serde(rename = "serverPubkeyPin")]
        server_pubkey_pin: String,
        #[serde(default, rename = "multihopRootPin")]
        multihop_root_pin: Option<String>,
        #[serde(default)]
        daita: bool,
        #[serde(default, rename = "daitaMachine")]
        daita_machine: Option<String>,
        // Defaults to true so an older client that omits the field keeps the
        // previous always-on IPv6 behaviour.
        #[serde(default = "default_true", rename = "requestIpv6")]
        request_ipv6: bool,
        // Lockdown mode: user-intended stops (disconnect, daemon stop) keep
        // the network BLOCKED instead of restoring it. Defaults off, the
        // pre-lockdown wire behaviour.
        #[serde(default)]
        lockdown: bool,
    },
    /// Bring up a system-VPN session to an exit (Ed25519 id from `listExits`).
    Connect {
        #[serde(rename = "exitPubkeyHex")]
        exit_pubkey_hex: String,
        #[serde(default = "default_true", rename = "dnsOverTunnel")]
        dns_over_tunnel: bool,
    },
    /// Tear the current session down.
    Disconnect,
}

const fn default_true() -> bool {
    true
}

/// Renders only the variant and its switches: a configure request carries the
/// mnemonic, and no identity material may reach a log line.
impl fmt::Debug for Request {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Request::Configure {
                daita,
                request_ipv6,
                lockdown,
                ..
            } => f
                .debug_struct("Configure")
                .field("daita", daita)
                .field("request_ipv6", request_ipv6)
                .field("lockdown", lockdown)
                .finish_non_exhaustive(),
            Request::Connect {
                dns_over_tunnel, ..
            } => f
                .debug_struct("Connect")
                .field("dns_over_tunnel", dns_over_tunnel)
                .finish_non_exhaustive(),
            Request::Disconnect => f.write_str("Disconnect"),
        }
    }
}

/// An event from the daemon to the app.
#[derive(Debug, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Event {
    /// A connection-state transition.
    State { state: ConnState },
    /// A redacted failure.
    Error { kind: String, message: String },
}

/// The connection state, serialized with the same names the Dart enum uses.
///
/// This is the full wire vocabulary shared with the Dart side, mirroring the
/// engine's `ConnectionState` lineage plus `Disconnected`. The current
/// (non-supervised) daemon only emits a subset (`Connected` / `Draining` /
/// `Disconnected`, plus errors); the others exist for protocol parity and a
/// future supervised daemon.
#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "snake_case")]
#[allow(dead_code)]
pub enum ConnState {
    Connecting,
    Connected,
    Reconnecting,
    /// The session is being wound down while the killswitch still holds: sent
    /// when an explicit disconnect starts tearing the datapath down (and, once
    /// the daemon is supervised, when the exit signals a drain migration).
    /// Not final: `Disconnected` follows only after the network is restored.
    Draining,
    Failed,
    Disconnected,
}

impl Event {
    /// Builds a state event.
    pub fn state(state: ConnState) -> Self {
        Event::State { state }
    }

    /// Builds a redacted error event.
    pub fn error(kind: &str, message: impl Into<String>) -> Self {
        Event::Error {
            kind: kind.to_owned(),
            message: message.into(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_the_dart_request_shapes() {
        let configure: Request = serde_json::from_str(
            r#"{"type":"configure","mnemonic":"m","apiBase":"https://a","serverPubkeyPin":"p"}"#,
        )
        .expect("configure");
        // Omitted optional fields default: no root pin, DAITA off, IPv6 on,
        // lockdown off.
        assert!(matches!(
            configure,
            Request::Configure {
                multihop_root_pin: None,
                daita: false,
                request_ipv6: true,
                lockdown: false,
                ..
            }
        ));

        let connect: Request = serde_json::from_str(
            r#"{"type":"connect","exitPubkeyHex":"ab12","dnsOverTunnel":false}"#,
        )
        .expect("connect");
        match connect {
            Request::Connect {
                exit_pubkey_hex,
                dns_over_tunnel,
            } => {
                assert_eq!(exit_pubkey_hex, "ab12");
                assert!(!dns_over_tunnel);
            }
            _ => panic!("expected connect"),
        }

        let disconnect: Request = serde_json::from_str(r#"{"type":"disconnect"}"#).expect("disc");
        assert!(matches!(disconnect, Request::Disconnect));
    }

    #[test]
    fn configure_carries_daita_and_ipv6_options() {
        let configure: Request = serde_json::from_str(
            r#"{"type":"configure","mnemonic":"m","apiBase":"https://a",
                "serverPubkeyPin":"p","daita":true,"daitaMachine":"tamaraw",
                "requestIpv6":false}"#,
        )
        .expect("configure");
        match configure {
            Request::Configure {
                daita,
                daita_machine,
                request_ipv6,
                ..
            } => {
                assert!(daita);
                assert_eq!(daita_machine.as_deref(), Some("tamaraw"));
                assert!(!request_ipv6);
            }
            _ => panic!("expected configure"),
        }
    }

    #[test]
    fn configure_carries_lockdown() {
        let configure: Request = serde_json::from_str(
            r#"{"type":"configure","mnemonic":"m","apiBase":"https://a",
                "serverPubkeyPin":"p","lockdown":true}"#,
        )
        .expect("configure");
        assert!(matches!(
            configure,
            Request::Configure { lockdown: true, .. }
        ));
    }

    #[test]
    fn connect_defaults_dns_over_tunnel_on() {
        let connect: Request =
            serde_json::from_str(r#"{"type":"connect","exitPubkeyHex":"ab"}"#).expect("connect");
        assert!(matches!(
            connect,
            Request::Connect {
                dns_over_tunnel: true,
                ..
            }
        ));
    }

    #[test]
    fn a_configure_request_never_prints_its_mnemonic() {
        let configure: Request = serde_json::from_str(
            r#"{"type":"configure","mnemonic":"abandon ability able",
                "apiBase":"https://a","serverPubkeyPin":"p"}"#,
        )
        .expect("configure");

        let rendered = format!("{configure:?}");

        assert!(rendered.starts_with("Configure"), "{rendered}");
        assert!(!rendered.contains("abandon"), "{rendered}");
    }

    #[test]
    fn serializes_events_as_the_dart_side_expects() {
        let state = serde_json::to_string(&Event::state(ConnState::Connected)).unwrap();
        assert_eq!(state, r#"{"type":"state","state":"connected"}"#);

        // The teardown-in-progress state (and, under a future supervised
        // daemon, the exit-drain migration): its spelling is shared with the
        // Dart enum and the TS WarrendState mirror.
        let draining = serde_json::to_string(&Event::state(ConnState::Draining)).unwrap();
        assert_eq!(draining, r#"{"type":"state","state":"draining"}"#);

        let error = serde_json::to_string(&Event::error("tunnel", "down")).unwrap();
        assert_eq!(
            error,
            r#"{"type":"error","kind":"tunnel","message":"down"}"#
        );
    }
}
