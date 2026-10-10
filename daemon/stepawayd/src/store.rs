//! Paired devices, persisted as JSON with owner-only permissions.
//!
//! TODO(security): move secrets to the OS keyring (Secret Service / DPAPI); for now the file is
//! 0600 on Unix and lives in the per-user profile on Windows.

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use stepaway_core::token::Secret;

#[derive(Clone, Serialize, Deserialize)]
pub struct Device {
    pub device_id: u16,
    pub name: String,
    secret_hex: String,
    pub paired_at: u64,
    pub last_counter: Option<u64>,
    /// "phone", "tablet", "watch" or "other" (only used for the icon and wording).
    #[serde(default = "default_kind")]
    pub kind: String,
    /// A plain Bluetooth device tracked by its address: it can lock the computer but can never
    /// unlock it, because it cannot prove who it is.
    #[serde(default)]
    pub presence_only: bool,
    #[serde(default)]
    pub address: Option<String>,
    /// Per-device distance calibration (a watch and a phone read very differently).
    #[serde(default)]
    pub tx_power_1m: Option<f64>,
    #[serde(default)]
    pub path_loss_n: Option<f64>,
    #[serde(skip)]
    pub last_seen_unix: Option<u64>,
}

fn default_kind() -> String {
    "phone".into()
}

pub const KINDS: &[&str] = &["phone", "tablet", "watch", "other"];

pub fn valid_kind(k: &str) -> bool {
    KINDS.contains(&k)
}

/// `AA:BB:CC:DD:EE:FF`
pub fn valid_address(a: &str) -> bool {
    let parts: Vec<&str> = a.split(':').collect();
    parts.len() == 6
        && parts
            .iter()
            .all(|p| p.len() == 2 && p.chars().all(|c| c.is_ascii_hexdigit()))
}

impl std::fmt::Debug for Device {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Device")
            .field("device_id", &self.device_id)
            .field("name", &self.name)
            .field("secret", &"<redacted>")
            .finish()
    }
}

pub fn hex_encode(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

fn hex_decode(s: &str) -> Option<Vec<u8>> {
    if !s.len().is_multiple_of(2) || !s.is_ascii() {
        return None;
    }
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).ok())
        .collect()
}

impl Device {
    pub fn new(
        device_id: u16,
        name: String,
        secret: &Secret,
        paired_at: u64,
        counter: Option<u64>,
    ) -> Self {
        Self {
            device_id,
            name,
            secret_hex: hex_encode(secret.as_bytes()),
            paired_at,
            last_counter: counter,
            kind: default_kind(),
            presence_only: false,
            address: None,
            tx_power_1m: None,
            path_loss_n: None,
            last_seen_unix: None,
        }
    }

    /// A lock-only device identified by its Bluetooth address (no secret).
    pub fn presence_only(
        device_id: u16,
        name: String,
        kind: &str,
        address: &str,
        paired_at: u64,
    ) -> Self {
        Self {
            device_id,
            name,
            secret_hex: String::new(),
            paired_at,
            last_counter: None,
            kind: kind.to_owned(),
            presence_only: true,
            address: Some(address.to_ascii_uppercase()),
            tx_power_1m: None,
            path_loss_n: None,
            last_seen_unix: None,
        }
    }

    pub fn with_kind(mut self, kind: &str) -> Self {
        self.kind = kind.to_owned();
        self
    }

    pub fn secret(&self) -> Option<Secret> {
        let b = hex_decode(&self.secret_hex)?;
        Some(Secret::new(<[u8; 32]>::try_from(b.as_slice()).ok()?))
    }
}

#[derive(Debug, Default, Serialize, Deserialize)]
struct File {
    devices: Vec<Device>,
}

#[derive(Debug)]
pub struct Store {
    path: Option<PathBuf>,
    devices: Vec<Device>,
}

impl Store {
    #[cfg(test)]
    pub fn in_memory() -> Self {
        Self {
            path: None,
            devices: Vec::new(),
        }
    }

    pub fn load(path: &Path) -> anyhow::Result<Self> {
        let devices = match std::fs::read_to_string(path) {
            Ok(t) => serde_json::from_str::<File>(&t)?.devices,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Vec::new(),
            Err(e) => return Err(e.into()),
        };
        Ok(Self {
            path: Some(path.to_path_buf()),
            devices,
        })
    }

    pub fn save(&self) -> anyhow::Result<()> {
        let Some(path) = &self.path else {
            return Ok(());
        };
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let tmp = path.with_extension("json.tmp");
        let json = serde_json::to_string_pretty(&File {
            devices: self.devices.clone(),
        })?;
        write_private(&tmp, json.as_bytes())?;
        std::fs::rename(tmp, path)?;
        Ok(())
    }

    pub fn list(&self) -> &[Device] {
        &self.devices
    }

    pub fn get(&self, id: u16) -> Option<&Device> {
        self.devices.iter().find(|d| d.device_id == id)
    }

    pub fn get_mut(&mut self, id: u16) -> Option<&mut Device> {
        self.devices.iter_mut().find(|d| d.device_id == id)
    }

    pub fn add(&mut self, d: Device) {
        self.devices.retain(|x| x.device_id != d.device_id);
        self.devices.push(d);
    }

    pub fn remove(&mut self, id: u16) -> bool {
        let before = self.devices.len();
        self.devices.retain(|d| d.device_id != id);
        self.devices.len() != before
    }
}

#[cfg(unix)]
fn write_private(path: &Path, data: &[u8]) -> std::io::Result<()> {
    use std::io::Write;
    use std::os::unix::fs::OpenOptionsExt;
    let mut f = std::fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(path)?;
    f.write_all(data)
}

#[cfg(not(unix))]
fn write_private(path: &Path, data: &[u8]) -> std::io::Result<()> {
    std::fs::write(path, data)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dev(id: u16) -> Device {
        Device::new(id, "Phone".into(), &Secret::new([id as u8; 32]), 100, None)
    }

    #[test]
    fn roundtrip_and_secret_recovery() {
        let dir = std::env::temp_dir().join(format!("stepaway-store-{}", std::process::id()));
        let path = dir.join("devices.json");
        let mut s = Store::load(&path).unwrap();
        s.add(dev(7));
        s.get_mut(7).unwrap().last_counter = Some(42);
        s.save().unwrap();
        let s2 = Store::load(&path).unwrap();
        let d = s2.get(7).unwrap();
        assert_eq!(d.last_counter, Some(42));
        assert_eq!(d.secret().unwrap().as_bytes(), &[7u8; 32]);
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(
                std::fs::metadata(&path).unwrap().permissions().mode() & 0o777,
                0o600
            );
        }
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn add_replaces_and_remove_works() {
        let mut s = Store::in_memory();
        s.add(dev(1));
        s.add(dev(1));
        assert_eq!(s.list().len(), 1);
        assert!(s.remove(1));
        assert!(!s.remove(1));
    }

    #[test]
    fn old_files_without_the_new_fields_still_load_as_phones() {
        let dir = std::env::temp_dir().join(format!("stepaway-store-old-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("devices.json");
        std::fs::write(&path, r#"{"devices":[{"device_id":5,"name":"Old","secret_hex":"00","paired_at":1,"last_counter":null}]}"#).unwrap();
        let s = Store::load(&path).unwrap();
        let d = s.get(5).unwrap();
        assert_eq!(
            (d.kind.as_str(), d.presence_only, d.address.is_none()),
            ("phone", false, true)
        );
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn presence_only_devices_have_no_secret_and_validate_input() {
        let d = Device::presence_only(9, "Band".into(), "watch", "aa:bb:cc:dd:ee:ff", 1);
        assert!(d.secret().is_none());
        assert_eq!(d.address.as_deref(), Some("AA:BB:CC:DD:EE:FF"));
        assert!(valid_kind("watch") && !valid_kind("toaster"));
        assert!(
            valid_address("AA:BB:CC:DD:EE:FF")
                && !valid_address("AA:BB:CC")
                && !valid_address("GG:BB:CC:DD:EE:FF")
                && !valid_address("")
        );
    }

    #[test]
    fn debug_never_prints_secret() {
        let d = dev(9);
        assert!(!format!("{d:?}").contains("0909"));
    }
}
