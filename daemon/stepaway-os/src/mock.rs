//! In-memory backend for tests; records calls and can be told to fail.

use crate::{LockBackend, OsError};
use std::sync::Mutex;

#[derive(Debug, Default)]
struct Inner {
    locked: bool,
    fail: bool,
    calls: Vec<&'static str>,
}

#[derive(Debug, Default)]
pub struct MockBackend(Mutex<Inner>);

impl MockBackend {
    pub fn new() -> Self {
        Self::default()
    }

    fn with<T>(&self, f: impl FnOnce(&mut Inner) -> T) -> T {
        // A poisoned mutex only means another test thread panicked; the data is still usable.
        let mut g = self.0.lock().unwrap_or_else(|e| e.into_inner());
        f(&mut g)
    }

    pub fn set_fail(&self, fail: bool) {
        self.with(|i| i.fail = fail);
    }

    pub fn calls(&self) -> Vec<&'static str> {
        self.with(|i| i.calls.clone())
    }

    fn act(&self, name: &'static str, locked: Option<bool>) -> Result<(), OsError> {
        self.with(|i| {
            i.calls.push(name);
            if i.fail {
                return Err(OsError::Failed("mock failure".into()));
            }
            if let Some(l) = locked {
                i.locked = l;
            }
            Ok(())
        })
    }
}

impl LockBackend for MockBackend {
    async fn lock(&self) -> Result<(), OsError> {
        self.act("lock", Some(true))
    }
    async fn unlock(&self) -> Result<(), OsError> {
        self.act("unlock", Some(false))
    }
    async fn is_locked(&self) -> Result<bool, OsError> {
        self.act("is_locked", None)?;
        Ok(self.with(|i| i.locked))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn lock_unlock_roundtrip() {
        let b = MockBackend::new();
        assert!(!b.is_locked().await.unwrap());
        b.lock().await.unwrap();
        assert!(b.is_locked().await.unwrap());
        b.unlock().await.unwrap();
        assert!(!b.is_locked().await.unwrap());
        assert_eq!(
            b.calls(),
            ["is_locked", "lock", "is_locked", "unlock", "is_locked"]
        );
    }

    #[tokio::test]
    async fn failure_leaves_state_unchanged() {
        let b = MockBackend::new();
        b.lock().await.unwrap();
        b.set_fail(true);
        assert!(b.unlock().await.is_err());
        b.set_fail(false);
        assert!(b.is_locked().await.unwrap());
    }
}
