//! Linux backend: `org.freedesktop.login1` on the system bus, acting on the caller's own session.
//!
//! `/org/freedesktop/login1/session/auto` is logind's alias for the calling process's session.

use crate::{LockBackend, OsError};
use zbus::Connection;

const DEST: &str = "org.freedesktop.login1";
const SESSION: &str = "/org/freedesktop/login1/session/auto";
const IFACE: &str = "org.freedesktop.login1.Session";

#[derive(Debug, Clone)]
pub struct LogindBackend {
    conn: Connection,
}

impl LogindBackend {
    pub async fn connect() -> Result<Self, OsError> {
        let conn = Connection::system()
            .await
            .map_err(|e| OsError::Unavailable(e.to_string()))?;
        Ok(Self { conn })
    }

    async fn call(&self, method: &str) -> Result<(), OsError> {
        self.conn
            .call_method(Some(DEST), SESSION, Some(IFACE), method, &())
            .await
            .map(|_| ())
            .map_err(|e| OsError::Failed(e.to_string()))
    }
}

impl LockBackend for LogindBackend {
    async fn lock(&self) -> Result<(), OsError> {
        self.call("Lock").await
    }

    async fn unlock(&self) -> Result<(), OsError> {
        self.call("Unlock").await
    }

    async fn is_locked(&self) -> Result<bool, OsError> {
        let reply = self
            .conn
            .call_method(
                Some(DEST),
                SESSION,
                Some("org.freedesktop.DBus.Properties"),
                "Get",
                &(IFACE, "LockedHint"),
            )
            .await
            .map_err(|e| OsError::Failed(e.to_string()))?;
        let v: zbus::zvariant::OwnedValue = reply
            .body()
            .deserialize()
            .map_err(|e| OsError::Failed(e.to_string()))?;
        bool::try_from(v).map_err(|e| OsError::Failed(e.to_string()))
    }
}
