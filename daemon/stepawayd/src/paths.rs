//! Filesystem and IPC locations. `STEPAWAY_HOME` overrides everything (used by tests).

use std::path::PathBuf;

fn override_home() -> Option<PathBuf> {
    std::env::var_os("STEPAWAY_HOME").map(PathBuf::from)
}

fn env_path(var: &str) -> Option<PathBuf> {
    std::env::var_os(var)
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
}

pub fn config_dir() -> PathBuf {
    if let Some(h) = override_home() {
        return h.join("config");
    }
    #[cfg(windows)]
    {
        env_path("APPDATA").unwrap_or_default().join("StepAway")
    }
    #[cfg(not(windows))]
    {
        env_path("XDG_CONFIG_HOME")
            .or_else(|| env_path("HOME").map(|h| h.join(".config")))
            .unwrap_or_default()
            .join("stepaway")
    }
}

pub fn data_dir() -> PathBuf {
    if let Some(h) = override_home() {
        return h.join("data");
    }
    #[cfg(windows)]
    {
        env_path("APPDATA").unwrap_or_default().join("StepAway")
    }
    #[cfg(not(windows))]
    {
        env_path("XDG_DATA_HOME")
            .or_else(|| env_path("HOME").map(|h| h.join(".local/share")))
            .unwrap_or_default()
            .join("stepaway")
    }
}

pub fn config_file() -> PathBuf {
    config_dir().join("config.toml")
}

pub fn log_file() -> PathBuf {
    data_dir().join("stepawayd.log")
}

pub fn devices_file() -> PathBuf {
    data_dir().join("devices.json")
}

#[cfg(unix)]
pub fn socket_path() -> PathBuf {
    if let Some(h) = override_home() {
        return h.join("stepaway.sock");
    }
    env_path("XDG_RUNTIME_DIR")
        .unwrap_or_else(std::env::temp_dir)
        .join("stepaway.sock")
}

#[cfg(windows)]
pub fn pipe_name() -> String {
    let user = std::env::var("USERNAME").unwrap_or_default();
    format!(r"\\.\pipe\stepaway-{user}")
}
