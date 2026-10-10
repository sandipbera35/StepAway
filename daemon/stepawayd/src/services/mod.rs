//! Background services that can be stopped when StepAway locks the computer: systemd *user*
//! units on Linux, Windows services (Service Control Manager) on Windows. Names are validated so
//! a setting can never turn into a command-line option or stop something the system needs.

use std::future::Future;

use serde::Serialize;

#[cfg(windows)]
pub mod windows;

/// One service offered in the picker.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct ServiceInfo {
    /// What is stored and passed to the platform (unit name / service name).
    pub id: String,
    /// What the user sees.
    pub name: String,
}

/// Linux units the session cannot work without: refused even if the user lists them.
const PROTECTED_UNIT_PREFIXES: &[&str] = &[
    "dbus",
    "systemd",
    "gnome-shell",
    "gnome-session",
    "plasma",
    "kwin",
    "org.gnome.Shell",
    "org.kde",
    "gdm",
    "sddm",
    "lightdm",
    "graphical-session",
    "xdg-desktop-portal",
    "pipewire",
    "wireplumber",
    "stepawayd",
];

/// Windows services that must keep running (stopping them breaks or hangs the system).
const PROTECTED_WIN_SERVICES: &[&str] = &[
    "rpcss",
    "rpceptmapper",
    "dcomlaunch",
    "lsm",
    "samss",
    "winmgmt",
    "eventlog",
    "bfe",
    "mpssvc",
    "cryptsvc",
    "dhcp",
    "dnscache",
    "nsi",
    "plugplay",
    "power",
    "profsvc",
    "usermanager",
    "staterepository",
    "trustedinstaller",
    "windefend",
    "wuauserv",
    "themes",
    "audiosrv",
    "audioendpointbuilder",
    "lanmanserver",
    "lanmanworkstation",
    "netlogon",
    "schedule",
    "sens",
    "shellhwdetection",
    "wlansvc",
    "netprofm",
    "nlasvc",
    "termservice",
    "wpnservice",
    "gpsvc",
    "sysmain",
    "token_broker",
    "tokenbroker",
    "brokerinfrastructure",
    "coremessagingregistrar",
    "keyiso",
    "lsass",
    "wininit",
    "stepaway",
    "stepawayd",
];

/// Is `name` an acceptable systemd user unit (a `.service` unit with safe characters)?
pub fn valid_unit(name: &str) -> bool {
    let Some(stem) = name.strip_suffix(".service") else {
        return false;
    };
    if stem.is_empty() || name.len() > 128 || stem.starts_with('-') || stem.starts_with('.') {
        return false;
    }
    if !stem
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.' | ':' | '@' | '\\'))
    {
        return false;
    }
    let lower = stem.to_ascii_lowercase();
    !PROTECTED_UNIT_PREFIXES
        .iter()
        .any(|p| lower.starts_with(&p.to_ascii_lowercase()))
}

/// Is `name` an acceptable Windows service name?
pub fn valid_win_service(name: &str) -> bool {
    if name.is_empty() || name.len() > 256 || name.starts_with(['-', ' ']) || name.ends_with(' ') {
        return false;
    }
    if !name
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '-' | '.' | '$' | ' ' | '@'))
    {
        return false;
    }
    let lower = name.to_ascii_lowercase();
    // per-user instances look like "CDPUserSvc_1a2b3": judge them by their base name
    let base = lower.split('_').next().unwrap_or(&lower);
    !PROTECTED_WIN_SERVICES
        .iter()
        .any(|p| lower == *p || base == *p)
}

/// Is `name` acceptable on this platform?
pub fn valid_service(name: &str) -> bool {
    if cfg!(windows) {
        valid_win_service(name)
    } else {
        valid_unit(name)
    }
}

/// Start/stop services and list the ones that are running.
pub trait ServiceControl: Send + Sync {
    fn is_active(&self, unit: &str) -> impl Future<Output = bool> + Send;
    fn stop(&self, unit: &str) -> impl Future<Output = Result<(), String>> + Send;
    fn start(&self, unit: &str) -> impl Future<Output = Result<(), String>> + Send;
    fn list_running(&self) -> impl Future<Output = Vec<ServiceInfo>> + Send;
}

/// For platforms without a service list: nothing to stop.
#[derive(Debug, Default, Clone, Copy)]
#[cfg_attr(any(target_os = "linux", windows), allow(dead_code))]
pub struct NoServices;

impl ServiceControl for NoServices {
    async fn is_active(&self, _unit: &str) -> bool {
        false
    }
    async fn stop(&self, _unit: &str) -> Result<(), String> {
        Err("services are not supported on this platform".into())
    }
    async fn start(&self, _unit: &str) -> Result<(), String> {
        Err("services are not supported on this platform".into())
    }
    async fn list_running(&self) -> Vec<ServiceInfo> {
        Vec::new()
    }
}

#[cfg(target_os = "linux")]
#[derive(Debug, Default, Clone, Copy)]
pub struct SystemdUser;

#[cfg(target_os = "linux")]
impl SystemdUser {
    async fn systemctl(args: &[&str]) -> Result<std::process::Output, String> {
        tokio::process::Command::new("systemctl")
            .arg("--user")
            .args(args)
            .output()
            .await
            .map_err(|e| e.to_string())
    }

    /// True if `systemctl --user` works on this machine.
    pub async fn available() -> bool {
        Self::systemctl(&["--version"])
            .await
            .map(|o| o.status.success())
            .unwrap_or(false)
    }

    async fn run(verb: &str, unit: &str) -> Result<(), String> {
        if !valid_unit(unit) {
            return Err(format!("refusing to touch {unit}"));
        }
        let out = Self::systemctl(&[verb, "--", unit]).await?;
        if out.status.success() {
            Ok(())
        } else {
            Err(String::from_utf8_lossy(&out.stderr).trim().to_string())
        }
    }
}

#[cfg(target_os = "linux")]
impl ServiceControl for SystemdUser {
    async fn is_active(&self, unit: &str) -> bool {
        valid_unit(unit)
            && Self::systemctl(&["is-active", "--quiet", "--", unit])
                .await
                .map(|o| o.status.success())
                .unwrap_or(false)
    }

    async fn stop(&self, unit: &str) -> Result<(), String> {
        Self::run("stop", unit).await
    }

    async fn start(&self, unit: &str) -> Result<(), String> {
        Self::run("start", unit).await
    }

    async fn list_running(&self) -> Vec<ServiceInfo> {
        let Ok(out) = Self::systemctl(&[
            "list-units",
            "--type=service",
            "--state=running",
            "--no-legend",
            "--plain",
            "--no-pager",
        ])
        .await
        else {
            return Vec::new();
        };
        let mut units: Vec<String> = String::from_utf8_lossy(&out.stdout)
            .lines()
            .filter_map(|l| l.split_whitespace().next())
            .filter(|u| valid_unit(u))
            .map(str::to_owned)
            .collect();
        units.sort();
        units.dedup();
        units
            .into_iter()
            .map(|u| ServiceInfo {
                name: u.trim_end_matches(".service").to_owned(),
                id: u,
            })
            .collect()
    }
}

/// Recording fake for tests.
#[cfg(test)]
#[derive(Debug, Default)]
pub struct MockServices {
    inner: std::sync::Mutex<MockInner>,
}

#[cfg(test)]
#[derive(Debug, Default)]
struct MockInner {
    active: Vec<String>,
    log: Vec<String>,
    fail_stop: bool,
}

#[cfg(test)]
impl MockServices {
    pub fn with_active(units: &[&str]) -> Self {
        let inner = MockInner {
            active: units.iter().map(|u| (*u).to_owned()).collect(),
            ..MockInner::default()
        };
        Self {
            inner: std::sync::Mutex::new(inner),
        }
    }
    fn lock(&self) -> std::sync::MutexGuard<'_, MockInner> {
        self.inner.lock().unwrap_or_else(|e| e.into_inner())
    }
    pub fn log(&self) -> Vec<String> {
        self.lock().log.clone()
    }
    pub fn set_fail_stop(&self, f: bool) {
        self.lock().fail_stop = f;
    }
    pub fn active(&self) -> Vec<String> {
        self.lock().active.clone()
    }
}

#[cfg(test)]
impl ServiceControl for MockServices {
    async fn is_active(&self, unit: &str) -> bool {
        self.lock().active.iter().any(|u| u == unit)
    }
    async fn stop(&self, unit: &str) -> Result<(), String> {
        let mut g = self.lock();
        g.log.push(format!("stop {unit}"));
        if g.fail_stop {
            return Err("mock failure".into());
        }
        g.active.retain(|u| u != unit);
        Ok(())
    }
    async fn start(&self, unit: &str) -> Result<(), String> {
        let mut g = self.lock();
        g.log.push(format!("start {unit}"));
        if !g.active.iter().any(|u| u == unit) {
            g.active.push(unit.to_owned());
        }
        Ok(())
    }
    async fn list_running(&self) -> Vec<ServiceInfo> {
        self.lock()
            .active
            .iter()
            .map(|u| ServiceInfo {
                id: u.clone(),
                name: u.clone(),
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_normal_unit_names() {
        for ok in [
            "syncthing.service",
            "my-app@1.service",
            "app_name.service",
            "foo.bar.service",
            "backup:daily.service",
        ] {
            assert!(valid_unit(ok), "{ok}");
        }
    }

    #[test]
    fn rejects_options_paths_shell_and_other_unit_types() {
        for bad in [
            "",
            ".service",
            "-rf.service",
            "--user.service",
            "a b.service",
            "a;b.service",
            "$(x).service",
            "../x.service",
            "a/b.service",
            "syncthing",
            "x.timer",
            "x.target",
            "x.socket",
            "a\nb.service",
        ] {
            assert!(!valid_unit(bad), "{bad:?}");
        }
        assert!(!valid_unit(&format!("{}.service", "a".repeat(200))));
    }

    #[test]
    fn refuses_units_the_session_depends_on() {
        for bad in [
            "dbus.service",
            "dbus-broker.service",
            "gnome-shell-wayland.service",
            "pipewire.service",
            "wireplumber.service",
            "xdg-desktop-portal.service",
            "stepawayd.service",
            "systemd-tmpfiles-clean.service",
            "Plasma-kwin_wayland.service",
        ] {
            assert!(!valid_unit(bad), "{bad}");
        }
    }

    #[test]
    fn windows_service_names_are_checked() {
        for ok in [
            "Spooler",
            "Fax",
            "MySQL80",
            "Apple Mobile Device Service",
            "SomeVendor.Updater",
            "WSearch",
            "CDPUserSvc_1a2b3",
        ] {
            assert!(valid_win_service(ok), "{ok}");
        }
        for bad in [
            "", "-x", " x", "x ", "a/b", "a\\b", "a;b", "$(x)", "a\nb", "a\"b",
        ] {
            assert!(!valid_win_service(bad), "{bad:?}");
        }
        for core in [
            "RpcSs",
            "rpcss",
            "DcomLaunch",
            "LSM",
            "WinDefend",
            "EventLog",
            "BFE",
            "StepAwayD",
            "TokenBroker_1a2b3",
        ] {
            assert!(!valid_win_service(core), "{core}");
        }
        assert!(!valid_win_service(&"a".repeat(300)));
    }
}
