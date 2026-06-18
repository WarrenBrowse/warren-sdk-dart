//! Stateful engine client wrapper (roadmap P2, account API).
//!
//! Holds a live `warren-sdk` client behind an opaque handle and exposes the
//! account surface (subscription, voucher redemption, exit listing). All
//! protocol logic stays in the audited engine; this is thin delegation plus
//! error categorization for the bridge.

use std::path::Path;
use std::sync::Arc;

use warren_sdk::api::dto::RegisterAccountRequest;
use warren_sdk::api::ClientError;
use warren_sdk::discovery::Relay;
use warren_sdk::identity::WarrenIdentity;
use warren_sdk::net::ProxyConfig;
use warren_sdk::{DefaultClient, FileGenerationStore, FileServerKeyStore, SdkError, WarrenClient};

use crate::api::datapath::WarrenSessionFrb;
use crate::api::error::{WarrenErrorKind, WarrenFfiError};

fn err(kind: WarrenErrorKind, message: impl Into<String>) -> WarrenFfiError {
    WarrenFfiError {
        kind,
        message: message.into(),
    }
}

/// An exit advertised by the verified signed relay list. Only fields the relay
/// list actually carries are surfaced; port-forwarding is negotiated per
/// connection (not known at listing time) and load is not advertised.
pub struct ExitInfoDto {
    /// Stable, operator-assigned exit identifier (survives key rotation).
    pub id: String,
    /// ISO country code.
    pub country: String,
    /// City name.
    pub city: String,
    /// Whether the exit attests IPv6 egress.
    pub supports_ipv6: bool,
}

/// The account server's view of the caller's connection, from a signed
/// `GET /v1/check`. Lets an app confirm against the backend whether its traffic
/// egresses from a registered Warren exit, and where.
pub struct TunnelCheckDto {
    /// The public IP the account server observed for this call.
    pub ip: String,
    /// True when `ip` is a registered Warren exit (traffic is tunneled).
    pub is_exit: bool,
    /// Exit country (ISO 3166-1 alpha-2), when `is_exit`.
    pub country: Option<String>,
    /// Exit city, when known.
    pub city: Option<String>,
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
        daita: bool,
        daita_machine: Option<String>,
        request_ipv6: bool,
        state_dir: Option<String>,
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
        if daita {
            builder = builder.daita();
            if let Some(machine) = daita_machine {
                builder = builder.daita_machine(machine);
            }
        }
        if request_ipv6 {
            builder = builder.request_ipv6();
        }
        if let Some(dir) = state_dir {
            // Persist the anti-rollback floors and the TOFU server pin across
            // restarts, so a downgraded relay/multihop list or a swapped server
            // key cannot slip past on the next launch. Mirrors the engine FFI's
            // `with_persistence`; the filenames must match for state continuity.
            let dir = Path::new(&dir);
            let io_err =
                |_| err(WarrenErrorKind::Api, "persistence state directory is not usable");
            std::fs::create_dir_all(dir).map_err(io_err)?;
            let relay_gen =
                FileGenerationStore::new(dir.join("relay_generation")).map_err(io_err)?;
            let mh_gen =
                FileGenerationStore::new(dir.join("multihop_generation")).map_err(io_err)?;
            let key_store = FileServerKeyStore::new(dir.join("server_key")).map_err(io_err)?;
            builder = builder
                .generation_store(Arc::new(relay_gen))
                .multihop_generation_store(Arc::new(mh_gen))
                .server_key_store(Arc::new(key_store));
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

    /// The account server's view of this connection (signed `GET /v1/check`):
    /// whether traffic egresses from a registered Warren exit, and which one.
    /// Confirms a tunnel end-to-end against the backend rather than a third-party
    /// IP echo.
    pub async fn check(&self) -> Result<TunnelCheckDto, WarrenFfiError> {
        let resp = self.inner.api().check().await.map_err(map_client_error)?;
        Ok(TunnelCheckDto {
            ip: resp.ip,
            is_exit: resp.is_exit,
            country: resp.exit_country,
            city: resp.exit_city,
        })
    }

    /// Fetches and verifies the signed relay list, returning the exits.
    pub async fn list_exits(&self) -> Result<Vec<ExitInfoDto>, WarrenFfiError> {
        let selector = self.inner.fetch_exits().await.map_err(map_sdk_error)?;
        Ok(selector.relays().iter().map(relay_to_dto).collect())
    }

    /// Opens a self-healing multihop proxy to the exit whose Ed25519 identity is
    /// `exit_pubkey_hex` (the `id` from [`list_exits`]), binding the local
    /// listeners. Proxy mode always uses multihop, which real exits require.
    ///
    /// Connect failures after this returns surface as connection state on the
    /// session, not as an error here.
    pub async fn connect_proxy(
        &self,
        exit_pubkey_hex: String,
        socks5_listen: String,
        http_listen: Option<String>,
        dns_server: Option<String>,
    ) -> Result<WarrenSessionFrb, WarrenFfiError> {
        let target: [u8; 32] = hex::decode(&exit_pubkey_hex)
            .ok()
            .and_then(|bytes| bytes.try_into().ok())
            .ok_or_else(|| err(WarrenErrorKind::Discovery, "invalid exit id"))?;

        let exits = self
            .inner
            .fetch_multihop_directory()
            .await
            .map_err(map_sdk_error)?;
        let exit = exits
            .into_iter()
            .find(|candidate| candidate.exit_ed25519_pubkey == target)
            .ok_or_else(|| err(WarrenErrorKind::Discovery, "exit not in multihop directory"))?;

        let cfg = ProxyConfig {
            socks5: socks5_listen
                .parse()
                .map_err(|_| err(WarrenErrorKind::Tunnel, "invalid socks5 listen address"))?,
            http: match http_listen {
                Some(addr) => Some(
                    addr.parse()
                        .map_err(|_| err(WarrenErrorKind::Tunnel, "invalid http listen address"))?,
                ),
                None => None,
            },
            // Optional resolver override (IPv4, port 53 implied) for exits that
            // disable the default tunnel DNS; otherwise the engine default.
            dns_server: match dns_server {
                Some(addr) => Some(addr.parse::<std::net::Ipv4Addr>().map_err(|_| {
                    err(WarrenErrorKind::Tunnel, "invalid dns server address")
                })?),
                None => None,
            },
        };

        let handle = self
            .inner
            .start_proxy_multihop_supervised(&exit, &cfg)
            .await
            .map_err(map_sdk_error)?;
        Ok(WarrenSessionFrb::new(handle))
    }
}

fn relay_to_dto(relay: &Relay) -> ExitInfoDto {
    ExitInfoDto {
        // The Ed25519 endpoint key is the canonical exit identity shared with
        // the multihop directory, so `connect` can cross-reference an exit the
        // app selected here against the directory entry it must dial.
        id: hex::encode(relay.endpoint_id()),
        country: relay.location().country_code().to_owned(),
        city: relay.location().city().to_owned(),
        supports_ipv6: relay.ipv6_egress(),
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
