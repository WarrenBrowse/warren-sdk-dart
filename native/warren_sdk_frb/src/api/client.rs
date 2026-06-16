//! Stateful engine client wrapper (roadmap P2, account API).
//!
//! Holds a live `warren-sdk` client behind an opaque handle and exposes the
//! account surface (subscription, voucher redemption, exit listing). All
//! protocol logic stays in the audited engine; this is thin delegation plus
//! error categorization for the bridge.

use std::sync::Arc;

use warren_sdk::api::dto::RegisterAccountRequest;
use warren_sdk::api::ClientError;
use warren_sdk::discovery::Relay;
use warren_sdk::identity::WarrenIdentity;
use warren_sdk::{DefaultClient, SdkError, WarrenClient};

use crate::api::error::{WarrenErrorKind, WarrenFfiError};

fn err(kind: WarrenErrorKind, message: impl Into<String>) -> WarrenFfiError {
    WarrenFfiError {
        kind,
        message: message.into(),
    }
}

/// An exit advertised by the verified signed relay list.
///
/// `supports_port_forwarding` is not carried in the relay list: inbound port
/// forwarding is negotiated per connection at handshake time, so it is reported
/// as `false` here and confirmed once a session is established. `load` is not
/// advertised either and is left unset.
pub struct ExitInfoDto {
    /// Stable, operator-assigned exit identifier (survives key rotation).
    pub id: String,
    /// ISO country code.
    pub country: String,
    /// City name.
    pub city: String,
    /// Whether the exit attests IPv6 egress.
    pub supports_ipv6: bool,
    /// Whether inbound port forwarding is known to be available (always false
    /// at listing time; negotiated at connect).
    pub supports_port_forwarding: bool,
    /// Optional load hint in `[0.0, 1.0]`, when advertised.
    pub load: Option<f64>,
}

/// An opaque, live engine client bound to one identity and account API.
pub struct WarrenClientFrb {
    inner: Arc<DefaultClient>,
    address: String,
}

impl WarrenClientFrb {
    /// Builds a client from a mnemonic and the account API configuration.
    ///
    /// The mnemonic is consumed here and not retained; the engine zeroizes the
    /// derived signing key on drop.
    pub async fn create(
        mnemonic: String,
        api_base: String,
        server_pubkey_pin: String,
        multihop_root_pin: Option<String>,
    ) -> Result<WarrenClientFrb, WarrenFfiError> {
        let identity = WarrenIdentity::from_mnemonic(&mnemonic)
            .map_err(|_| err(WarrenErrorKind::Identity, "invalid mnemonic"))?;
        let address = identity.address();

        let mut builder = WarrenClient::builder()
            .identity(identity)
            .api_base(api_base)
            .server_pubkey_pin(server_pubkey_pin);
        if let Some(root) = multihop_root_pin {
            builder = builder.multihop_root_pubkey_pin(root);
        }
        let inner = builder
            .build()
            .map_err(|e| err(WarrenErrorKind::Api, e.to_string()))?;

        Ok(Self {
            inner: Arc::new(inner),
            address,
        })
    }

    /// The SS58 `wb...` address of the bound identity.
    pub fn address(&self) -> String {
        self.address.clone()
    }

    /// Unix-seconds subscription expiry (`0` means no active subscription).
    pub async fn subscription_expiry(&self) -> Result<u64, WarrenFfiError> {
        let resp = self
            .inner
            .api()
            .subscription()
            .await
            .map_err(map_client_error)?;
        Ok(resp.expires_at)
    }

    /// Redeems a voucher and returns the new expiry (Unix seconds).
    pub async fn redeem_voucher(&self, secret: String) -> Result<u64, WarrenFfiError> {
        let req = RegisterAccountRequest {
            pubkey_ss58: self.address.clone(),
            voucher_secret: secret,
            referral_code: None,
        };
        let resp = self
            .inner
            .api()
            .register(&req)
            .await
            .map_err(map_client_error)?;
        Ok(resp.expires_at)
    }

    /// Fetches and verifies the signed relay list, returning the exits.
    pub async fn list_exits(&self) -> Result<Vec<ExitInfoDto>, WarrenFfiError> {
        let selector = self.inner.fetch_exits().await.map_err(map_sdk_error)?;
        Ok(selector.relays().iter().map(relay_to_dto).collect())
    }
}

fn relay_to_dto(relay: &Relay) -> ExitInfoDto {
    ExitInfoDto {
        id: relay.exit_id().to_string(),
        country: relay.location().country_code().to_owned(),
        city: relay.location().city().to_owned(),
        supports_ipv6: relay.ipv6_egress(),
        supports_port_forwarding: false,
        load: None,
    }
}

fn map_client_error(error: ClientError) -> WarrenFfiError {
    err(WarrenErrorKind::Api, error.to_string())
}

fn map_sdk_error(error: SdkError) -> WarrenFfiError {
    let kind = match error {
        SdkError::Discovery(_)
        | SdkError::Selector(_)
        | SdkError::StaleRelayList
        | SdkError::RolledBackRelayList { .. } => WarrenErrorKind::Discovery,
        SdkError::Tunnel(_) | SdkError::Multihop(_) => WarrenErrorKind::Tunnel,
        _ => WarrenErrorKind::Api,
    };
    err(kind, error.to_string())
}
