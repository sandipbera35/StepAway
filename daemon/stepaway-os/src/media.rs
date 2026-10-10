//! Pausing and resuming media players (music, video) of the current user.
//!
//! Linux uses MPRIS on the session bus (Spotify, VLC, Firefox, Chrome, mpv, ... all expose it);
//! Windows uses the system media transport controls.

use std::future::Future;

use crate::OsError;

/// Pause everything that is playing, and later resume exactly what was paused.
pub trait MediaControl: Send + Sync {
    /// Pause every player that is currently playing; returns identifiers of the players paused.
    fn pause_playing(&self) -> impl Future<Output = Result<Vec<String>, OsError>> + Send;
    /// Resume the given players (identifiers returned by `pause_playing`). Players that have
    /// gone away are ignored.
    fn resume(&self, players: &[String]) -> impl Future<Output = Result<(), OsError>> + Send;
}

/// Used when the platform offers no media control: does nothing.
#[derive(Debug, Default, Clone, Copy)]
pub struct NullMedia;

impl MediaControl for NullMedia {
    async fn pause_playing(&self) -> Result<Vec<String>, OsError> {
        Ok(Vec::new())
    }
    async fn resume(&self, _players: &[String]) -> Result<(), OsError> {
        Ok(())
    }
}

/// In-memory players for tests.
#[derive(Debug, Default)]
pub struct MockMedia {
    inner: std::sync::Mutex<MockMediaInner>,
}

#[derive(Debug, Default)]
struct MockMediaInner {
    /// (name, playing)
    players: Vec<(String, bool)>,
    fail: bool,
}

impl MockMedia {
    pub fn with_players(players: &[(&str, bool)]) -> Self {
        let inner = MockMediaInner {
            players: players.iter().map(|(n, p)| ((*n).to_owned(), *p)).collect(),
            fail: false,
        };
        Self {
            inner: std::sync::Mutex::new(inner),
        }
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, MockMediaInner> {
        self.inner.lock().unwrap_or_else(|e| e.into_inner())
    }

    pub fn set_fail(&self, fail: bool) {
        self.lock().fail = fail;
    }

    pub fn is_playing(&self, name: &str) -> bool {
        self.lock().players.iter().any(|(n, p)| n == name && *p)
    }
}

impl MediaControl for MockMedia {
    async fn pause_playing(&self) -> Result<Vec<String>, OsError> {
        let mut g = self.lock();
        if g.fail {
            return Err(OsError::Failed("mock failure".into()));
        }
        let mut paused = Vec::new();
        for (name, playing) in g.players.iter_mut() {
            if *playing {
                *playing = false;
                paused.push(name.clone());
            }
        }
        Ok(paused)
    }

    async fn resume(&self, players: &[String]) -> Result<(), OsError> {
        let mut g = self.lock();
        if g.fail {
            return Err(OsError::Failed("mock failure".into()));
        }
        for (name, playing) in g.players.iter_mut() {
            if players.contains(name) {
                *playing = true;
            }
        }
        Ok(())
    }
}

#[cfg(target_os = "linux")]
pub use mpris::MprisMedia;

#[cfg(target_os = "linux")]
mod mpris {
    use super::{MediaControl, OsError};
    use zbus::Connection;

    const PREFIX: &str = "org.mpris.MediaPlayer2.";
    const PATH: &str = "/org/mpris/MediaPlayer2";
    const PLAYER: &str = "org.mpris.MediaPlayer2.Player";

    #[derive(Debug, Clone)]
    pub struct MprisMedia {
        conn: Connection,
    }

    impl MprisMedia {
        pub async fn connect() -> Result<Self, OsError> {
            let conn = Connection::session()
                .await
                .map_err(|e| OsError::Unavailable(e.to_string()))?;
            Ok(Self { conn })
        }

        /// Names of the media players currently on the session bus (diagnostics).
        pub async fn list_players(&self) -> Result<Vec<String>, OsError> {
            self.players().await
        }

        async fn players(&self) -> Result<Vec<String>, OsError> {
            let reply = self
                .conn
                .call_method(
                    Some("org.freedesktop.DBus"),
                    "/org/freedesktop/DBus",
                    Some("org.freedesktop.DBus"),
                    "ListNames",
                    &(),
                )
                .await
                .map_err(|e| OsError::Failed(e.to_string()))?;
            let names: Vec<String> = reply
                .body()
                .deserialize()
                .map_err(|e| OsError::Failed(e.to_string()))?;
            Ok(names
                .into_iter()
                .filter(|n| n.starts_with(PREFIX))
                .collect())
        }

        async fn status(&self, name: &str) -> Option<String> {
            let reply = self
                .conn
                .call_method(
                    Some(name),
                    PATH,
                    Some("org.freedesktop.DBus.Properties"),
                    "Get",
                    &(PLAYER, "PlaybackStatus"),
                )
                .await
                .ok()?;
            let v: zbus::zvariant::OwnedValue = reply.body().deserialize().ok()?;
            String::try_from(v).ok()
        }

        async fn call(&self, name: &str, method: &str) -> Result<(), OsError> {
            self.conn
                .call_method(Some(name), PATH, Some(PLAYER), method, &())
                .await
                .map(|_| ())
                .map_err(|e| OsError::Failed(e.to_string()))
        }
    }

    impl MediaControl for MprisMedia {
        async fn pause_playing(&self) -> Result<Vec<String>, OsError> {
            let mut paused = Vec::new();
            for name in self.players().await? {
                if self.status(&name).await.as_deref() == Some("Playing")
                    && self.call(&name, "Pause").await.is_ok()
                {
                    paused.push(name);
                }
            }
            Ok(paused)
        }

        async fn resume(&self, players: &[String]) -> Result<(), OsError> {
            let alive = self.players().await?;
            for name in players.iter().filter(|p| alive.contains(p)) {
                // Only resume what we paused and is still paused: never restart something the user
                // has since stopped or changed on purpose.
                if self.status(name).await.as_deref() == Some("Paused") {
                    let _ = self.call(name, "Play").await;
                }
            }
            Ok(())
        }
    }
}

#[cfg(windows)]
pub use smtc::WindowsMedia;

#[cfg(windows)]
mod smtc {
    use super::{MediaControl, OsError};
    use windows::Media::Control::{
        GlobalSystemMediaTransportControlsSessionManager as Manager,
        GlobalSystemMediaTransportControlsSessionPlaybackStatus as Status,
    };
    use windows::Win32::System::WinRT::{RoInitialize, RO_INIT_MULTITHREADED};

    #[derive(Debug, Default, Clone, Copy)]
    pub struct WindowsMedia;

    fn err(e: windows::core::Error) -> OsError {
        OsError::Failed(e.to_string())
    }

    fn manager() -> Result<Manager, OsError> {
        // Safe to call repeatedly: it fails harmlessly if the thread is already initialised.
        // SAFETY: plain COM initialisation call with no pointers.
        let _ = unsafe { RoInitialize(RO_INIT_MULTITHREADED) };
        Manager::RequestAsync().map_err(err)?.join().map_err(err)
    }

    impl MediaControl for WindowsMedia {
        async fn pause_playing(&self) -> Result<Vec<String>, OsError> {
            let mgr = manager()?;
            let mut paused = Vec::new();
            for session in mgr.GetSessions().map_err(err)? {
                let playing = session
                    .GetPlaybackInfo()
                    .and_then(|i| i.PlaybackStatus())
                    .map(|s| s == Status::Playing)
                    .unwrap_or(false);
                if playing {
                    if let Ok(op) = session.TryPauseAsync() {
                        let _ = op.join();
                    }
                    if let Ok(id) = session.SourceAppUserModelId() {
                        paused.push(id.to_string());
                    }
                }
            }
            Ok(paused)
        }

        async fn resume(&self, players: &[String]) -> Result<(), OsError> {
            let mgr = manager()?;
            for session in mgr.GetSessions().map_err(err)? {
                let Ok(id) = session.SourceAppUserModelId() else {
                    continue;
                };
                if !players.contains(&id.to_string()) {
                    continue;
                }
                let paused = session
                    .GetPlaybackInfo()
                    .and_then(|i| i.PlaybackStatus())
                    .map(|s| s == Status::Paused)
                    .unwrap_or(false);
                if paused {
                    if let Ok(op) = session.TryPlayAsync() {
                        let _ = op.join();
                    }
                }
            }
            Ok(())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn pauses_only_what_is_playing_and_resumes_exactly_that() {
        let m = MockMedia::with_players(&[("spotify", true), ("vlc", false), ("firefox", true)]);
        let paused = m.pause_playing().await.unwrap();
        assert_eq!(paused, vec!["spotify".to_string(), "firefox".to_string()]);
        assert!(!m.is_playing("spotify") && !m.is_playing("firefox"));
        m.resume(&paused).await.unwrap();
        assert!(m.is_playing("spotify") && m.is_playing("firefox"));
        assert!(
            !m.is_playing("vlc"),
            "a player that was not playing must stay stopped"
        );
    }

    #[tokio::test]
    async fn pausing_twice_does_not_report_players_again() {
        let m = MockMedia::with_players(&[("mpv", true)]);
        assert_eq!(m.pause_playing().await.unwrap().len(), 1);
        assert!(m.pause_playing().await.unwrap().is_empty());
    }

    #[tokio::test]
    async fn null_media_is_a_no_op() {
        assert!(NullMedia.pause_playing().await.unwrap().is_empty());
        NullMedia.resume(&["x".into()]).await.unwrap();
    }
}
