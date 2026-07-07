//! The flutter_rust_bridge API surface.
//!
//! Organized by concern, mirroring the engine layers:
//! - [`identity`]: stateless identity helpers.
//! - [`client`]: the account API over a live engine client.
//! - [`datapath`]: the proxy session and its connection-state stream.
//! - [`error`]: the typed error mirrored to Dart.

pub mod client;
pub mod datapath;
pub mod error;
pub mod identity;
