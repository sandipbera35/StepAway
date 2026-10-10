//! What happens besides locking: pause music and videos, close the user's chosen applications,
//! stop their chosen services, and (optionally) bring everything back after unlock.
//!
//! Everything we change is remembered, so we only ever undo our own actions: a player that was
//! not playing stays stopped, an application or service that was not running is not started.

use std::sync::Mutex;

use stepaway_os::media::MediaControl;
use tracing::{info, warn};

use crate::apps::{valid_app_id, AppControl, AppEntry};
use crate::config::Settings;
use crate::services::{valid_service, ServiceControl};

pub struct LockActions<M, S, A> {
    media: M,
    services: S,
    apps: A,
    paused_players: Mutex<Vec<String>>,
    stopped_units: Mutex<Vec<String>>,
    closed_apps: Mutex<Vec<AppEntry>>,
}

fn guard<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

impl<M: MediaControl, S: ServiceControl, A: AppControl> LockActions<M, S, A> {
    pub fn new(media: M, services: S, apps: A) -> Self {
        Self {
            media,
            services,
            apps,
            paused_players: Mutex::new(Vec::new()),
            stopped_units: Mutex::new(Vec::new()),
            closed_apps: Mutex::new(Vec::new()),
        }
    }

    pub fn media(&self) -> &M {
        &self.media
    }

    pub fn services(&self) -> &S {
        &self.services
    }

    pub fn apps(&self) -> &A {
        &self.apps
    }

    /// Run after StepAway has locked the session.
    pub async fn on_lock(&self, s: &Settings) {
        if s.lock_pause_media {
            match self.media.pause_playing().await {
                Ok(names) if names.is_empty() => {}
                Ok(names) => {
                    info!("paused {} media player(s)", names.len());
                    let mut g = guard(&self.paused_players);
                    for n in names {
                        if !g.contains(&n) {
                            g.push(n);
                        }
                    }
                }
                Err(e) => warn!("could not pause media: {e}"),
            }
        }
        for app in &s.lock_close_apps {
            if !valid_app_id(&app.id) || !self.apps.is_running(&app.id).await {
                continue;
            }
            match self.apps.close(&app.id).await {
                Ok(()) => {
                    info!("asked {} to close", app.name);
                    let mut g = guard(&self.closed_apps);
                    if !g.iter().any(|a| a.id == app.id) {
                        g.push(app.clone());
                    }
                }
                Err(e) => warn!("could not close {}: {e}", app.name),
            }
        }
        for unit in &s.lock_stop_services {
            if !valid_service(unit) || !self.services.is_active(unit).await {
                continue;
            }
            match self.services.stop(unit).await {
                Ok(()) => {
                    info!("stopped {unit}");
                    let mut g = guard(&self.stopped_units);
                    if !g.contains(unit) {
                        g.push(unit.clone());
                    }
                }
                Err(e) => warn!("could not stop {unit}: {e}"),
            }
        }
    }

    /// Run when the session becomes unlocked (by StepAway or by the user).
    pub async fn on_unlock(&self, s: &Settings) {
        let players = std::mem::take(&mut *guard(&self.paused_players));
        if s.unlock_resume_media && !players.is_empty() {
            if let Err(e) = self.media.resume(&players).await {
                warn!("could not resume media: {e}");
            }
        }
        let apps = std::mem::take(&mut *guard(&self.closed_apps));
        if s.unlock_reopen_apps {
            for app in apps {
                // never start a second copy of something the user already reopened
                if self.apps.is_running(&app.id).await {
                    continue;
                }
                if let Err(e) = self.apps.launch(&app.id).await {
                    warn!("could not reopen {}: {e}", app.name);
                }
            }
        }
        let units = std::mem::take(&mut *guard(&self.stopped_units));
        if s.unlock_start_services {
            for unit in units {
                if let Err(e) = self.services.start(&unit).await {
                    warn!("could not start {unit}: {e}");
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::apps::MockApps;
    use crate::services::MockServices;
    use stepaway_os::media::MockMedia;

    fn entry(id: &str) -> AppEntry {
        AppEntry {
            id: id.into(),
            name: id.trim_end_matches(".desktop").into(),
        }
    }

    fn settings() -> Settings {
        Settings {
            lock_pause_media: true,
            unlock_resume_media: true,
            lock_close_apps: vec![entry("spotify.desktop"), entry("not-running.desktop")],
            unlock_reopen_apps: true,
            lock_stop_services: vec![],
            unlock_start_services: true,
            ..Settings::default()
        }
    }

    fn with_services(units: &[&str]) -> Settings {
        Settings {
            lock_stop_services: units.iter().map(|u| (*u).to_owned()).collect(),
            ..settings()
        }
    }

    type Sut = LockActions<MockMedia, MockServices, MockApps>;

    fn actions() -> Sut {
        LockActions::new(
            MockMedia::with_players(&[("spotify", true), ("vlc", false)]),
            MockServices::with_active(&["syncthing.service", "other.service"]),
            MockApps::with_running(&["spotify.desktop", "firefox.desktop"]),
        )
    }

    // ---- media ----

    #[tokio::test]
    async fn lock_pauses_media_and_unlock_resumes_exactly_that() {
        let a = actions();
        a.on_lock(&settings()).await;
        assert!(!a.media.is_playing("spotify"));
        a.on_unlock(&settings()).await;
        assert!(a.media.is_playing("spotify"));
        assert!(!a.media.is_playing("vlc"));
    }

    #[tokio::test]
    async fn nothing_happens_unless_enabled() {
        let a = actions();
        a.on_lock(&Settings::default()).await;
        assert!(a.media.is_playing("spotify"));
        assert!(a.services.log().is_empty());
        assert!(a.apps.log().is_empty());
    }

    // ---- applications ----

    #[tokio::test]
    async fn only_listed_running_apps_are_closed_and_reopened() {
        let a = actions();
        a.on_lock(&settings()).await;
        assert_eq!(a.apps.log(), vec!["close spotify.desktop"]);
        assert_eq!(a.apps.running(), vec!["firefox.desktop"]);
        a.on_unlock(&settings()).await;
        assert!(a.apps.running().contains(&"spotify.desktop".to_string()));
        assert!(!a
            .apps
            .log()
            .iter()
            .any(|l| l == "launch not-running.desktop"));
        assert!(!a.apps.log().iter().any(|l| l == "launch firefox.desktop"));
    }

    #[tokio::test]
    async fn reopen_is_a_separate_opt_in_and_skips_apps_the_user_already_reopened() {
        let a = actions();
        let off = Settings {
            unlock_reopen_apps: false,
            ..settings()
        };
        a.on_lock(&off).await;
        a.on_unlock(&off).await;
        assert!(!a.apps.running().contains(&"spotify.desktop".to_string()));

        let b = actions();
        b.on_lock(&settings()).await;
        b.apps.launch("spotify.desktop").await.unwrap(); // the user reopened it by hand
        b.on_unlock(&settings()).await;
        assert_eq!(
            b.apps
                .log()
                .iter()
                .filter(|l| *l == "launch spotify.desktop")
                .count(),
            1,
            "no second copy"
        );
    }

    #[tokio::test]
    async fn invalid_or_protected_app_ids_are_never_touched() {
        let a = LockActions::new(
            MockMedia::default(),
            MockServices::default(),
            MockApps::with_running(&["gnome-shell.desktop", "-evil.desktop"]),
        );
        let s = Settings {
            lock_close_apps: vec![
                entry("gnome-shell.desktop"),
                entry("-evil.desktop"),
                entry("x; reboot"),
            ],
            ..settings()
        };
        a.on_lock(&s).await;
        assert!(a.apps.log().is_empty());
    }

    // ---- services ----

    #[tokio::test]
    async fn lock_stops_only_listed_running_services_and_unlock_starts_them() {
        let a = actions();
        let s = with_services(&["syncthing.service", "not-running.service"]);
        a.on_lock(&s).await;
        assert_eq!(a.services.log(), vec!["stop syncthing.service"]);
        assert_eq!(a.services.active(), vec!["other.service"]);
        a.on_unlock(&s).await;
        assert!(a
            .services
            .active()
            .contains(&"syncthing.service".to_string()));
        assert!(!a
            .services
            .log()
            .iter()
            .any(|l| l == "start not-running.service"));
    }

    #[tokio::test]
    async fn restart_is_a_separate_opt_in_and_memory_is_cleared() {
        let a = actions();
        let s = Settings {
            unlock_resume_media: false,
            unlock_start_services: false,
            unlock_reopen_apps: false,
            ..with_services(&["syncthing.service"])
        };
        a.on_lock(&s).await;
        a.on_unlock(&s).await;
        assert!(
            !a.media.is_playing("spotify"),
            "must stay paused when resume is off"
        );
        assert!(!a
            .services
            .active()
            .contains(&"syncthing.service".to_string()));
        a.on_unlock(&with_services(&["syncthing.service"])).await; // memory was cleared
        assert!(!a.media.is_playing("spotify"));
    }

    #[tokio::test]
    async fn failures_are_survived_and_do_not_record_phantom_changes() {
        let a = actions();
        a.media.set_fail(true);
        a.services.set_fail_stop(true);
        a.apps.set_fail_close(true);
        let s = with_services(&["syncthing.service"]);
        a.on_lock(&s).await; // must not panic
        a.media.set_fail(false);
        a.on_unlock(&s).await;
        assert!(a
            .services
            .active()
            .contains(&"syncthing.service".to_string()));
        assert!(
            !a.services.log().iter().any(|l| l.starts_with("start")),
            "nothing was stopped, so nothing is started"
        );
        assert!(
            !a.apps.log().iter().any(|l| l.starts_with("launch")),
            "nothing was closed, so nothing is launched"
        );
    }

    #[tokio::test]
    async fn invalid_or_protected_service_names_are_never_touched() {
        let a = LockActions::new(
            MockMedia::default(),
            MockServices::with_active(&["dbus.service", "-evil.service"]),
            MockApps::default(),
        );
        let s = with_services(&["dbus.service", "-evil.service", "x; reboot"]);
        a.on_lock(&s).await;
        assert!(a.services.log().is_empty());
    }

    #[tokio::test]
    async fn repeated_lock_attempts_do_not_duplicate_memory() {
        let a = actions();
        a.on_lock(&settings()).await;
        a.on_lock(&settings()).await; // e.g. a retried lock: nothing is playing / running any more
        a.on_unlock(&settings()).await;
        assert!(a.media.is_playing("spotify"));
        assert_eq!(
            a.apps
                .log()
                .iter()
                .filter(|l| l.starts_with("launch"))
                .count(),
            1
        );
    }
}
