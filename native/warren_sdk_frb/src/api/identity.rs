//! Stateless identity helpers.
//!
//! Thin delegation to `warren_sdk::identity`. These are pure and pinned by the
//! shared golden vectors, so the Dart surface stays wire-identical to every
//! sibling SDK.

use anyhow::{anyhow, Result};
use warren_sdk::identity::{ss58, WarrenIdentity};
use zeroize::Zeroize;

/// Authentication material for a signed Warren API request.
///
/// Mirrors the engine's `RequestSignature` as a plain, bridge-friendly struct so
/// flutter_rust_bridge can marshal it to a Dart value.
pub struct SignedRequest {
    /// The signer's SS58 `wb...` address.
    pub pubkey_ss58: String,
    /// The 64-byte Ed25519 signature, hex-encoded.
    pub signature_hex: String,
    /// The request timestamp echoed back, in seconds.
    pub timestamp: u64,
    /// The 16-byte nonce echoed back, hex-encoded.
    pub nonce_hex: String,
}

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
    let mut mnemonic = mnemonic;
    let address = WarrenIdentity::from_mnemonic(&mnemonic).map(|identity| identity.address());
    // Wipe the bridge-side copy once the address is derived, error path included.
    mnemonic.zeroize();
    address.map_err(|_| anyhow!("invalid mnemonic"))
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

/// Signs a Warren API request deterministically from a 32-byte seed.
///
/// Low-level conformance and utility surface: production signing happens inside
/// the engine client, but this primitive replays the shared `request_signature`
/// golden vectors across the bridge, pinning the wire format and the binary body
/// marshalling. `seed_hex` is 32 bytes (64 hex chars); `nonce_hex` is 16 bytes
/// (32 hex chars). Errors are redacted: no seed or signature is echoed.
pub fn sign_request(
    seed_hex: String,
    method: String,
    path: String,
    body: Vec<u8>,
    timestamp: u64,
    nonce_hex: String,
) -> Result<SignedRequest> {
    let seed: [u8; 32] = hex::decode(&seed_hex)
        .map_err(|_| anyhow!("seed is not valid hex"))?
        .try_into()
        .map_err(|_| anyhow!("seed must be 32 bytes"))?;
    let nonce: [u8; 16] = hex::decode(&nonce_hex)
        .map_err(|_| anyhow!("nonce is not valid hex"))?
        .try_into()
        .map_err(|_| anyhow!("nonce must be 16 bytes"))?;

    let identity = WarrenIdentity::from_seed(&seed);
    let sig = identity.sign_request(&method, &path, &body, timestamp, nonce);
    Ok(SignedRequest {
        pubkey_ss58: sig.pubkey_ss58,
        signature_hex: sig.signature_hex,
        timestamp: sig.timestamp,
        nonce_hex: sig.nonce_hex,
    })
}
