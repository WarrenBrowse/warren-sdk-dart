//! The app's device, registered by the daemon (warren-core doc 115).
//!
//! An install is one device of its account. The app keeps the device identity
//! in its own state directory and drives two engines: its in-process client and
//! this daemon, whose engine issues the system-VPN session's credentials. The
//! daemon registers under the identity the app sends in `configure`, so both
//! present one device, which the account lists once and revokes once.
//!
//! The engine keeps a device identity in a file it reads at build and writes
//! when the registry renames the device. The daemon runs as root, so it never
//! acts on a path a client names: it writes the identity it was sent into a
//! directory of its own, private to root, removed with the session.

use std::fs::DirBuilder;
use std::os::unix::fs::DirBuilderExt;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use anyhow::{Context, Result};
use warren_sdk::api::{DeviceId, DeviceIdentity, DevicePlatform};

/// The device a configure request names: who registers, and from which app.
pub struct DeviceRequest {
    pub device_id: String,
    pub name: String,
    pub app_version: String,
}

/// The platform this daemon registers its host as, from the operating system
/// it was built for (`std::env::consts::OS`).
pub fn platform_for(os: &str) -> Option<DevicePlatform> {
    match os {
        "macos" => Some(DevicePlatform::Macos),
        "windows" => Some(DevicePlatform::Windows),
        "linux" => Some(DevicePlatform::Linux),
        _ => None,
    }
}

/// The device identity file of one session, in a root-private directory
/// removed when this is dropped.
pub struct DeviceFile {
    dir: PathBuf,
    path: PathBuf,
}

impl DeviceFile {
    /// Writes the identity `request` names into a fresh private directory
    /// under `base`.
    ///
    /// # Errors
    ///
    /// The identifier is malformed, or the directory or the file cannot be
    /// written.
    pub fn create(base: &Path, request: &DeviceRequest) -> Result<Self> {
        let device_id = DeviceId::try_from(request.device_id.clone())
            .map_err(|_| anyhow::anyhow!("invalid device id"))?;
        let identity = DeviceIdentity {
            device_id,
            name: request.name.clone(),
        };
        let dir = private_dir(base)?;
        let file = Self {
            path: dir.join("device"),
            dir,
        };
        let json = serde_json::to_vec(&identity).context("encoding the device identity")?;
        std::fs::write(&file.path, json).context("writing the device identity")?;
        Ok(file)
    }

    /// Where the engine keeps the identity.
    pub fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for DeviceFile {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

/// Creates a new directory under `base`, mode 0700. `create` (not
/// `create_all`) refuses a name that already exists, link or not, so a path
/// planted in a shared temporary directory is never adopted; a fresh name is
/// drawn instead.
fn private_dir(base: &Path) -> Result<PathBuf> {
    static SEQUENCE: AtomicU64 = AtomicU64::new(0);
    for _ in 0..16 {
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.subsec_nanos());
        let name = format!(
            "warrend-device-{}-{}-{nanos}",
            std::process::id(),
            SEQUENCE.fetch_add(1, Ordering::Relaxed)
        );
        let dir = base.join(name);
        match DirBuilder::new().mode(0o700).create(&dir) {
            Ok(()) => return Ok(dir),
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(e).context("creating the device directory"),
        }
    }
    anyhow::bail!("no free name for the device directory")
}

#[cfg(test)]
mod tests {
    use std::os::unix::fs::PermissionsExt;

    use super::*;

    fn request(device_id: &str) -> DeviceRequest {
        DeviceRequest {
            device_id: device_id.to_owned(),
            name: "quiet otter".to_owned(),
            app_version: "1.2.0".to_owned(),
        }
    }

    fn scratch() -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "warrend-device-test-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("clock after the epoch")
                .as_nanos()
        ));
        std::fs::create_dir_all(&dir).expect("scratch");
        dir
    }

    #[test]
    fn the_engine_reads_back_the_identity_the_app_sent() {
        let base = scratch();
        let id = String::from(DeviceId::from_bytes([9; 16]));

        let file = DeviceFile::create(&base, &request(&id)).expect("device file");
        let kept = warren_sdk::kept_device_identity(file.path());

        assert_eq!(String::from(kept.device_id), id);
        assert_eq!(kept.name, "quiet otter");
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn the_identity_lives_in_a_directory_only_root_can_enter() {
        let base = scratch();
        let id = String::from(DeviceId::from_bytes([9; 16]));

        let file = DeviceFile::create(&base, &request(&id)).expect("device file");
        let mode = std::fs::metadata(file.path().parent().expect("dir"))
            .expect("dir metadata")
            .permissions()
            .mode();

        assert_eq!(mode & 0o777, 0o700);
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn the_identity_goes_with_the_session() {
        let base = scratch();
        let id = String::from(DeviceId::from_bytes([9; 16]));
        let file = DeviceFile::create(&base, &request(&id)).expect("device file");
        let dir = file.path().parent().expect("dir").to_owned();

        drop(file);

        assert!(!dir.exists());
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn a_malformed_identifier_is_refused() {
        let base = scratch();

        let refused = DeviceFile::create(&base, &request("not-a-device"));

        assert!(refused.is_err());
        assert_eq!(std::fs::read_dir(&base).expect("base").count(), 0);
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn each_desktop_os_registers_as_its_own_platform() {
        assert_eq!(platform_for("macos"), Some(DevicePlatform::Macos));
        assert_eq!(platform_for("windows"), Some(DevicePlatform::Windows));
        assert_eq!(platform_for("linux"), Some(DevicePlatform::Linux));
        assert_eq!(platform_for("android"), None);
    }
}
