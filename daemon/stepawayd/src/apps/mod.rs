//! Applications that can be closed when StepAway locks the computer, and reopened afterwards.
//!
//! Linux lists the installed `.desktop` applications and finds running ones by program name;
//! Windows lists the applications that currently have a window. An application is identified by
//! `id`: the desktop-file name on Linux (`firefox.desktop`) and the full path of the program on
//! Windows. IDs are validated, so a setting can never become an arbitrary command.

use std::future::Future;

use serde::{Deserialize, Serialize};

#[cfg(target_os = "linux")]
pub mod linux;
#[cfg(windows)]
pub mod windows;

/// One entry on the user's "close on lock" list.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AppEntry {
    pub id: String,
    pub name: String,
}

/// One application offered in the picker.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct AppInfo {
    pub id: String,
    pub name: String,
    pub running: bool,
}

/// Program names that must never be closed: the desktop session, system services and StepAway.
const PROTECTED: &[&str] = &[
    "gnome-shell",
    "org.gnome.shell",
    "org.gnome.session",
    "org.kde.plasmashell",
    "org.kde.kwin",
    "gnome-session",
    "gnome-keyring",
    "plasmashell",
    "kwin",
    "ksmserver",
    "xdg-desktop-portal",
    "dbus",
    "systemd",
    "xorg",
    "xwayland",
    "pipewire",
    "wireplumber",
    "pulseaudio",
    "gdm",
    "sddm",
    "lightdm",
    "login",
    "polkit",
    "stepaway",
    "stepawayd",
    "explorer",
    "winlogon",
    "csrss",
    "dwm",
    "svchost",
    "lsass",
    "services",
    "sihost",
    "ctfmon",
    "searchhost",
    "startmenuexperiencehost",
    "shellexperiencehost",
    "textinputhost",
    "fontdrvhost",
    "wininit",
];

/// True if `name` (a program or file stem) is something we refuse to close.
pub fn is_protected(name: &str) -> bool {
    let lower = name.to_ascii_lowercase();
    let stem = lower
        .strip_suffix(".exe")
        .or_else(|| lower.strip_suffix(".desktop"))
        .unwrap_or(&lower);
    PROTECTED.iter().any(|p| {
        stem == *p
            || ["-", ".", "_"]
                .iter()
                .any(|sep| stem.starts_with(&format!("{p}{sep}")))
    })
}

/// A Linux desktop-file id such as `firefox.desktop` or `org.mozilla.firefox.desktop`.
pub fn valid_desktop_id(id: &str) -> bool {
    let Some(stem) = id.strip_suffix(".desktop") else {
        return false;
    };
    !stem.is_empty()
        && id.len() <= 160
        && !stem.starts_with(['-', '.'])
        && stem
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.' | '+'))
        && !is_protected(stem)
}

/// A Windows program path such as `C:\Program Files\Spotify\Spotify.exe`.
pub fn valid_windows_exe(id: &str) -> bool {
    let b = id.as_bytes();
    let drive = b.len() > 3
        && b[0].is_ascii_alphabetic()
        && b[1] == b':'
        && (b[2] == b'\\' || b[2] == b'/');
    if !drive || id.len() > 260 || !id.to_ascii_lowercase().ends_with(".exe") {
        return false;
    }
    if id
        .chars()
        .any(|c| c.is_control() || matches!(c, '<' | '>' | '"' | '|' | '?' | '*'))
    {
        return false;
    }
    if id.split(['\\', '/']).any(|part| part == "..") {
        return false;
    }
    let file = id.rsplit(['\\', '/']).next().unwrap_or("");
    !is_protected(file)
}

/// Is `id` acceptable on this platform?
pub fn valid_app_id(id: &str) -> bool {
    if cfg!(windows) {
        valid_windows_exe(id)
    } else {
        valid_desktop_id(id)
    }
}

/// List, close and reopen applications.
pub trait AppControl: Send + Sync {
    /// Applications to offer in the picker (running ones are flagged).
    fn list(&self) -> impl Future<Output = Vec<AppInfo>> + Send;
    fn is_running(&self, id: &str) -> impl Future<Output = bool> + Send;
    /// Ask the application to quit.
    fn close(&self, id: &str) -> impl Future<Output = Result<(), String>> + Send;
    fn launch(&self, id: &str) -> impl Future<Output = Result<(), String>> + Send;
}

/// For platforms without app control: nothing to list.
#[derive(Debug, Default, Clone, Copy)]
#[cfg_attr(any(target_os = "linux", windows), allow(dead_code))]
pub struct NoApps;

impl AppControl for NoApps {
    async fn list(&self) -> Vec<AppInfo> {
        Vec::new()
    }
    async fn is_running(&self, _id: &str) -> bool {
        false
    }
    async fn close(&self, _id: &str) -> Result<(), String> {
        Err("application control is not supported on this platform".into())
    }
    async fn launch(&self, _id: &str) -> Result<(), String> {
        Err("application control is not supported on this platform".into())
    }
}

/// Recording fake for tests.
#[cfg(test)]
#[derive(Debug, Default)]
pub struct MockApps {
    inner: std::sync::Mutex<MockInner>,
}

#[cfg(test)]
#[derive(Debug, Default)]
struct MockInner {
    running: Vec<String>,
    log: Vec<String>,
    fail_close: bool,
}

#[cfg(test)]
impl MockApps {
    pub fn with_running(ids: &[&str]) -> Self {
        let inner = MockInner {
            running: ids.iter().map(|i| (*i).to_owned()).collect(),
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
    pub fn running(&self) -> Vec<String> {
        self.lock().running.clone()
    }
    pub fn set_fail_close(&self, f: bool) {
        self.lock().fail_close = f;
    }
}

#[cfg(test)]
impl AppControl for MockApps {
    async fn list(&self) -> Vec<AppInfo> {
        self.lock()
            .running
            .iter()
            .map(|id| AppInfo {
                id: id.clone(),
                name: id.clone(),
                running: true,
            })
            .collect()
    }
    async fn is_running(&self, id: &str) -> bool {
        self.lock().running.iter().any(|r| r == id)
    }
    async fn close(&self, id: &str) -> Result<(), String> {
        let mut g = self.lock();
        g.log.push(format!("close {id}"));
        if g.fail_close {
            return Err("mock failure".into());
        }
        g.running.retain(|r| r != id);
        Ok(())
    }
    async fn launch(&self, id: &str) -> Result<(), String> {
        let mut g = self.lock();
        g.log.push(format!("launch {id}"));
        if !g.running.iter().any(|r| r == id) {
            g.running.push(id.to_owned());
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn desktop_ids_accept_real_names_and_reject_the_rest() {
        for ok in [
            "firefox.desktop",
            "org.mozilla.firefox.desktop",
            "spotify.desktop",
            "google-chrome.desktop",
            "code_code.desktop",
            "gimp-2.10.desktop",
        ] {
            assert!(valid_desktop_id(ok), "{ok}");
        }
        for bad in [
            "",
            ".desktop",
            "firefox",
            "-x.desktop",
            "a b.desktop",
            "a;b.desktop",
            "$(x).desktop",
            "../x.desktop",
            "a/b.desktop",
            "a\nb.desktop",
            "firefox.desktop.sh",
            "x.service",
        ] {
            assert!(!valid_desktop_id(bad), "{bad:?}");
        }
        assert!(!valid_desktop_id(&format!("{}.desktop", "a".repeat(200))));
    }

    #[test]
    fn session_critical_programs_are_refused() {
        for bad in [
            "gnome-shell.desktop",
            "org.gnome.Shell.desktop",
            "plasmashell.desktop",
            "dbus.desktop",
            "stepaway.desktop",
            "stepawayd.desktop",
        ] {
            assert!(!valid_desktop_id(bad) || is_protected(bad), "{bad}");
        }
        assert!(
            is_protected("explorer.exe")
                && is_protected("Explorer.EXE")
                && is_protected("svchost.exe")
                && is_protected("gnome-shell")
        );
        assert!(
            !is_protected("spotify.desktop")
                && !is_protected("firefox")
                && !is_protected("code.exe")
        );
    }

    #[test]
    fn windows_paths_are_checked() {
        for ok in [
            r"C:\Program Files\Spotify\Spotify.exe",
            r"D:\Apps\foo.exe",
            "C:/Users/me/AppData/Local/app/app.exe",
        ] {
            assert!(valid_windows_exe(ok), "{ok}");
        }
        for bad in [
            "",
            "spotify.exe",
            r"\\server\share\x.exe",
            r"C:\x.bat",
            r"C:\a\..\b.exe",
            r"C:\Windows\explorer.exe",
            "C:\\a\"b.exe",
            "C:\\a|b.exe",
            "C:\\a\nb.exe",
            r"C:\Windows\System32\svchost.exe",
            r"C:\x\stepaway_desktop.exe",
        ] {
            assert!(!valid_windows_exe(bad), "{bad:?}");
        }
    }
}
