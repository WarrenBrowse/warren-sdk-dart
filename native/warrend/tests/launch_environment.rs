//! The daemon runs as root and shells out to firewall and network tools. What it
//! runs must not depend on the environment of whoever launched it: sudo passes
//! the caller's PATH through unless the host sets `secure_path`, which macOS
//! does not.

mod common;

use common::{scratch_dir, set_mode, spawn_daemon, stop, wait_for_listening, Launch};

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
        set_mode(&script, 0o755);
    }
    let caller_path = format!(
        "{}:{}",
        planted.display(),
        std::env::var("PATH").unwrap_or_default()
    );

    let mut daemon = spawn_daemon(
        &dir.join("d.sock"),
        Launch {
            path_variable: Some(&caller_path),
            ..Launch::default()
        },
    );
    // Startup reconciles the firewall and DNS before it binds, so every tool
    // the daemon runs at startup has run once the socket is announced.
    let listening = wait_for_listening(&mut daemon);
    stop(&mut daemon);
    let ran = std::fs::read_to_string(&marker).unwrap_or_default();
    std::fs::remove_dir_all(&dir).ok();

    assert!(listening, "the daemon never announced its socket");
    assert!(
        ran.is_empty(),
        "the daemon ran tools planted in the caller's PATH: {ran:?}"
    );
}

#[test]
fn the_daemon_starts_whatever_names_its_environment_holds() {
    // A name std cannot remove (here one starting with `=`) must not abort the
    // reset that runs before anything else.
    let output = std::process::Command::new(env!("CARGO_BIN_EXE_warrend"))
        .arg("--help")
        .env("=planted", "1")
        .output()
        .expect("run warrend --help");

    assert!(
        output.status.success(),
        "warrend --help failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
}
