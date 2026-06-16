//! The flutter_rust_bridge API surface.
//!
//! Organized by concern, mirroring the engine layers and the roadmap phases:
//! - [`identity`]: stateless identity helpers (P1).
//! - [`client`]: the account API over a live engine client (P2).
//! - [`error`]: the typed error mirrored to Dart.
//! - datapath: proxy session (P3), added as that phase lands.

pub mod client;
pub mod error;
pub mod identity;
