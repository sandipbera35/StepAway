//! Platform lock/unlock backends behind a trait, so logic can be tested with a mock.

use std::future::Future;

pub mod beacon;
pub mod media;
pub mod mock;

#[cfg(target_os = "linux")]
pub mod logind;

#[cfg(windows)]
pub mod windows;

#[derive(Debug, thiserror::Error)]
pub enum OsError {
    #[error("backend unavailable: {0}")]
    Unavailable(String),
    #[error("operation failed: {0}")]
    Failed(String),
}

/// Lock/unlock the current user's session.
///
/// Any error must be treated by callers as "stay as is" (never as "unlock").
pub trait LockBackend: Send + Sync {
    fn lock(&self) -> impl Future<Output = Result<(), OsError>> + Send;
    fn unlock(&self) -> impl Future<Output = Result<(), OsError>> + Send;
    fn is_locked(&self) -> impl Future<Output = Result<bool, OsError>> + Send;
}
