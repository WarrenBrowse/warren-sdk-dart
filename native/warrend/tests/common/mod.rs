//! Shared helpers for the tests that launch the real `warrend` binary. Launched
//! unprivileged, the daemon runs its whole startup (environment, firewall and
//! DNS reconcile, socket setup) and serves its socket; only the TUN bring-up
//! needs root, and no test here reaches it.

#![allow(dead_code)]

use std::io::{BufRead, BufReader};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, ExitStatus, Stdio};
use std::sync::mpsc;
use std::time::{Duration, Instant};

/// A fresh private directory for one test (mode 0700, owned by this account).
pub fn scratch_dir(tag: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("warrend-{tag}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir(&dir).expect("scratch dir");
    set_mode(&dir, 0o700);
    dir
}

/// Sets the permission bits of `path`.
pub fn set_mode(path: &Path, mode: u32) {
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(mode)).expect("chmod");
}

/// How the test launches the daemon, beyond the socket path.
#[derive(Default)]
pub struct Launch<'a> {
    /// Replaces the launcher's PATH.
    pub path_variable: Option<&'a str>,
    /// The file-creation mask the daemon inherits.
    pub umask: Option<libc::mode_t>,
}

/// Starts the daemon on `socket` with stderr piped.
pub fn spawn_daemon(socket: &Path, launch: Launch<'_>) -> Child {
    use std::os::unix::process::CommandExt;

    let mut command = Command::new(env!("CARGO_BIN_EXE_warrend"));
    command
        .arg(socket)
        .stdout(Stdio::null())
        .stderr(Stdio::piped());
    if let Some(path_variable) = launch.path_variable {
        command.env("PATH", path_variable);
    }
    if let Some(mask) = launch.umask {
        // SAFETY: umask is async-signal-safe and touches only the child.
        unsafe {
            command.pre_exec(move || {
                libc::umask(mask);
                Ok(())
            });
        }
    }
    command.spawn().expect("spawn warrend")
}

/// Waits until the daemon announces its socket on stderr.
pub fn wait_for_listening(daemon: &mut Child) -> bool {
    let stderr = daemon.stderr.take().expect("piped stderr");
    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || {
        for line in BufReader::new(stderr).lines().map_while(Result::ok) {
            if line.contains("listening") {
                let _ = tx.send(());
            }
        }
    });
    rx.recv_timeout(Duration::from_secs(30)).is_ok()
}

/// Waits for the daemon to exit on its own, or kills it after 30 s.
pub fn wait_for_exit(daemon: &mut Child) -> Option<ExitStatus> {
    let deadline = Instant::now() + Duration::from_secs(30);
    while Instant::now() < deadline {
        if let Ok(Some(status)) = daemon.try_wait() {
            return Some(status);
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    stop(daemon);
    None
}

/// Kills the daemon and reaps it.
pub fn stop(daemon: &mut Child) {
    daemon.kill().ok();
    daemon.wait().ok();
}
