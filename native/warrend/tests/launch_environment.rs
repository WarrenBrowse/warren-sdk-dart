//! The daemon runs as root and shells out to firewall and network tools. What it
//! runs must not depend on the environment of whoever launched it: sudo passes
//! the caller's PATH through unless the host sets `secure_path`, which macOS
//! does not.

use std::io::{BufRead, BufReader};
use std::os::unix::fs::PermissionsExt;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::mpsc;
use std::time::Duration;

/// A fresh private directory for one test (mode 0700, owned by this account).
fn scratch_dir(tag: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("warrend-{tag}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir(&dir).expect("scratch dir");
    std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o700))
        .expect("scratch dir mode");
    dir
}

/// Waits until the daemon announces its socket on stderr.
fn wait_for_listening(daemon: &mut Child) -> bool {
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

#[test]
fn the_daemon_never_runs_a_tool_planted_in_the_callers_path() {
    let dir = scratch_dir("path");
    let planted = dir.join("bin");
    std::fs::create_dir(&planted).expect("planted bin dir");
    let marker = dir.join("ran");
    for tool in ["pfctl", "nft", "networksetup"] {
        let script = planted.join(tool);
        std::fs::write(
            &script,
            format!("#!/bin/sh\necho {tool} >> '{}'\nexit 1\n", marker.display()),
        )
        .expect("planted tool");
        std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o755))
            .expect("planted tool mode");
    }
    let caller_path = format!(
        "{}:{}",
        planted.display(),
        std::env::var("PATH").unwrap_or_default()
    );

    let mut daemon = Command::new(env!("CARGO_BIN_EXE_warrend"))
        .arg(dir.join("d.sock"))
        .env("PATH", caller_path)
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn warrend");
    // Startup reconciles the firewall and DNS before it binds, so every tool
    // the daemon runs at startup has run once the socket is announced.
    let listening = wait_for_listening(&mut daemon);
    daemon.kill().ok();
    daemon.wait().ok();
    let ran = std::fs::read_to_string(&marker).unwrap_or_default();
    std::fs::remove_dir_all(&dir).ok();

    assert!(listening, "the daemon never announced its socket");
    assert!(
        ran.is_empty(),
        "the daemon ran tools planted in the caller's PATH: {ran:?}"
    );
}
