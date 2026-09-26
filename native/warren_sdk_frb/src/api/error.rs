//! The typed error crossing the bridge.
//!
//! flutter_rust_bridge mirrors these as a Dart enum plus a plain class, so
//! `warren_sdk_ffi` maps `kind` to the matching sealed `WarrenError` without
//! parsing strings and without pulling in a code-generated union (freezed).
//! Messages are already redacted by the engine (no key, address or IP).

use crate::api::datapath::BanReasonDto;

/// Category of a redacted failure crossing the bridge.
pub enum WarrenErrorKind {
    /// The mnemonic, key or signing input was malformed.
    Identity,
    /// An account API call failed (network, auth, server).
    Api,
    /// Relay-list verification or exit selection failed.
    Discovery,
    /// The tunnel or datapath failed.
    Tunnel,
    /// A privileged-mode failure (daemon or extension unavailable).
    Privilege,
}

/// A categorized, redacted failure surfaced to Dart.
pub struct WarrenFfiError {
    /// The failure category, mapped to a sealed `WarrenError` subtype in Dart.
    pub kind: WarrenErrorKind,
    /// A redacted, human-readable description. Safe to log and display.
    pub message: String,
    /// Present when the server refused the call because the account is
    /// banned. A refused voucher redemption leaves the voucher unredeemed.
    pub ban: Option<BanRefusalDto>,
}

/// The server's ban refusal (403 `{"error":"banned"}`), typed for Dart.
pub struct BanRefusalDto {
    /// Why the account is banned.
    pub reason: BanReasonDto,
    /// When the ban lapses on its own, Unix seconds. Absent for a ban that
    /// does not lapse, and when the refusing endpoint does not say.
    pub lapses_at_unix_secs: Option<u64>,
}
