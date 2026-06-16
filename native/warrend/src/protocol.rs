//! The daemon IPC wire protocol.
//!
//! Byte-for-byte compatible with the Dart `warren_sdk_desktop` messages: a
//! length-prefixed (4-byte big-endian) UTF-8 JSON object with a `type`
//! discriminator. Field names match the Dart side (camelCase).

use serde::{Deserialize, Serialize};

/// A request from the app to the daemon.
#[derive(Debug, Deserialize)]
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
/// This is the full wire vocabulary shared with the Dart side. The current
/// (non-supervised) daemon only emits a subset (`Connected` / `Disconnected`,
/// plus errors); the others exist for protocol parity and a future supervised
/// daemon.
#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "snake_case")]
#[allow(dead_code)]
pub enum ConnState {
    Connecting,
    Connected,
    Reconnecting,
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
        assert!(matches!(
            configure,
            Request::Configure {
                multihop_root_pin: None,
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
    fn serializes_events_as_the_dart_side_expects() {
        let state = serde_json::to_string(&Event::state(ConnState::Connected)).unwrap();
        assert_eq!(state, r#"{"type":"state","state":"connected"}"#);

        let error = serde_json::to_string(&Event::error("tunnel", "down")).unwrap();
        assert_eq!(
            error,
            r#"{"type":"error","kind":"tunnel","message":"down"}"#
        );
    }
}
