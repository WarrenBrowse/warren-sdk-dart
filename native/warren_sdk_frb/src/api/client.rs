//! Stateful engine client wrapper for the account API.
//!
//! Holds a live `warren-sdk` client behind an opaque handle and exposes the
//! account surface (subscription, voucher redemption, exit listing, the
//! account's devices). All
//! protocol logic stays in the audited engine; this is thin delegation plus
//! error categorization for the bridge.

use std::sync::{Arc, Mutex, PoisonError};

use warren_sdk::api::dto::RegisterAccountRequest;
use warren_sdk::api::{ClientError, DeviceId};
use warren_sdk::discovery::{Relay, VerifiedExit};
use warren_sdk::identity::WarrenIdentity;
use warren_sdk::net::ProxyConfig;
use warren_sdk::{
    Circuit, DefaultClient, FileGenerationStore, FileServerKeyStore, SdkError, WarrenClient,
};
use zeroize::Zeroize;

use crate::api::datapath::{ban_reason_dto, WarrenSessionFrb};
use crate::api::device::{device_list_to_dto, device_platform_for, DeviceListDto};
use crate::api::error::{
    BanRefusalDto, ClockSkewDto, DeviceRefusalDto, WarrenErrorKind, WarrenFfiError,
};

/// The file in the client's state directory that keeps this install's device
/// identity, the name the engine's own FFI uses, so an app moving between the
/// two bindings keeps one device.
const DEVICE_FILE: &str = "device";

fn err(kind: WarrenErrorKind, message: impl Into<String>) -> WarrenFfiError {
    WarrenFfiError {
        kind,
        message: message.into(),
        ban: None,
        clock_skew: None,
        device: None,
    }
}

fn device_refusal(refusal: DeviceRefusalDto, message: &str) -> WarrenFfiError {
    WarrenFfiError {
        device: Some(refusal),
        ..err(WarrenErrorKind::Api, message)
    }
}

fn parse_device_id(id: String) -> Result<DeviceId, WarrenFfiError> {
    DeviceId::try_from(id)
        .map_err(|_| device_refusal(DeviceRefusalDto::InvalidId, "invalid device id"))
}

/// An exit advertised by the verified signed relay list. Only fields the relay
/// list actually carries are surfaced; port-forwarding is negotiated per
/// connection (not known at listing time).
pub struct ExitInfoDto {
    /// Stable, operator-assigned exit identifier (survives key rotation).
    pub id: String,
    /// ISO country code.
    pub country: String,
    /// City name.
    pub city: String,
    /// Whether the exit attests IPv6 egress.
    pub supports_ipv6: bool,
    /// The exit's X.509 cover domain (ADR-0004 mimicry), when it advertises one.
    /// Such exits require cover-cert dialing the engine does not do yet, so an app
    /// can use this to pre-filter exits it cannot reach.
    pub cover_domain: Option<String>,
    /// Relative selection weight the relay list advertises for load balancing.
    pub weight: u64,
    /// Whether the relay list marks the exit currently active.
    pub is_active: bool,
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
    /// The name this install's device registers under, as this client last
    /// knew it. A system-VPN daemon registering the same device takes it
    /// from here; the registry keeps the name of a device it already holds.
    device_name: Mutex<Option<String>>,
}

impl WarrenClientFrb {
    /// Builds a client from a mnemonic and the account API configuration.
    ///
    /// The mnemonic is consumed here and not retained; the engine zeroizes the
    /// derived signing key on drop.
    ///
    /// With an `app_version`, the client registers this install as a device
    /// of the account (warren-core doc 115) on the platform this build runs
    /// on, keeping the device identity in `state_dir`, which it then needs.
    #[allow(clippy::too_many_arguments)]
    pub async fn create(
        mnemonic: String,
        api_base: String,
        api_alternative_hosts: Vec<String>,
        server_pubkey_pin: String,
        multihop_root_pin: Option<String>,
        daita: bool,
        daita_machine: Option<String>,
        request_ipv6: bool,
        state_dir: Option<String>,
        app_version: Option<String>,
    ) -> Result<WarrenClientFrb, WarrenFfiError> {
        let mut mnemonic = mnemonic;
        let identity_result = WarrenIdentity::from_mnemonic(&mnemonic);
        // The engine keeps only the zeroized derived key; wipe the bridge-side
        // copy immediately, on the error path too.
        mnemonic.zeroize();
        let identity =
            identity_result.map_err(|_| err(WarrenErrorKind::Identity, "invalid mnemonic"))?;
        let address = identity.address();

        let mut builder = WarrenClient::builder()
            .identity(identity)
            .api_base(api_base)
            .server_pubkey_pin(server_pubkey_pin);
        if !api_alternative_hosts.is_empty() {
            // Anti-censorship fallback: the engine tries these hosts (and a no-SNI
            // retry transport) when the primary API base is blocked.
            builder = builder.api_alternative_hosts(api_alternative_hosts);
        }
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
        let state_dir = state_dir.map(std::path::PathBuf::from);
        if let Some(dir) = state_dir.as_deref() {
            // Persist the anti-rollback floors and the TOFU server pin across
            // restarts, so a downgraded relay/multihop list or a swapped server
            // key cannot slip past on the next launch. Mirrors the engine FFI's
            // `with_persistence`; the filenames must match for state continuity.
            let io_err = |_| {
                err(
                    WarrenErrorKind::Api,
                    "persistence state directory is not usable",
                )
            };
            std::fs::create_dir_all(dir).map_err(io_err)?;
            let relay_gen =
                FileGenerationStore::new(dir.join("relay_generation")).map_err(io_err)?;
            let mh_gen =
                FileGenerationStore::new(dir.join("multihop_generation")).map_err(io_err)?;
            let key_store = FileServerKeyStore::new(dir.join("server_key")).map_err(io_err)?;
            builder = builder
                .generation_store(Arc::new(relay_gen))
                .multihop_generation_store(Arc::new(mh_gen))
                .server_key_store(Arc::new(key_store))
                // A restarted app leads with its predecessor's token serial, so
                // the exit hands back its inner address and forwarded ports.
                .token_rotation(warren_sdk::kept_token_rotation(&dir.join("token_rotation")));
        }
        let mut device_name = None;
        if let Some(app_version) = app_version {
            let dir = state_dir.as_deref().ok_or_else(|| {
                err(
                    WarrenErrorKind::Api,
                    "a device needs a state directory to keep its identity",
                )
            })?;
            let platform = device_platform_for(std::env::consts::OS).ok_or_else(|| {
                err(
                    WarrenErrorKind::Api,
                    "this platform cannot register a device",
                )
            })?;
            let path = dir.join(DEVICE_FILE);
            // The builder reads back the identity this call keeps, so both
            // see the same device.
            device_name = Some(warren_sdk::kept_device_identity(&path).name);
            builder = builder.device(path, platform, app_version);
        }
        let inner = builder
            .build()
            .map_err(|e| err(WarrenErrorKind::Api, e.to_string()))?;

        Ok(Self {
            inner: Arc::new(inner),
            address,
            device_name: Mutex::new(device_name),
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
            // The request DTO's pubkey is the validated `PubkeySs58` newtype;
            // `self.address` is already a valid SS58 string, so this cannot fail.
            pubkey_ss58: self
                .address
                .clone()
                .try_into()
                .map_err(|_| err(WarrenErrorKind::Identity, "invalid ss58 address"))?,
            // The DTO field turned optional (registering with no code lets the
            // server apply its campaign voucher); this path always carries one,
            // and `Some` keeps the wire form byte-identical.
            voucher_secret: Some(secret),
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
            // The engine types the country as the `CountryCode` newtype; the
            // Dart-facing DTO keeps it a plain string.
            country: resp.exit_country.map(String::from),
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
    /// When `failover_exit_pubkeys_hex` is non-empty the datapath runs over the
    /// prioritized list `[exit_pubkey_hex, ..failover]`: it sticks with the first
    /// exit that connects and only rotates to the next candidate when the current
    /// one fails to (re)establish, so one broken exit no longer wedges the session.
    ///
    /// Connect failures after this returns surface as connection state on the
    /// session, not as an error here.
    pub async fn connect_proxy(
        &self,
        exit_pubkey_hex: String,
        failover_exit_pubkeys_hex: Vec<String>,
        socks5_listen: String,
        http_listen: Option<String>,
        dns_server: Option<String>,
    ) -> Result<WarrenSessionFrb, WarrenFfiError> {
        let directory = self
            .inner
            .fetch_multihop_directory()
            .await
            .map_err(map_sdk_error)?;
        let resolve = |hex_id: &str| -> Result<VerifiedExit, WarrenFfiError> {
            let target: [u8; 32] = hex::decode(hex_id)
                .ok()
                .and_then(|bytes| bytes.try_into().ok())
                .ok_or_else(|| err(WarrenErrorKind::Discovery, "invalid exit id"))?;
            directory
                .iter()
                .find(|candidate| candidate.exit_ed25519_pubkey == target)
                .cloned()
                .ok_or_else(|| err(WarrenErrorKind::Discovery, "exit not in multihop directory"))
        };

        let primary = resolve(&exit_pubkey_hex)?;

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
                Some(addr) => Some(
                    addr.parse::<std::net::Ipv4Addr>()
                        .map_err(|_| err(WarrenErrorKind::Tunnel, "invalid dns server address"))?,
                ),
                None => None,
            },
            // Fresh per session, read back through the session's credentials.
            credentials: None,
        };

        let handle = if failover_exit_pubkeys_hex.is_empty() {
            self.inner
                .start_proxy_supervised(&Circuit::SingleHop(primary), &cfg)
                .await
                .map_err(map_sdk_error)?
        } else {
            let mut candidates = Vec::with_capacity(1 + failover_exit_pubkeys_hex.len());
            candidates.push(primary);
            for hex_id in &failover_exit_pubkeys_hex {
                candidates.push(resolve(hex_id)?);
            }
            let circuits: Vec<Circuit> = candidates.into_iter().map(Circuit::SingleHop).collect();
            self.inner
                .start_proxy_supervised_failover(&circuits, &cfg)
                .await
                .map_err(map_sdk_error)?
        };
        Ok(WarrenSessionFrb::new(handle))
    }

    /// This install's device identifier (base64url), when the client was
    /// built with an app version. Keep it out of every log.
    pub fn device_id(&self) -> Option<String> {
        self.inner.device_id().map(String::from)
    }

    /// The name this install's device registers under, as this client last
    /// knew it, when the client was built with an app version. A rename
    /// made from another device reaches it only through the next list.
    pub fn device_name(&self) -> Option<String> {
        self.device_name
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .clone()
    }

    /// Whether this install's device was revoked from another device of the
    /// account, as the last credential refresh learned. Sticky. When it reads
    /// `true` the app disconnects, says "This device was disconnected from
    /// another device of your account", calls [`Self::forget_device`] and asks
    /// for the recovery phrase again.
    pub fn device_revoked(&self) -> bool {
        self.inner.device_revoked()
    }

    /// Whether the last credential refresh found the account's device cap
    /// reached: this install is not registered and is issued no session token
    /// until another device is revoked. Not sticky.
    pub fn device_limit_reached(&self) -> bool {
        self.inner.device_limit_reached()
    }

    /// The account's devices, this install's marked `this_device`, and the
    /// last day an older client of the account was superseded.
    pub async fn list_devices(&self) -> Result<DeviceListDto, WarrenFfiError> {
        self.inner
            .list_devices()
            .await
            .map(device_list_to_dto)
            .map_err(map_sdk_error)
    }

    /// Renames a device of the account. Renaming this install's own device
    /// also keeps the name for its later registrations.
    pub async fn rename_device(
        &self,
        device_id: String,
        name: String,
    ) -> Result<(), WarrenFfiError> {
        let id = parse_device_id(device_id)?;
        self.inner
            .rename_device(id, &name)
            .await
            .map_err(map_sdk_error)?;
        if self.inner.device_id() == Some(id) {
            *self
                .device_name
                .lock()
                .unwrap_or_else(PoisonError::into_inner) = Some(name);
        }
        Ok(())
    }

    /// Revokes a device of the account. Revoking this install's own device is
    /// a logout: the next refresh reads it revoked.
    pub async fn revoke_device(&self, device_id: String) -> Result<(), WarrenFfiError> {
        let id = parse_device_id(device_id)?;
        self.inner.revoke_device(id).await.map_err(map_sdk_error)
    }

    /// Erases this install's kept device identity from the state directory,
    /// once it was revoked or logged out: the next client draws a new one.
    /// Does nothing for a client without a device.
    pub fn forget_device(&self) -> Result<(), WarrenFfiError> {
        self.inner.forget_device().map_err(|_| {
            err(
                WarrenErrorKind::Api,
                "the device identity could not be erased",
            )
        })
    }

    /// Permanently deletes the account bound to this identity (signed
    /// `DELETE /v1/account`). App stores require an in-app account-deletion path.
    pub async fn delete_account(&self) -> Result<(), WarrenFfiError> {
        self.inner
            .api()
            .delete_account()
            .await
            .map_err(map_client_error)
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
        cover_domain: relay.cover_domain().map(str::to_owned),
        weight: relay.weight(),
        is_active: relay.is_active(),
    }
}

fn map_client_error(error: ClientError) -> WarrenFfiError {
    let ban = match &error {
        ClientError::Banned {
            reason_code,
            lapses_at_unix_secs,
        } => Some(BanRefusalDto {
            reason: ban_reason_dto(reason_code),
            lapses_at_unix_secs: *lapses_at_unix_secs,
        }),
        _ => None,
    };
    let clock_skew = match &error {
        ClientError::ClockSkew { offset_secs } => Some(ClockSkewDto {
            offset_secs: *offset_secs,
        }),
        _ => None,
    };
    let device = match &error {
        ClientError::DeviceRevoked => Some(DeviceRefusalDto::Revoked),
        ClientError::DeviceLimitReached => Some(DeviceRefusalDto::LimitReached),
        _ => None,
    };
    WarrenFfiError {
        ban,
        clock_skew,
        device,
        ..err(WarrenErrorKind::Api, error.to_string())
    }
}

fn map_sdk_error(error: SdkError) -> WarrenFfiError {
    // An account API failure keeps the typed refusals (ban, clock) it carries.
    let error = match error {
        SdkError::Api(api) => return map_client_error(api),
        other => other,
    };
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

#[cfg(test)]
mod tests {
    use warren_sdk::api::{BanReasonCode, ClientError};
    use warren_sdk::SdkError;

    use super::{map_client_error, map_sdk_error, WarrenClientFrb, DEVICE_FILE};
    use crate::api::datapath::BanReasonDto;
    use crate::api::error::{DeviceRefusalDto, WarrenErrorKind, WarrenFfiError};
    use crate::api::identity::generate_mnemonic;

    async fn client(
        state_dir: Option<&std::path::Path>,
        app_version: Option<&str>,
    ) -> Result<WarrenClientFrb, WarrenFfiError> {
        WarrenClientFrb::create(
            generate_mnemonic(),
            "https://api.example.test".to_owned(),
            Vec::new(),
            "00".repeat(32),
            None,
            false,
            None,
            false,
            state_dir.map(|d| d.to_string_lossy().into_owned()),
            app_version.map(str::to_owned),
        )
        .await
    }

    /// Unwraps a bridge result; the bridge error has no `Debug` on purpose.
    fn ok<T>(result: Result<T, WarrenFfiError>) -> T {
        match result {
            Ok(value) => value,
            Err(error) => panic!("unexpected bridge error: {}", error.message),
        }
    }

    fn scratch_dir(name: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "warren-frb-test-{name}-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("clock after the epoch")
                .as_nanos()
        ));
        std::fs::create_dir_all(&dir).expect("scratch dir");
        dir
    }

    #[tokio::test]
    async fn a_client_given_an_app_version_keeps_its_device_in_the_state_dir() {
        let dir = scratch_dir("kept");

        let first = ok(client(Some(&dir), Some("1.2.0")).await);
        let second = ok(client(Some(&dir), Some("1.2.0")).await);

        let id = first.device_id().expect("a registered install has an id");
        assert_eq!(second.device_id(), Some(id), "one install, one device");
        assert!(dir.join(DEVICE_FILE).exists());
        let kept = warren_sdk::kept_device_identity(&dir.join(DEVICE_FILE));
        assert_eq!(first.device_name(), Some(kept.name));
        std::fs::remove_dir_all(&dir).ok();
    }

    #[tokio::test]
    async fn a_client_without_an_app_version_registers_no_device() {
        let dir = scratch_dir("none");

        let plain = ok(client(Some(&dir), None).await);

        assert_eq!(plain.device_id(), None);
        assert_eq!(plain.device_name(), None);
        assert!(!dir.join(DEVICE_FILE).exists());
        std::fs::remove_dir_all(&dir).ok();
    }

    #[tokio::test]
    async fn a_device_without_a_state_directory_is_refused() {
        let refused = client(None, Some("1.2.0")).await;

        let Err(error) = refused else {
            panic!("a device without a state directory was accepted");
        };
        assert!(matches!(error.kind, WarrenErrorKind::Api));
        assert!(
            error.message.contains("state directory"),
            "{}",
            error.message
        );
    }

    #[tokio::test]
    async fn a_forgotten_device_is_drawn_anew_by_the_next_client() {
        let dir = scratch_dir("forget");
        let revoked = ok(client(Some(&dir), Some("1.2.0")).await);
        let old = revoked.device_id().expect("id");

        ok(revoked.forget_device());
        let next = ok(client(Some(&dir), Some("1.2.0")).await);

        assert_ne!(next.device_id().expect("id"), old);
        std::fs::remove_dir_all(&dir).ok();
    }

    #[tokio::test]
    async fn a_malformed_device_id_is_refused_typed_before_any_call() {
        let plain = ok(client(None, None).await);

        let renamed = plain
            .rename_device("not-a-device".to_owned(), "x".to_owned())
            .await;
        let revoked = plain.revoke_device("not-a-device".to_owned()).await;

        for result in [renamed, revoked] {
            let Err(error) = result else {
                panic!("a malformed device id was accepted");
            };
            assert_eq!(error.device, Some(DeviceRefusalDto::InvalidId));
        }
    }

    #[test]
    fn a_device_revocation_crosses_the_bridge_typed() {
        let mapped = map_sdk_error(SdkError::Api(ClientError::DeviceRevoked));

        assert!(matches!(mapped.kind, WarrenErrorKind::Api));
        assert_eq!(mapped.device, Some(DeviceRefusalDto::Revoked));
        assert!(mapped.ban.is_none());
    }

    #[test]
    fn the_device_cap_crosses_the_bridge_typed() {
        let mapped = map_client_error(ClientError::DeviceLimitReached);

        assert_eq!(mapped.device, Some(DeviceRefusalDto::LimitReached));
    }

    #[test]
    fn a_ban_refusal_crosses_the_bridge_typed() {
        let mapped = map_client_error(ClientError::Banned {
            reason_code: BanReasonCode::PortForwardingAbuse,
            lapses_at_unix_secs: Some(1_790_336_000),
        });

        assert!(matches!(mapped.kind, WarrenErrorKind::Api));
        let ban = mapped.ban.expect("a ban refusal carries its ban");
        assert!(matches!(ban.reason, BanReasonDto::PortForwardingAbuse));
        assert_eq!(ban.lapses_at_unix_secs, Some(1_790_336_000));
    }

    #[test]
    fn a_ban_without_a_lapse_keeps_the_lapse_absent() {
        let mapped = map_client_error(ClientError::Banned {
            reason_code: BanReasonCode::PortForwardingAbuse,
            lapses_at_unix_secs: None,
        });

        let ban = mapped.ban.expect("a ban refusal carries its ban");
        assert_eq!(ban.lapses_at_unix_secs, None);
    }

    #[test]
    fn a_clock_refusal_crosses_the_bridge_typed_with_its_offset() {
        let mapped = map_client_error(ClientError::ClockSkew {
            offset_secs: Some(-3_600),
        });

        assert!(matches!(mapped.kind, WarrenErrorKind::Api));
        assert!(mapped.ban.is_none());
        let skew = mapped
            .clock_skew
            .expect("a clock refusal carries its clock skew");
        assert_eq!(skew.offset_secs, Some(-3_600));
    }

    #[test]
    fn a_clock_refusal_from_a_session_call_keeps_its_type() {
        let mapped = map_sdk_error(SdkError::Api(ClientError::ClockSkew { offset_secs: None }));

        assert!(matches!(mapped.kind, WarrenErrorKind::Api));
        let skew = mapped
            .clock_skew
            .expect("a clock refusal carries its clock skew");
        assert_eq!(skew.offset_secs, None);
    }

    #[test]
    fn a_plain_403_carries_no_ban() {
        let mapped = map_client_error(ClientError::ServerStatus {
            status: 403,
            body: r#"{"error":"forbidden"}"#.to_owned(),
        });

        assert!(matches!(mapped.kind, WarrenErrorKind::Api));
        assert!(mapped.ban.is_none());
        assert!(mapped.clock_skew.is_none());
        assert!(mapped.device.is_none());
    }
}
