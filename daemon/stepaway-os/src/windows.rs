//! Windows backend. Locking uses `LockWorkStation`, which works from an unprivileged process.
//!
//! Unlocking cannot be done from user code on Windows; it needs the credential provider
//! (docs/plan.md Phase 7). Until then `unlock` always fails, which is the safe outcome.

use crate::{LockBackend, OsError};
use windows_sys::Win32::System::Shutdown::LockWorkStation;
use windows_sys::Win32::System::StationsAndDesktops::{
    CloseDesktop, OpenInputDesktop, DESKTOP_SWITCHDESKTOP,
};

#[derive(Debug, Default, Clone, Copy)]
pub struct WindowsBackend;

impl WindowsBackend {
    pub fn new() -> Self {
        Self
    }
}

impl LockBackend for WindowsBackend {
    async fn lock(&self) -> Result<(), OsError> {
        // SAFETY: LockWorkStation takes no arguments and has no memory-safety preconditions.
        let ok = unsafe { LockWorkStation() };
        if ok != 0 {
            Ok(())
        } else {
            Err(OsError::Failed("LockWorkStation failed".into()))
        }
    }

    async fn unlock(&self) -> Result<(), OsError> {
        Err(OsError::Unavailable(
            "unlock is not supported without the credential provider".into(),
        ))
    }

    async fn is_locked(&self) -> Result<bool, OsError> {
        // While the lock screen (secure desktop) is active, an ordinary process cannot open the
        // input desktop for switching. Any failure is conservatively reported as "locked".
        // SAFETY: plain Win32 calls; the handle is closed right after use.
        unsafe {
            let h = OpenInputDesktop(0, 0, DESKTOP_SWITCHDESKTOP);
            if h.is_null() {
                return Ok(true);
            }
            CloseDesktop(h);
        }
        Ok(false)
    }
}
