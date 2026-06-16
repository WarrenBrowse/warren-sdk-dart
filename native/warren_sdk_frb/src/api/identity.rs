//! Stateless identity helpers (roadmap P1).
//!
//! Thin delegation to `warren_sdk::identity`. These are pure and pinned by the
//! shared golden vectors, so the Dart surface stays wire-identical to every
//! sibling SDK.

use anyhow::{anyhow, Result};
use warren_sdk::identity::{ss58, WarrenIdentity};

/// Generates a fresh 12-word BIP39 mnemonic.
///
/// The returned string is secret; the caller (Dart) must persist it through the
/// platform secure store and drop its reference.
pub fn generate_mnemonic() -> String {
    let (_identity, mnemonic) = WarrenIdentity::generate();
    mnemonic
}

/// Derives the SS58 `wb...` address from a mnemonic.
///
/// Returns a redacted error if the mnemonic is malformed (no secret material is
/// included in the message).
pub fn address_from_mnemonic(mnemonic: String) -> Result<String> {
    let identity =
        WarrenIdentity::from_mnemonic(&mnemonic).map_err(|_| anyhow!("invalid mnemonic"))?;
    Ok(identity.address())
}

/// Encodes a 32-byte public key (hex) to its SS58 `wb...` address.
pub fn ss58_encode(public_key_hex: String) -> Result<String> {
    let bytes = hex::decode(&public_key_hex).map_err(|_| anyhow!("public key is not valid hex"))?;
    let key: [u8; 32] = bytes
        .try_into()
        .map_err(|_| anyhow!("public key must be 32 bytes"))?;
    Ok(ss58::encode(&key))
}

/// Decodes an SS58 `wb...` address back to its public key hex.
pub fn ss58_decode(address: String) -> Result<String> {
    let key = ss58::decode(&address).map_err(|_| anyhow!("invalid SS58 address"))?;
    Ok(hex::encode(key))
}
