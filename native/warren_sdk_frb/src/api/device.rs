//! The account's device registry (warren-core doc 115), mirrored for Dart.
//!
//! Registration, listing, renaming and revocation all live in the engine; this
//! module only carries the engine's answers across the bridge and names the
//! platform this build registers from.

use warren_sdk::api::{DeviceListResponse, DevicePlatform};

/// Where a device runs, mirrored for Dart as a plain enum.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DevicePlatformDto {
    /// Android app.
    Android,
    /// iOS app.
    Ios,
    /// macOS desktop app.
    Macos,
    /// Windows desktop app.
    Windows,
    /// Linux desktop app.
    Linux,
    /// A command-line client (warren-cli, wclaude).
    Cli,
    /// The browser extension's helper.
    Browser,
    /// A platform this build does not know.
    Other,
}

/// One device of the account. Its identifier and name belong in the account's
/// own UI, never in a log.
pub struct DeviceDto {
    /// The install's identifier, base64url: what `rename_device` and
    /// `revoke_device` take.
    pub device_id: String,
    /// Its name.
    pub name: String,
    /// Where it runs.
    pub platform: DevicePlatformDto,
    /// The app version it last registered with.
    pub app_version: String,
    /// The day it registered, `YYYY-MM-DD`.
    pub registered_on: String,
    /// The last day it was seen, `YYYY-MM-DD`.
    pub last_seen_on: String,
    /// Whether it is this install.
    pub this_device: bool,
}

/// The account's devices.
pub struct DeviceListDto {
    /// The active devices.
    pub devices: Vec<DeviceDto>,
    /// The last day an older client of the account (one that does not
    /// register) was superseded by a registered device, `YYYY-MM-DD`.
    pub older_client_seen_on: Option<String>,
}

pub(crate) fn platform_to_dto(platform: DevicePlatform) -> DevicePlatformDto {
    match platform {
        DevicePlatform::Android => DevicePlatformDto::Android,
        DevicePlatform::Ios => DevicePlatformDto::Ios,
        DevicePlatform::Macos => DevicePlatformDto::Macos,
        DevicePlatform::Windows => DevicePlatformDto::Windows,
        DevicePlatform::Linux => DevicePlatformDto::Linux,
        DevicePlatform::Cli => DevicePlatformDto::Cli,
        DevicePlatform::Browser => DevicePlatformDto::Browser,
        DevicePlatform::Other => DevicePlatformDto::Other,
    }
}

pub(crate) fn device_list_to_dto(list: DeviceListResponse) -> DeviceListDto {
    DeviceListDto {
        devices: list
            .devices
            .into_iter()
            .map(|d| DeviceDto {
                device_id: String::from(d.device_id),
                name: d.name,
                platform: platform_to_dto(d.platform),
                app_version: d.app_version,
                registered_on: d.registered_on,
                last_seen_on: d.last_seen_on,
                this_device: d.this_device,
            })
            .collect(),
        older_client_seen_on: list.older_client_seen_on,
    }
}

/// The platform an app built for `os` (`std::env::consts::OS`) registers as,
/// or `None` for an operating system no Flutter app ships on.
pub(crate) fn device_platform_for(os: &str) -> Option<DevicePlatform> {
    match os {
        "android" => Some(DevicePlatform::Android),
        "ios" => Some(DevicePlatform::Ios),
        "macos" => Some(DevicePlatform::Macos),
        "windows" => Some(DevicePlatform::Windows),
        "linux" => Some(DevicePlatform::Linux),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use warren_sdk::api::{DeviceId, DeviceListResponse, DevicePlatform, DeviceView};

    use super::{device_list_to_dto, device_platform_for, DevicePlatformDto};

    #[test]
    fn each_flutter_target_registers_as_its_own_platform() {
        for (os, platform) in [
            ("android", DevicePlatform::Android),
            ("ios", DevicePlatform::Ios),
            ("macos", DevicePlatform::Macos),
            ("windows", DevicePlatform::Windows),
            ("linux", DevicePlatform::Linux),
        ] {
            assert_eq!(device_platform_for(os), Some(platform), "{os}");
        }
    }

    #[test]
    fn an_os_no_app_ships_on_registers_no_platform() {
        assert_eq!(device_platform_for("freebsd"), None);
    }

    #[test]
    fn a_listed_device_crosses_the_bridge_whole() {
        let id = DeviceId::from_bytes([7; 16]);
        let list = DeviceListResponse {
            devices: vec![DeviceView {
                device_id: id,
                name: "quiet otter".to_owned(),
                platform: DevicePlatform::Ios,
                app_version: "1.2.0".to_owned(),
                registered_on: "2026-10-01".to_owned(),
                last_seen_on: "2026-10-28".to_owned(),
                this_device: true,
            }],
            older_client_seen_on: Some("2026-10-27".to_owned()),
        };

        let dto = device_list_to_dto(list);

        let device = &dto.devices[0];
        assert_eq!(device.device_id, String::from(id));
        assert_eq!(device.name, "quiet otter");
        assert_eq!(device.platform, DevicePlatformDto::Ios);
        assert_eq!(device.app_version, "1.2.0");
        assert_eq!(device.registered_on, "2026-10-01");
        assert_eq!(device.last_seen_on, "2026-10-28");
        assert!(device.this_device);
        assert_eq!(dto.older_client_seen_on.as_deref(), Some("2026-10-27"));
    }

    #[test]
    fn a_platform_this_build_does_not_know_reads_as_other() {
        assert_eq!(
            super::platform_to_dto(DevicePlatform::Other),
            DevicePlatformDto::Other
        );
    }
}
