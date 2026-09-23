//! Where and how the daemon creates its control socket. Launched through sudo it
//! acts as root on that path twice: it removes a stale entry left there, and it
//! hands the fresh socket to the invoking account. Both must only ever touch a
//! socket, in a directory no other account can rearrange.

mod common;

use std::os::unix::fs::{FileTypeExt, MetadataExt, PermissionsExt};

use common::{
    ask_daemon, scratch_dir, set_mode, spawn_daemon, stop, wait_for_exit, wait_for_listening,
    Launch,
};

#[test]
fn the_control_socket_is_owner_only_from_creation() {
    let dir = scratch_dir("mode");
    let socket = dir.join("d.sock");

    // Even a launcher that masks nothing gets an owner-only socket.
    let mut daemon = spawn_daemon(
        &socket,
        Launch {
            umask: Some(0),
            ..Launch::default()
        },
    );
    let listening = wait_for_listening(&mut daemon);
    let meta = std::fs::symlink_metadata(&socket);
    stop(&mut daemon);
    std::fs::remove_dir_all(&dir).ok();

    assert!(listening, "the daemon never announced its socket");
    let meta = meta.expect("socket present while the daemon listens");
    assert!(meta.file_type().is_socket());
    assert_eq!(
        format!("{:o}", meta.permissions().mode() & 0o777),
        "600",
        "no other account may even connect to the control socket"
    );
}

#[test]
fn the_daemon_refuses_a_socket_directory_other_accounts_can_write() {
    let dir = scratch_dir("shared");
    let shared = dir.join("shared");
    std::fs::create_dir(&shared).expect("shared dir");
    set_mode(&shared, 0o777);
    let socket = shared.join("d.sock");

    let mut daemon = spawn_daemon(&socket, Launch::default());
    let status = wait_for_exit(&mut daemon);
    let bound = std::fs::symlink_metadata(&socket).is_ok();
    std::fs::remove_dir_all(&dir).ok();

    assert!(
        status.is_some_and(|status| !status.success()),
        "the daemon must refuse to start: {status:?}"
    );
    assert!(!bound, "nothing may be bound in a directory others control");
}

#[test]
fn the_daemon_never_removes_a_non_socket_at_its_path() {
    let dir = scratch_dir("stale");
    let socket = dir.join("d.sock");
    std::fs::write(&socket, "not a socket").expect("regular file");

    let mut daemon = spawn_daemon(&socket, Launch::default());
    let status = wait_for_exit(&mut daemon);
    let left = std::fs::read_to_string(&socket);
    std::fs::remove_dir_all(&dir).ok();

    assert!(
        status.is_some_and(|status| !status.success()),
        "the daemon must refuse to start: {status:?}"
    );
    assert_eq!(
        left.expect("the file is still there"),
        "not a socket",
        "a root daemon given any path must never delete what it finds there"
    );
}

#[test]
fn a_missing_socket_directory_is_created_writable_by_its_owner_only() {
    let dir = scratch_dir("create");
    let run_dir = dir.join("run");
    let socket = run_dir.join("d.sock");

    // A launcher mask that would hide the directory from the app connecting.
    let mut daemon = spawn_daemon(
        &socket,
        Launch {
            umask: Some(0o077),
            ..Launch::default()
        },
    );
    let listening = wait_for_listening(&mut daemon);
    let meta = std::fs::symlink_metadata(&run_dir);
    stop(&mut daemon);
    std::fs::remove_dir_all(&dir).ok();

    assert!(listening, "the daemon never announced its socket");
    let meta = meta.expect("the socket directory was created");
    assert!(meta.is_dir());
    assert_eq!(format!("{:o}", meta.permissions().mode() & 0o7777), "755");
}

#[test]
fn a_second_daemon_on_the_same_socket_leaves_the_first_one_serving() {
    let dir = scratch_dir("second");
    let socket = dir.join("d.sock");

    let mut first = spawn_daemon(&socket, Launch::default());
    let listening = wait_for_listening(&mut first);
    let mut second = spawn_daemon(&socket, Launch::default());
    let second_status = wait_for_exit(&mut second);
    let reply = ask_daemon(&socket);
    stop(&mut first);
    std::fs::remove_dir_all(&dir).ok();

    assert!(listening, "the first daemon never announced its socket");
    assert!(
        second_status.is_some_and(|status| !status.success()),
        "the second daemon must refuse to start: {second_status:?}"
    );
    assert!(
        reply
            .as_deref()
            .is_some_and(|r| r.contains("malformed request")),
        "the first daemon must still serve its socket: {reply:?}"
    );
}

#[test]
fn the_socket_is_handed_to_the_account_sudo_recorded() {
    // Unprivileged, the daemon can only hand the socket to this account, but
    // it can move the group to any group this account belongs to, which makes
    // the hand-off observable.
    let ids = |flag: &str| -> Vec<u32> {
        let out = std::process::Command::new("id")
            .arg(flag)
            .output()
            .expect("id");
        String::from_utf8_lossy(&out.stdout)
            .split_whitespace()
            .filter_map(|id| id.parse().ok())
            .collect()
    };
    let uid = ids("-u")[0];
    let primary = ids("-g")[0];
    let Some(other_group) = ids("-G").into_iter().find(|gid| *gid != primary) else {
        eprintln!("this account has no supplementary group; the hand-off is not observable");
        return;
    };
    let dir = scratch_dir("handoff");
    let socket = dir.join("d.sock");

    let mut daemon = spawn_daemon(
        &socket,
        Launch {
            sudo_ids: Some((uid, other_group)),
            ..Launch::default()
        },
    );
    let listening = wait_for_listening(&mut daemon);
    let meta = std::fs::symlink_metadata(&socket);
    stop(&mut daemon);
    std::fs::remove_dir_all(&dir).ok();

    assert!(listening, "the daemon never announced its socket");
    let meta = meta.expect("socket present while the daemon listens");
    assert_eq!((meta.uid(), meta.gid()), (uid, other_group));
}
