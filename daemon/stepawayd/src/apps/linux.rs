//! Linux: installed applications come from `.desktop` files; running ones are found by program
//! name in `/proc`. Closing sends SIGTERM (the application can still shut down cleanly).

use std::collections::HashSet;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};

use super::{is_protected, valid_desktop_id, AppControl, AppInfo};

/// A parsed `.desktop` application.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DesktopApp {
    pub id: String,
    pub name: String,
    pub argv: Vec<String>,
    /// Program names (lowercase) used to recognise its processes.
    pub keys: Vec<String>,
    /// Flatpak application id, if it is a Flatpak.
    pub flatpak: Option<String>,
}

/// Program names too generic to identify an application by.
const GENERIC: &[&str] = &[
    "sh",
    "bash",
    "dash",
    "zsh",
    "env",
    "python",
    "python3",
    "java",
    "node",
    "electron",
    "perl",
    "ruby",
    "flatpak",
    "snap",
    "gtk-launch",
    "xdg-open",
];

/// Split an `Exec=` line following the Desktop Entry quoting rules and drop field codes (`%U`...).
pub fn exec_argv(exec: &str) -> Vec<String> {
    let mut args = Vec::new();
    let mut cur = String::new();
    let mut in_quotes = false;
    let mut have = false;
    let mut chars = exec.chars().peekable();
    while let Some(c) = chars.next() {
        match c {
            '"' => {
                in_quotes = !in_quotes;
                have = true;
            }
            '\\' if in_quotes => {
                if let Some(n) = chars.next() {
                    cur.push(n);
                }
            }
            c if c.is_whitespace() && !in_quotes => {
                if have {
                    args.push(std::mem::take(&mut cur));
                    have = false;
                }
            }
            c => {
                cur.push(c);
                have = true;
            }
        }
    }
    if have {
        args.push(cur);
    }
    args.retain(|a| !(a.len() == 2 && a.starts_with('%')) && a != "@@" && a != "@@u" && a != "@@U");
    args
}

fn base(path: &str) -> String {
    Path::new(path)
        .file_name()
        .map(|f| f.to_string_lossy().to_ascii_lowercase())
        .unwrap_or_default()
}

/// Parse one desktop file; returns `None` for entries that are hidden, not applications, or unusable.
pub fn parse_desktop_entry(id: &str, text: &str) -> Option<DesktopApp> {
    let mut in_entry = false;
    let (mut name, mut exec, mut kind) = (None, None, None);
    let (mut hidden, mut flatpak) = (false, None);
    for line in text.lines() {
        let line = line.trim();
        if line.starts_with('[') {
            in_entry = line == "[Desktop Entry]";
            continue;
        }
        if !in_entry {
            continue;
        }
        let Some((k, v)) = line.split_once('=') else {
            continue;
        };
        match k.trim() {
            "Name" => name = Some(v.trim().to_owned()),
            "Exec" => exec = Some(v.trim().to_owned()),
            "Type" => kind = Some(v.trim().to_owned()),
            "NoDisplay" | "Hidden" if v.trim().eq_ignore_ascii_case("true") => hidden = true,
            "X-Flatpak" => flatpak = Some(v.trim().to_owned()),
            _ => {}
        }
    }
    if hidden || kind.as_deref() != Some("Application") || !valid_desktop_id(id) {
        return None;
    }
    let argv = exec_argv(&exec?);
    let first = argv.first()?;
    let mut keys = Vec::new();
    if base(first) == "env" {
        if let Some(prog) = argv
            .iter()
            .skip(1)
            .find(|a| !a.contains('=') && !a.starts_with('-'))
        {
            keys.push(base(prog));
        }
    } else if base(first) == "flatpak" {
        // `flatpak run [options] APP-ID`
        if let Some(app) = argv
            .iter()
            .skip(1)
            .find(|a| a.contains('.') && !a.starts_with('-') && !a.contains('='))
        {
            flatpak = flatpak.or_else(|| Some(app.clone()));
        }
    } else {
        keys.push(base(first));
    }
    let stem = id.trim_end_matches(".desktop").to_ascii_lowercase();
    keys.retain(|k| !k.is_empty() && !GENERIC.contains(&k.as_str()));
    keys.dedup();
    if keys.is_empty() && flatpak.is_none() {
        keys.push(stem.clone());
    }
    if keys.iter().any(|k| is_protected(k)) || is_protected(&stem) {
        return None;
    }
    Some(DesktopApp {
        id: id.to_owned(),
        name: name.unwrap_or_else(|| stem.clone()),
        argv,
        keys,
        flatpak,
    })
}

/// A running process, reduced to what matching needs.
#[derive(Debug, Clone)]
pub struct Proc {
    pub pid: u32,
    pub comm: String,
    pub argv0: String,
    pub cgroup: String,
    pub cmdline: String,
}

/// Does process `p` belong to `app`?
pub fn matches(app: &DesktopApp, p: &Proc) -> bool {
    if let Some(fp) = &app.flatpak {
        let marker = format!("app-flatpak-{}", fp.to_ascii_lowercase());
        if p.cgroup.to_ascii_lowercase().contains(&marker) || p.cmdline.contains(fp.as_str()) {
            return true;
        }
    }
    let comm = p.comm.to_ascii_lowercase();
    let argv0 = base(&p.argv0);
    app.keys
        .iter()
        .any(|k| *k == comm || *k == argv0 || (comm.len() == 15 && k.starts_with(&comm)))
}

fn data_dirs() -> Vec<PathBuf> {
    let home = std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_default();
    let xdg_home = std::env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or_else(|| home.join(".local/share"));
    let mut dirs = vec![
        xdg_home.join("applications"),
        xdg_home.join("flatpak/exports/share/applications"),
    ];
    let system = std::env::var("XDG_DATA_DIRS")
        .ok()
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "/usr/local/share:/usr/share".into());
    dirs.extend(system.split(':').map(|d| Path::new(d).join("applications")));
    dirs.push(PathBuf::from("/var/lib/flatpak/exports/share/applications"));
    dirs.push(PathBuf::from("/var/lib/snapd/desktop/applications"));
    dirs
}

/// All applications from the standard directories (the first definition of an id wins).
pub fn installed_apps(dirs: &[PathBuf]) -> Vec<DesktopApp> {
    let mut seen = HashSet::new();
    let mut apps = Vec::new();
    for dir in dirs {
        let Ok(rd) = std::fs::read_dir(dir) else {
            continue;
        };
        let mut files: Vec<_> = rd.filter_map(Result::ok).collect();
        files.sort_by_key(|e| e.file_name());
        for e in files {
            let id = e.file_name().to_string_lossy().into_owned();
            if !id.ends_with(".desktop") || !seen.insert(id.clone()) {
                continue;
            }
            if let Ok(text) = std::fs::read_to_string(e.path()) {
                if let Some(app) = parse_desktop_entry(&id, &text) {
                    apps.push(app);
                }
            }
        }
    }
    apps
}

fn read_procs() -> Vec<Proc> {
    let my_uid = std::fs::metadata("/proc/self")
        .map(|m| m.uid())
        .unwrap_or(u32::MAX);
    let me = std::process::id();
    let Ok(rd) = std::fs::read_dir("/proc") else {
        return Vec::new();
    };
    let mut out = Vec::new();
    for e in rd.filter_map(Result::ok) {
        let Some(pid) = e.file_name().to_str().and_then(|s| s.parse::<u32>().ok()) else {
            continue;
        };
        if pid == me || e.metadata().map(|m| m.uid()).unwrap_or(u32::MAX) != my_uid {
            continue;
        }
        let p = e.path();
        let comm = std::fs::read_to_string(p.join("comm"))
            .unwrap_or_default()
            .trim()
            .to_owned();
        let raw = std::fs::read(p.join("cmdline")).unwrap_or_default();
        let cmdline = String::from_utf8_lossy(&raw).replace('\0', " ");
        let argv0 =
            String::from_utf8_lossy(raw.split(|b| *b == 0).next().unwrap_or(&[])).into_owned();
        let cgroup = std::fs::read_to_string(p.join("cgroup")).unwrap_or_default();
        out.push(Proc {
            pid,
            comm,
            argv0,
            cgroup,
            cmdline,
        });
    }
    out
}

fn find_app(id: &str) -> Option<DesktopApp> {
    if !valid_desktop_id(id) {
        return None;
    }
    installed_apps(&data_dirs())
        .into_iter()
        .find(|a| a.id == id)
}

#[derive(Debug, Default, Clone, Copy)]
pub struct XdgApps;

impl AppControl for XdgApps {
    async fn list(&self) -> Vec<AppInfo> {
        let procs = read_procs();
        let mut apps: Vec<AppInfo> = installed_apps(&data_dirs())
            .into_iter()
            .map(|a| AppInfo {
                running: procs.iter().any(|p| matches(&a, p)),
                id: a.id,
                name: a.name,
            })
            .collect();
        apps.sort_by(|a, b| {
            b.running
                .cmp(&a.running)
                .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
        });
        apps
    }

    async fn is_running(&self, id: &str) -> bool {
        let Some(app) = find_app(id) else {
            return false;
        };
        read_procs().iter().any(|p| matches(&app, p))
    }

    async fn close(&self, id: &str) -> Result<(), String> {
        let app = find_app(id).ok_or_else(|| format!("unknown application {id}"))?;
        let pids: Vec<String> = read_procs()
            .iter()
            .filter(|p| matches(&app, p))
            .map(|p| p.pid.to_string())
            .collect();
        if pids.is_empty() {
            return Err("not running".into());
        }
        let out = tokio::process::Command::new("kill")
            .arg("-TERM")
            .arg("--")
            .args(&pids)
            .output()
            .await
            .map_err(|e| e.to_string())?;
        // some pids may already be gone: success if at least the signal could be sent
        if out.status.success() || pids.len() > 1 {
            Ok(())
        } else {
            Err(String::from_utf8_lossy(&out.stderr).trim().to_owned())
        }
    }

    async fn launch(&self, id: &str) -> Result<(), String> {
        let app = find_app(id).ok_or_else(|| format!("unknown application {id}"))?;
        let (prog, args) = app.argv.split_first().ok_or("empty command")?;
        // detached, in its own session, so it outlives the daemon
        tokio::process::Command::new("setsid")
            .arg("-f")
            .arg(prog)
            .args(args)
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn()
            .map(|_| ())
            .map_err(|e| e.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const FIREFOX: &str = "[Desktop Entry]\nVersion=1.0\nName=Firefox\nName[de]=Feuerfuchs\nType=Application\nExec=firefox %u\nIcon=firefox\nCategories=Network;\n\n[Desktop Action new-window]\nName=New Window\nExec=firefox --new-window %u\n";

    #[test]
    fn exec_lines_are_split_like_the_spec_says() {
        assert_eq!(exec_argv("firefox %u"), ["firefox"]);
        assert_eq!(
            exec_argv("/usr/bin/env FOO=1 \"my app\" --flag %F"),
            ["/usr/bin/env", "FOO=1", "my app", "--flag"]
        );
        assert_eq!(
            exec_argv("sh -c \"echo \\\"hi\\\"\""),
            ["sh", "-c", "echo \"hi\""]
        );
        assert_eq!(
            exec_argv("flatpak run --branch=stable org.mozilla.firefox @@u %u @@"),
            ["flatpak", "run", "--branch=stable", "org.mozilla.firefox"]
        );
    }

    #[test]
    fn parses_a_normal_application_and_ignores_actions_and_translations() {
        let a = parse_desktop_entry("firefox.desktop", FIREFOX).unwrap();
        assert_eq!(
            (a.name.as_str(), a.keys.clone()),
            ("Firefox", vec!["firefox".to_string()])
        );
        assert_eq!(a.argv, ["firefox"]);
    }

    #[test]
    fn hidden_non_applications_and_protected_entries_are_dropped() {
        let hidden = FIREFOX.replace("Type=Application", "Type=Application\nNoDisplay=true");
        assert!(parse_desktop_entry("firefox.desktop", &hidden).is_none());
        let link = FIREFOX.replace("Type=Application", "Type=Link");
        assert!(parse_desktop_entry("firefox.desktop", &link).is_none());
        let shell = "[Desktop Entry]\nName=Shell\nType=Application\nExec=gnome-shell\n";
        assert!(parse_desktop_entry("org.gnome.Shell.desktop", shell).is_none());
        assert!(parse_desktop_entry("bad name.desktop", FIREFOX).is_none());
    }

    #[test]
    fn wrapper_commands_use_the_real_program_name() {
        let t = "[Desktop Entry]\nName=App\nType=Application\nExec=env GDK_BACKEND=x11 /opt/app/bin/myapp %U\n";
        assert_eq!(
            parse_desktop_entry("app.desktop", t).unwrap().keys,
            ["myapp"]
        );
        let sh = "[Desktop Entry]\nName=App\nType=Application\nExec=sh -c something\n";
        assert_eq!(
            parse_desktop_entry("weird.desktop", sh).unwrap().keys,
            ["weird"],
            "a generic launcher falls back to the file name"
        );
        let fp = "[Desktop Entry]\nName=Spotify\nType=Application\nExec=flatpak run --branch=stable --arch=x86_64 com.spotify.Client\nX-Flatpak=com.spotify.Client\n";
        let a = parse_desktop_entry("com.spotify.Client.desktop", fp).unwrap();
        assert_eq!(a.flatpak.as_deref(), Some("com.spotify.Client"));
    }

    fn proc(comm: &str, argv0: &str, cgroup: &str, cmdline: &str) -> Proc {
        Proc {
            pid: 1,
            comm: comm.into(),
            argv0: argv0.into(),
            cgroup: cgroup.into(),
            cmdline: cmdline.into(),
        }
    }

    #[test]
    fn processes_are_matched_by_program_name_or_flatpak_id() {
        let ff = parse_desktop_entry("firefox.desktop", FIREFOX).unwrap();
        assert!(matches(
            &ff,
            &proc("firefox", "/usr/lib/firefox/firefox", "", "")
        ));
        assert!(
            matches(
                &ff,
                &proc("firefox-bin", "/usr/lib64/firefox/firefox", "", "")
            ),
            "argv0 base name also counts"
        );
        assert!(!matches(
            &ff,
            &proc("firefox-esr", "/usr/bin/other", "", "")
        ));
        assert!(
            !matches(&ff, &proc("bash", "bash", "", "bash -c firefox")),
            "a shell that merely mentions the name is not the app"
        );
        let fp = "[Desktop Entry]\nName=Spotify\nType=Application\nExec=flatpak run com.spotify.Client\n";
        let sp = parse_desktop_entry("com.spotify.Client.desktop", fp).unwrap();
        assert!(matches(
            &sp,
            &proc(
                "spotify",
                "/app/extra/spotify",
                "0::/user.slice/app-flatpak-com.spotify.Client-1234.scope",
                ""
            )
        ));
        assert!(!matches(
            &sp,
            &proc(
                "spotify",
                "/usr/bin/spotify",
                "0::/user.slice/other.scope",
                ""
            )
        ));
    }

    #[test]
    fn scans_a_directory_and_prefers_the_first_definition() {
        let dir = std::env::temp_dir().join(format!("sa-apps-{}", std::process::id()));
        let (a, b) = (dir.join("a"), dir.join("b"));
        std::fs::create_dir_all(&a).unwrap();
        std::fs::create_dir_all(&b).unwrap();
        std::fs::write(a.join("firefox.desktop"), FIREFOX).unwrap();
        std::fs::write(
            b.join("firefox.desktop"),
            FIREFOX.replace("Firefox", "Other"),
        )
        .unwrap();
        std::fs::write(b.join("notes.txt"), "x").unwrap();
        let apps = installed_apps(&[a, b, dir.join("missing")]);
        assert_eq!(apps.len(), 1);
        assert_eq!(apps[0].name, "Firefox");
        let _ = std::fs::remove_dir_all(dir);
    }
}
