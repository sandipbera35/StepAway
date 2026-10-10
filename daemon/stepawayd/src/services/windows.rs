//! Windows services through the Service Control Manager. Stopping or starting a service needs
//! the right to do so (administrator, or a service that grants it to the user); otherwise the
//! call fails and StepAway just logs it.

use std::ptr::{null, null_mut};

use windows_sys::Win32::System::Services::{
    CloseServiceHandle, ControlService, EnumServicesStatusExW, OpenSCManagerW, OpenServiceW,
    QueryServiceStatusEx, StartServiceW, ENUM_SERVICE_STATUS_PROCESSW, SC_ENUM_PROCESS_INFO,
    SC_HANDLE, SC_MANAGER_CONNECT, SC_MANAGER_ENUMERATE_SERVICE, SC_STATUS_PROCESS_INFO,
    SERVICE_ACTIVE, SERVICE_CONTROL_STOP, SERVICE_QUERY_STATUS, SERVICE_RUNNING, SERVICE_START,
    SERVICE_STATUS, SERVICE_STATUS_PROCESS, SERVICE_STOP, SERVICE_WIN32,
};

use super::{valid_win_service, ServiceControl, ServiceInfo};

fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

unsafe fn from_wide(p: *const u16) -> String {
    if p.is_null() {
        return String::new();
    }
    let mut len = 0;
    // SAFETY: the Service Control Manager returns NUL-terminated strings.
    while unsafe { *p.add(len) } != 0 {
        len += 1;
    }
    String::from_utf16_lossy(unsafe { std::slice::from_raw_parts(p, len) })
}

/// Closes a service handle when dropped.
struct Handle(SC_HANDLE);

impl Drop for Handle {
    fn drop(&mut self) {
        if !self.0.is_null() {
            // SAFETY: the handle came from OpenSCManagerW / OpenServiceW and is closed once.
            unsafe { CloseServiceHandle(self.0) };
        }
    }
}

fn open_manager(access: u32) -> Result<Handle, String> {
    // SAFETY: null machine and database names mean "local, active database".
    let h = unsafe { OpenSCManagerW(null(), null(), access) };
    if h.is_null() {
        Err("could not open the service manager".into())
    } else {
        Ok(Handle(h))
    }
}

fn open_service(name: &str, access: u32) -> Result<(Handle, Handle), String> {
    if !valid_win_service(name) {
        return Err(format!("refusing to touch {name}"));
    }
    let scm = open_manager(SC_MANAGER_CONNECT)?;
    let w = wide(name);
    // SAFETY: `w` is NUL-terminated and outlives the call.
    let h = unsafe { OpenServiceW(scm.0, w.as_ptr(), access) };
    if h.is_null() {
        return Err(format!("no permission to use the service {name}"));
    }
    Ok((scm, Handle(h)))
}

fn is_running(name: &str) -> bool {
    let Ok((_scm, svc)) = open_service(name, SERVICE_QUERY_STATUS) else {
        return false;
    };
    let mut status = SERVICE_STATUS_PROCESS {
        dwServiceType: 0,
        dwCurrentState: 0,
        dwControlsAccepted: 0,
        dwWin32ExitCode: 0,
        dwServiceSpecificExitCode: 0,
        dwCheckPoint: 0,
        dwWaitHint: 0,
        dwProcessId: 0,
        dwServiceFlags: 0,
    };
    let mut needed = 0u32;
    // SAFETY: `status` is a valid SERVICE_STATUS_PROCESS of the size passed.
    let ok = unsafe {
        QueryServiceStatusEx(
            svc.0,
            SC_STATUS_PROCESS_INFO,
            (&mut status as *mut SERVICE_STATUS_PROCESS).cast(),
            std::mem::size_of::<SERVICE_STATUS_PROCESS>() as u32,
            &mut needed,
        )
    };
    ok != 0 && status.dwCurrentState == SERVICE_RUNNING
}

fn list_running_blocking() -> Vec<ServiceInfo> {
    let Ok(scm) = open_manager(SC_MANAGER_ENUMERATE_SERVICE) else {
        return Vec::new();
    };
    let mut buf: Vec<u8> = vec![0; 64 * 1024];
    let mut resume = 0u32;
    let mut out = Vec::new();
    loop {
        let (mut needed, mut count) = (0u32, 0u32);
        // SAFETY: the buffer pointer and length describe `buf`; the out-parameters are valid.
        let ok = unsafe {
            EnumServicesStatusExW(
                scm.0,
                SC_ENUM_PROCESS_INFO,
                SERVICE_WIN32,
                SERVICE_ACTIVE,
                buf.as_mut_ptr(),
                buf.len() as u32,
                &mut needed,
                &mut count,
                &mut resume,
                null(),
            )
        };
        let entries = buf.as_ptr().cast::<ENUM_SERVICE_STATUS_PROCESSW>();
        for i in 0..count as usize {
            // SAFETY: the API wrote `count` entries at the start of the buffer.
            let e = unsafe { &*entries.add(i) };
            let id = unsafe { from_wide(e.lpServiceName) };
            if e.ServiceStatusProcess.dwCurrentState == SERVICE_RUNNING && valid_win_service(&id) {
                let display = unsafe { from_wide(e.lpDisplayName) };
                out.push(ServiceInfo {
                    name: if display.is_empty() {
                        id.clone()
                    } else {
                        display
                    },
                    id,
                });
            }
        }
        if ok != 0 || resume == 0 {
            break;
        }
        if needed as usize > buf.len() {
            buf.resize(needed as usize, 0);
        }
    }
    out.sort_by_key(|s| s.name.to_lowercase());
    out.dedup_by(|a, b| a.id == b.id);
    out
}

fn stop_blocking(name: &str) -> Result<(), String> {
    let (_scm, svc) = open_service(name, SERVICE_STOP | SERVICE_QUERY_STATUS)?;
    let mut st = SERVICE_STATUS {
        dwServiceType: 0,
        dwCurrentState: 0,
        dwControlsAccepted: 0,
        dwWin32ExitCode: 0,
        dwServiceSpecificExitCode: 0,
        dwCheckPoint: 0,
        dwWaitHint: 0,
    };
    // SAFETY: `st` is a valid SERVICE_STATUS.
    if unsafe { ControlService(svc.0, SERVICE_CONTROL_STOP, &mut st) } == 0 {
        return Err(format!(
            "could not stop {name} (administrator rights may be needed)"
        ));
    }
    Ok(())
}

fn start_blocking(name: &str) -> Result<(), String> {
    let (_scm, svc) = open_service(name, SERVICE_START | SERVICE_QUERY_STATUS)?;
    // SAFETY: no arguments are passed.
    if unsafe { StartServiceW(svc.0, 0, null_mut()) } == 0 {
        return Err(format!(
            "could not start {name} (administrator rights may be needed)"
        ));
    }
    Ok(())
}

#[derive(Debug, Default, Clone, Copy)]
pub struct WindowsServices;

impl ServiceControl for WindowsServices {
    async fn is_active(&self, unit: &str) -> bool {
        is_running(unit)
    }
    async fn stop(&self, unit: &str) -> Result<(), String> {
        stop_blocking(unit)
    }
    async fn start(&self, unit: &str) -> Result<(), String> {
        start_blocking(unit)
    }
    async fn list_running(&self) -> Vec<ServiceInfo> {
        list_running_blocking()
    }
}
