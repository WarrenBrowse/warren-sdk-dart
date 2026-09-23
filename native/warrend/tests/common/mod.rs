//! Shared helpers for the tests that launch the real `warrend` binary. Launched
//! unprivileged, the daemon runs its startup (environment reset, firewall
//! detection, socket setup) and serves its socket, and leaves the host's DNS
//! alone; only the TUN bring-up needs root, and no test here reaches it.

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
    /// `SUDO_UID` / `SUDO_GID` as sudo would set them. Unset otherwise, even
    /// when the test itself runs under sudo.
    pub sudo_ids: Option<(u32, u32)>,
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
    command.env_remove("SUDO_UID").env_remove("SUDO_GID");
    if let Some((uid, gid)) = launch.sudo_ids {
        command
            .env("SUDO_UID", uid.to_string())
            .env("SUDO_GID", gid.to_string());
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

/// Connects to the daemon and has it answer: a malformed frame draws a
/// `malformed request` error and touches nothing on the host. Returns the
/// daemon's reply, or `None` when nothing answers.
pub fn ask_daemon(socket: &Path) -> Option<String> {
    use std::io::{Read, Write};
    use std::os::unix::net::UnixStream;

    let mut stream = UnixStream::connect(socket).ok()?;
    stream
        .set_read_timeout(Some(Duration::from_secs(10)))
        .ok()?;
    let payload = b"{}";
    stream
        .write_all(&(payload.len() as u32).to_be_bytes())
        .ok()?;
    stream.write_all(payload).ok()?;
    let mut len = [0u8; 4];
    stream.read_exact(&mut len).ok()?;
    let mut reply = vec![0u8; u32::from_be_bytes(len) as usize];
    stream.read_exact(&mut reply).ok()?;
    String::from_utf8(reply).ok()
}
