//! The flutter_rust_bridge API surface.
//!
//! Organized by concern, mirroring the engine layers and the roadmap phases:
//! - [`identity`]: stateless identity helpers (P1).
//! - [`client`]: the account API over a live engine client (P2).
//! - [`datapath`]: the proxy session and its connection-state stream (P3).
//! - [`error`]: the typed error mirrored to Dart.

pub mod client;
pub mod datapath;
pub mod error;
pub mod identity;
