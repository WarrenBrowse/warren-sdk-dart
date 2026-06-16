//! The flutter_rust_bridge API surface.
//!
//! Organized by concern, mirroring the engine layers and the roadmap phases:
//! - [`identity`]: stateless identity helpers (P1).
//! - client and datapath: account + proxy (P2, P3), added as those phases land.

pub mod identity;
