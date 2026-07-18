//! The daemon's stop-time kill-switch posture decision, single-homed here so
//! every stop path (explicit disconnect, shutdown signal, owner connection
//! loss) reads the same rule.
//!
//! The values mirror the shared cross-client matrix
//! `warren_contract::killswitch::expected_posture` row for row. They are
//! duplicated rather than imported because this repo's CI checks the
//! warren-contract sibling out at the rev the pinned engine expects, so
//! warrend cannot depend on a newer contract rev than the engine does; the
//! pinned table below is the drift guard until the engine pin catches up and
//! a direct contract dep becomes possible.

/// Why the daemon is deciding a stop posture. Only stops with a protected
/// session (or a held block) reach this decision.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StopTrigger {
    /// The owner asked to disconnect (IPC `disconnect`).
    UserDisconnect,
    /// The daemon was asked to stop (SIGINT / SIGTERM).
    DaemonShutdown,
    /// The owner connection vanished without a prior disconnect: app crash,
    /// kill, or a dropped control socket.
    OwnerConnectionLost,
}

/// What the stop path must do with the installed network block.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StopAction {
    /// Tear the rules down and restore the host network.
    RestoreNetwork,
    /// Leave the block holding: no traffic may leak past a gone controller.
    HoldBlock,
}

/// The single decision table.
#[must_use]
pub fn stop_action(trigger: StopTrigger, lockdown: bool) -> StopAction {
    match trigger {
        // User-intended ends open the network unless lockdown mode is on
        // (contract: `lockdown ? Blocking : Open`).
        StopTrigger::UserDisconnect | StopTrigger::DaemonShutdown => {
            if lockdown {
                StopAction::HoldBlock
            } else {
                StopAction::RestoreNetwork
            }
        }
        // An abnormal owner end always holds (contract: `Blocking`): the
        // owner dying is exactly when protected traffic would otherwise leak.
        StopTrigger::OwnerConnectionLost => StopAction::HoldBlock,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use StopAction::{HoldBlock, RestoreNetwork};
    use StopTrigger::*;

    #[test]
    fn the_stop_table_is_pinned_to_the_shared_contract() {
        // Mirrors warren_contract::killswitch::expected_posture (UserDisconnect,
        // DaemonShutdown, OwnerConnectionLost rows). A change here is a
        // cross-client security semantics change and must move in lockstep
        // with the contract matrix.
        let cases = [
            (UserDisconnect, false, RestoreNetwork),
            (UserDisconnect, true, HoldBlock),
            (DaemonShutdown, false, RestoreNetwork),
            (DaemonShutdown, true, HoldBlock),
            (OwnerConnectionLost, false, HoldBlock),
            (OwnerConnectionLost, true, HoldBlock),
        ];
        for (trigger, lockdown, expected) in cases {
            assert_eq!(
                stop_action(trigger, lockdown),
                expected,
                "{trigger:?} with lockdown={lockdown} must be {expected:?}"
            );
        }
    }

    #[test]
    fn an_owner_loss_never_restores_the_network() {
        for lockdown in [false, true] {
            assert_eq!(
                stop_action(OwnerConnectionLost, lockdown),
                HoldBlock,
                "a vanished owner is a leak moment, not an intent to open"
            );
        }
    }
}
