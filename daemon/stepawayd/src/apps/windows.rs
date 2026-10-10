//! Windows: the applications that currently show a window. Closing posts WM_CLOSE to their
//! windows (the application can still ask to save); reopening starts the program again.

use std::path::Path;

use windows_sys::Win32::Foundation::{CloseHandle, BOOL, HWND, LPARAM};
use windows_sys::Win32::System::Threading::{
    OpenProcess, QueryFullProcessImageNameW, PROCESS_QUERY_LIMITED_INFORMATION,
};
use windows_sys::Win32::UI::WindowsAndMessaging::{
    EnumWindows, GetWindow, GetWindowLongW, GetWindowTextLengthW, GetWindowThreadProcessId,
    IsWindowVisible, PostMessageW, GWL_EXSTYLE, GW_OWNER, WM_CLOSE, WS_EX_TOOLWINDOW,
};

use super::{is_protected, valid_windows_exe, AppControl, AppInfo};

/// A top-level window and the program that owns it.
struct Win {
    hwnd: HWND,
    exe: String,
}

unsafe extern "system" fn collect(hwnd: HWND, lparam: LPARAM) -> BOOL {
    // SAFETY: `lparam` is the pointer to the Vec passed to EnumWindows below.
    let list = unsafe { &mut *(lparam as *mut Vec<HWND>) };
    list.push(hwnd);
    1
}

fn exe_of(pid: u32) -> Option<String> {
    // SAFETY: plain Win32 calls; the handle is closed before returning.
    unsafe {
        let h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid);
        if h.is_null() {
            return None;
        }
        let mut buf = vec![0u16; 1024];
        let mut len = buf.len() as u32;
        let ok = QueryFullProcessImageNameW(h, 0, buf.as_mut_ptr(), &mut len);
        CloseHandle(h);
        (ok != 0).then(|| String::from_utf16_lossy(&buf[..len as usize]))
    }
}

/// Visible, titled, non-tool top-level windows with the program that owns them.
fn windows() -> Vec<Win> {
    let mut handles: Vec<HWND> = Vec::new();
    // SAFETY: the callback only pushes into the Vec, which outlives the call.
    unsafe { EnumWindows(Some(collect), (&mut handles as *mut Vec<HWND>) as LPARAM) };
    let mut out = Vec::new();
    for hwnd in handles {
        // SAFETY: `hwnd` came from EnumWindows; each call only reads window information.
        let (visible, titled, tool, owned) = unsafe {
            (
                IsWindowVisible(hwnd) != 0,
                GetWindowTextLengthW(hwnd) > 0,
                (GetWindowLongW(hwnd, GWL_EXSTYLE) as u32) & WS_EX_TOOLWINDOW != 0,
                !GetWindow(hwnd, GW_OWNER).is_null(),
            )
        };
        if !visible || !titled || tool || owned {
            continue;
        }
        let mut pid = 0u32;
        // SAFETY: `pid` is a valid out-parameter.
        unsafe { GetWindowThreadProcessId(hwnd, &mut pid) };
        if let Some(exe) = exe_of(pid) {
            if valid_windows_exe(&exe) {
                out.push(Win { hwnd, exe });
            }
        }
    }
    out
}

fn same(a: &str, b: &str) -> bool {
    a.replace('/', "\\")
        .eq_ignore_ascii_case(&b.replace('/', "\\"))
}

fn pretty_name(exe: &str) -> String {
    let stem = Path::new(exe)
        .file_stem()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default();
    let mut chars = stem.chars();
    chars
        .next()
        .map(|c| c.to_uppercase().collect::<String>() + chars.as_str())
        .unwrap_or(stem)
}

#[derive(Debug, Default, Clone, Copy)]
pub struct WindowsApps;

impl AppControl for WindowsApps {
    async fn list(&self) -> Vec<AppInfo> {
        let mut apps: Vec<AppInfo> = Vec::new();
        for w in windows() {
            if !apps.iter().any(|a| same(&a.id, &w.exe))
                && !is_protected(
                    Path::new(&w.exe)
                        .file_name()
                        .and_then(|f| f.to_str())
                        .unwrap_or(""),
                )
            {
                apps.push(AppInfo {
                    name: pretty_name(&w.exe),
                    id: w.exe,
                    running: true,
                });
            }
        }
        apps.sort_by_key(|a| a.name.to_lowercase());
        apps
    }

    async fn is_running(&self, id: &str) -> bool {
        valid_windows_exe(id) && windows().iter().any(|w| same(&w.exe, id))
    }

    async fn close(&self, id: &str) -> Result<(), String> {
        if !valid_windows_exe(id) {
            return Err(format!("refusing to close {id}"));
        }
        let targets: Vec<HWND> = windows()
            .into_iter()
            .filter(|w| same(&w.exe, id))
            .map(|w| w.hwnd)
            .collect();
        if targets.is_empty() {
            return Err("not running".into());
        }
        for hwnd in targets {
            // SAFETY: posting WM_CLOSE to a window handle is always safe; a stale handle just fails.
            unsafe { PostMessageW(hwnd, WM_CLOSE, 0, 0) };
        }
        Ok(())
    }

    async fn launch(&self, id: &str) -> Result<(), String> {
        if !valid_windows_exe(id) {
            return Err(format!("refusing to start {id}"));
        }
        std::process::Command::new(id)
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn()
            .map(|_| ())
            .map_err(|e| e.to_string())
    }
}
