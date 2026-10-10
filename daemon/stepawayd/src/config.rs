//! User settings (TOML). Secrets never live here.

use std::path::Path;

use serde::{Deserialize, Serialize};
use stepaway_core::distance::DistanceModel;
use stepaway_core::state;

use crate::apps::AppEntry;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Settings {
    /// With several devices: "any" = you are near while at least one is near; "all" = only
    /// when every paired device is near.
    pub presence_rule: String,
    /// Let paired devices measure how far away this computer is (a small signed Bluetooth beacon).
    pub beacon_enabled: bool,
    pub lock_distance_m: f64,
    pub return_distance_m: f64,
    pub lock_grace_s: u64,
    pub return_grace_s: u64,
    pub lost_timeout_s: u64,
    pub unlock_enabled: bool,
    pub tx_power_1m: f64,
    pub path_loss_n: f64,
    pub desktop_name: String,
    /// Pause every playing music/video player when StepAway locks the computer.
    pub lock_pause_media: bool,
    /// Resume what was paused once the computer is unlocked.
    pub unlock_resume_media: bool,
    /// Applications to close when StepAway locks the computer.
    pub lock_close_apps: Vec<AppEntry>,
    /// Reopen the closed applications after unlock.
    pub unlock_reopen_apps: bool,
    /// Background services to stop when StepAway locks the computer (systemd user units on
    /// Linux, Windows services on Windows).
    pub lock_stop_services: Vec<String>,
    /// Start the stopped services again after unlock.
    pub unlock_start_services: bool,
    /// True once the calibration wizard has fitted the distance model to this room and phone.
    pub calibrated: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            presence_rule: "any".into(),
            beacon_enabled: true,
            lock_distance_m: 3.0,
            return_distance_m: 2.0,
            lock_grace_s: 10,
            return_grace_s: 3,
            lost_timeout_s: 10,
            unlock_enabled: false,
            tx_power_1m: -59.0,
            path_loss_n: 2.0,
            desktop_name: default_name(),
            lock_pause_media: false,
            unlock_resume_media: false,
            lock_close_apps: Vec::new(),
            unlock_reopen_apps: false,
            lock_stop_services: Vec::new(),
            unlock_start_services: false,
            calibrated: false,
        }
    }
}

fn default_name() -> String {
    std::env::var("HOSTNAME")
        .ok()
        .filter(|h| !h.is_empty())
        .or_else(|| std::env::var("COMPUTERNAME").ok())
        .unwrap_or_else(|| "StepAway PC".into())
}

impl Settings {
    pub fn validate(&self) -> Result<(), String> {
        let ok = |v: f64| v.is_finite();
        if !(ok(self.lock_distance_m)
            && ok(self.return_distance_m)
            && ok(self.tx_power_1m)
            && ok(self.path_loss_n))
        {
            return Err("values must be finite numbers".into());
        }
        if self.presence_rule != "any" && self.presence_rule != "all" {
            return Err("presence_rule must be \"any\" or \"all\"".into());
        }
        if self.lock_distance_m < 0.5 || self.lock_distance_m > 30.0 {
            return Err("lock_distance_m must be between 0.5 and 30".into());
        }
        if self.return_distance_m <= 0.0 || self.return_distance_m >= self.lock_distance_m {
            return Err(
                "return_distance_m must be positive and smaller than lock_distance_m".into(),
            );
        }
        if !(1.0..=6.0).contains(&self.path_loss_n) {
            return Err("path_loss_n must be between 1 and 6".into());
        }
        if !(-100.0..=0.0).contains(&self.tx_power_1m) {
            return Err("tx_power_1m must be between -100 and 0".into());
        }
        if self.lock_grace_s > 600
            || self.return_grace_s > 600
            || !(2..=600).contains(&self.lost_timeout_s)
        {
            return Err("grace periods must be at most 600 s and lost_timeout_s 2-600 s".into());
        }
        if self.lock_stop_services.len() > 32 {
            return Err("at most 32 services can be listed".into());
        }
        if let Some(bad) = self
            .lock_stop_services
            .iter()
            .find(|u| !crate::services::valid_service(u))
        {
            return Err(format!("not an allowed service name: {bad}"));
        }
        if self.desktop_name.len() > 64 {
            return Err("desktop_name too long".into());
        }
        Ok(())
    }

    pub fn machine_config(&self) -> state::Config {
        state::Config {
            lock_distance_m: self.lock_distance_m,
            return_distance_m: self.return_distance_m,
            lock_grace_ms: self.lock_grace_s * 1000,
            return_grace_ms: self.return_grace_s * 1000,
            lost_timeout_ms: self.lost_timeout_s * 1000,
            unlock_enabled: self.unlock_enabled,
        }
    }

    pub fn model(&self) -> DistanceModel {
        DistanceModel {
            tx_power_1m: self.tx_power_1m,
            n: self.path_loss_n,
        }
    }

    /// Merge a JSON object of changed keys, validating the result. `self` is untouched on error.
    pub fn with_patch(&self, patch: &serde_json::Value) -> Result<Settings, String> {
        let mut cur = serde_json::to_value(self).map_err(|e| e.to_string())?;
        let (Some(c), Some(p)) = (cur.as_object_mut(), patch.as_object()) else {
            return Err("config patch must be an object".into());
        };
        for (k, v) in p {
            if !c.contains_key(k) {
                return Err(format!("unknown setting: {k}"));
            }
            c.insert(k.clone(), v.clone());
        }
        let next: Settings = serde_json::from_value(cur).map_err(|e| e.to_string())?;
        next.validate()?;
        Ok(next)
    }

    /// Load settings; a missing file gives defaults, an invalid one is an error.
    pub fn load(path: &Path) -> anyhow::Result<Settings> {
        match std::fs::read_to_string(path) {
            Ok(text) => {
                let s: Settings = toml::from_str(&text)?;
                s.validate().map_err(anyhow::Error::msg)?;
                Ok(s)
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Settings::default()),
            Err(e) => Err(e.into()),
        }
    }

    pub fn save(&self, path: &Path) -> anyhow::Result<()> {
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let tmp = path.with_extension("toml.tmp");
        std::fs::write(&tmp, toml::to_string_pretty(self)?)?;
        std::fs::rename(tmp, path)?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn defaults_are_valid_and_lock_only() {
        let s = Settings::default();
        assert!(s.validate().is_ok());
        assert!(!s.unlock_enabled);
    }

    #[test]
    fn patch_merges_and_validates() {
        let s = Settings::default();
        let n = s
            .with_patch(&json!({"lock_distance_m": 5.0, "unlock_enabled": true}))
            .unwrap();
        assert_eq!(n.lock_distance_m, 5.0);
        assert!(n.unlock_enabled);
        assert!(s.with_patch(&json!({"lock_distance_m": 1.0})).is_err()); // return(2.0) >= lock(1.0)
        assert!(s.with_patch(&json!({"nope": 1})).is_err());
        assert!(s.with_patch(&json!({"lock_distance_m": "far"})).is_err());
        assert!(s.with_patch(&json!([1])).is_err());
    }

    #[test]
    fn lock_list_settings_are_validated() {
        let s = Settings::default();
        let ok = s
            .with_patch(
                &json!({"lock_pause_media": true, "lock_stop_services": ["syncthing.service"]}),
            )
            .unwrap();
        assert!(ok.lock_pause_media);
        assert_eq!(ok.lock_stop_services, vec!["syncthing.service".to_string()]);
        for bad in [
            json!(["dbus.service"]),
            json!(["x; reboot"]),
            json!(["-rf.service"]),
            json!(["a.timer"]),
            json!([1]),
        ] {
            assert!(s.with_patch(&json!({ "lock_stop_services": bad })).is_err());
        }
        let many: Vec<String> = (0..33).map(|i| format!("svc{i}.service")).collect();
        assert!(s
            .with_patch(&json!({ "lock_stop_services": many }))
            .is_err());
    }

    #[test]
    fn toml_roundtrip_and_partial_file() {
        let dir = std::env::temp_dir().join(format!("stepaway-cfg-{}", std::process::id()));
        let path = dir.join("config.toml");
        assert_eq!(Settings::load(&path).unwrap(), Settings::default());
        let s = Settings {
            lock_distance_m: 4.5,
            ..Settings::default()
        };
        s.save(&path).unwrap();
        assert_eq!(Settings::load(&path).unwrap().lock_distance_m, 4.5);
        std::fs::write(&path, "lock_distance_m = 6.0\n").unwrap();
        let p = Settings::load(&path).unwrap();
        assert_eq!(p.lock_distance_m, 6.0);
        assert_eq!(p.lock_grace_s, 10);
        std::fs::write(&path, "lock_distance_m = 100.0\n").unwrap();
        assert!(Settings::load(&path).is_err());
        let _ = std::fs::remove_dir_all(dir);
    }
}
