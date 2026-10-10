//! stepawayd: locks the computer when a paired phone/watch moves away.

mod actions;
mod apps;
mod config;
mod engine;
mod ipc;
mod paths;
mod services;
mod store;

use std::sync::Arc;
use std::time::Duration;

use anyhow::Context;
use stepaway_ble::{AdvSource, BtleplugSource, ScanEvent};
use stepaway_core::token;
use stepaway_os::beacon::{BeaconAdvertiser, NullBeacon};
use stepaway_os::media::{MediaControl, NullMedia};
use stepaway_os::{LockBackend, OsError};
use tracing::{error, info, warn};

use crate::apps::{AppControl, NoApps};
use crate::config::Settings;
use crate::engine::{Effect, Engine, Output};
use crate::ipc::Shared;
use crate::services::{NoServices, ServiceControl, ServiceInfo};
use crate::store::Store;

#[cfg(target_os = "linux")]
type Backend = stepaway_os::logind::LogindBackend;
#[cfg(windows)]
type Backend = stepaway_os::windows::WindowsBackend;

#[cfg(target_os = "linux")]
async fn connect_backend() -> anyhow::Result<Backend> {
    Ok(Backend::connect().await?)
}
#[cfg(windows)]
async fn connect_backend() -> anyhow::Result<Backend> {
    Ok(Backend::new())
}

fn init_logging(level: &str) {
    use std::io::IsTerminal;
    let filter = tracing_subscriber::EnvFilter::try_new(level)
        .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info"));
    // Started by the app (detached) there is no terminal: keep a small log file instead.
    if !std::io::stderr().is_terminal() {
        let path = paths::log_file();
        if let Some(dir) = path.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        if std::fs::metadata(&path)
            .map(|m| m.len() > 1_000_000)
            .unwrap_or(false)
        {
            let _ = std::fs::rename(&path, path.with_extension("log.1"));
        }
        if let Ok(file) = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&path)
        {
            tracing_subscriber::fmt()
                .with_env_filter(filter)
                .with_ansi(false)
                .with_writer(std::sync::Mutex::new(file))
                .init();
            return;
        }
    }
    tracing_subscriber::fmt().with_env_filter(filter).init();
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let mut args = std::env::args().skip(1);
    let mut cmd = String::from("run");
    let mut level = String::from("info");
    while let Some(a) = args.next() {
        match a.as_str() {
            "--log-level" => level = args.next().context("--log-level needs a value")?,
            "run" | "scan" | "devices" | "apps" | "services" => cmd = a,
            "-h" | "--help" => {
                println!("usage: stepawayd [run|scan|devices] [--log-level LEVEL]");
                return Ok(());
            }
            other => anyhow::bail!("unknown argument: {other}"),
        }
    }
    init_logging(&level);
    match cmd.as_str() {
        "scan" => scan().await,
        "devices" => devices(),
        "apps" => list_apps().await,
        "services" => list_services().await,
        _ => run().await,
    }
}

/// Diagnostic: print the applications StepAway can offer (running ones first). Changes nothing.
async fn list_apps() -> anyhow::Result<()> {
    for a in connect_apps().await.list().await {
        println!(
            "{} {:<48} {}",
            if a.running { "*" } else { " " },
            a.id,
            a.name
        );
    }
    Ok(())
}

/// Diagnostic: print the running services StepAway can offer. Changes nothing.
async fn list_services() -> anyhow::Result<()> {
    for s in connect_services().await.list_running().await {
        println!("{:<48} {}", s.id, s.name);
    }
    Ok(())
}

fn devices() -> anyhow::Result<()> {
    let store = Store::load(&paths::devices_file())?;
    for d in store.list() {
        println!("{:04x}  {}", d.device_id, d.name);
    }
    Ok(())
}

/// Debug aid: print every StepAway advertisement and whether it verifies for a paired device.
async fn scan() -> anyhow::Result<()> {
    let store = Store::load(&paths::devices_file())?;
    let mut src = BtleplugSource::start().await?;
    println!("scanning for StepAway advertisements (Ctrl+C to stop)...");
    while let Some(ev) = src.next().await {
        let ScanEvent::Stepaway(adv) = ev else {
            continue;
        };
        let id = u16::from_be_bytes([adv.payload[1], adv.payload[2]]);
        let now = Shared::now_unix();
        let verdict = match store.get(id).and_then(|d| d.secret()) {
            Some(s) => match token::verify(&s, id, &adv.payload, now, None) {
                Ok(_) => "valid".to_string(),
                Err(e) => format!("invalid ({e})"),
            },
            None => "unpaired device".to_string(),
        };
        let hex: String = adv.payload.iter().map(|b| format!("{b:02x}")).collect();
        println!(
            "rssi {:>4} dBm  id {id:04x}  payload {hex}  {verdict}",
            adv.rssi
        );
    }
    Ok(())
}

/// Media control for this platform (or nothing when it is unavailable).
enum AnyMedia {
    #[cfg(target_os = "linux")]
    Mpris(stepaway_os::media::MprisMedia),
    #[cfg(windows)]
    Windows(stepaway_os::media::WindowsMedia),
    #[cfg_attr(windows, allow(dead_code))] // Windows always has media transport controls
    Null(NullMedia),
}

impl MediaControl for AnyMedia {
    async fn pause_playing(&self) -> Result<Vec<String>, OsError> {
        match self {
            #[cfg(target_os = "linux")]
            AnyMedia::Mpris(m) => m.pause_playing().await,
            #[cfg(windows)]
            AnyMedia::Windows(m) => m.pause_playing().await,
            AnyMedia::Null(m) => m.pause_playing().await,
        }
    }

    async fn resume(&self, players: &[String]) -> Result<(), OsError> {
        match self {
            #[cfg(target_os = "linux")]
            AnyMedia::Mpris(m) => m.resume(players).await,
            #[cfg(windows)]
            AnyMedia::Windows(m) => m.resume(players).await,
            AnyMedia::Null(m) => m.resume(players).await,
        }
    }
}

enum AnyServices {
    #[cfg(target_os = "linux")]
    Systemd(services::SystemdUser),
    #[cfg(windows)]
    Windows(services::windows::WindowsServices),
    #[cfg_attr(windows, allow(dead_code))]
    None(NoServices),
}

enum AnyApps {
    #[cfg(target_os = "linux")]
    Xdg(apps::linux::XdgApps),
    #[cfg(windows)]
    Windows(apps::windows::WindowsApps),
    #[allow(dead_code)]
    None(NoApps),
}

impl AppControl for AnyApps {
    async fn list(&self) -> Vec<apps::AppInfo> {
        match self {
            #[cfg(target_os = "linux")]
            AnyApps::Xdg(a) => a.list().await,
            #[cfg(windows)]
            AnyApps::Windows(a) => a.list().await,
            AnyApps::None(a) => a.list().await,
        }
    }
    async fn is_running(&self, id: &str) -> bool {
        match self {
            #[cfg(target_os = "linux")]
            AnyApps::Xdg(a) => a.is_running(id).await,
            #[cfg(windows)]
            AnyApps::Windows(a) => a.is_running(id).await,
            AnyApps::None(a) => a.is_running(id).await,
        }
    }
    async fn close(&self, id: &str) -> Result<(), String> {
        match self {
            #[cfg(target_os = "linux")]
            AnyApps::Xdg(a) => a.close(id).await,
            #[cfg(windows)]
            AnyApps::Windows(a) => a.close(id).await,
            AnyApps::None(a) => a.close(id).await,
        }
    }
    async fn launch(&self, id: &str) -> Result<(), String> {
        match self {
            #[cfg(target_os = "linux")]
            AnyApps::Xdg(a) => a.launch(id).await,
            #[cfg(windows)]
            AnyApps::Windows(a) => a.launch(id).await,
            AnyApps::None(a) => a.launch(id).await,
        }
    }
}

impl ServiceControl for AnyServices {
    async fn is_active(&self, unit: &str) -> bool {
        match self {
            #[cfg(target_os = "linux")]
            AnyServices::Systemd(s) => s.is_active(unit).await,
            #[cfg(windows)]
            AnyServices::Windows(s) => s.is_active(unit).await,
            AnyServices::None(s) => s.is_active(unit).await,
        }
    }
    async fn stop(&self, unit: &str) -> Result<(), String> {
        match self {
            #[cfg(target_os = "linux")]
            AnyServices::Systemd(s) => s.stop(unit).await,
            #[cfg(windows)]
            AnyServices::Windows(s) => s.stop(unit).await,
            AnyServices::None(s) => s.stop(unit).await,
        }
    }
    async fn start(&self, unit: &str) -> Result<(), String> {
        match self {
            #[cfg(target_os = "linux")]
            AnyServices::Systemd(s) => s.start(unit).await,
            #[cfg(windows)]
            AnyServices::Windows(s) => s.start(unit).await,
            AnyServices::None(s) => s.start(unit).await,
        }
    }
    async fn list_running(&self) -> Vec<ServiceInfo> {
        match self {
            #[cfg(target_os = "linux")]
            AnyServices::Systemd(s) => s.list_running().await,
            #[cfg(windows)]
            AnyServices::Windows(s) => s.list_running().await,
            AnyServices::None(s) => s.list_running().await,
        }
    }
}

/// The computer's own beacon (Bluetooth advertising), or nothing when it is unavailable.
enum AnyBeacon {
    #[cfg(target_os = "linux")]
    BlueZ(stepaway_os::beacon::BlueZBeacon),
    #[cfg(windows)]
    Windows(stepaway_os::beacon::WindowsBeacon),
    #[cfg_attr(windows, allow(dead_code))]
    Null(NullBeacon),
}

impl BeaconAdvertiser for AnyBeacon {
    async fn set_payload(
        &self,
        payload: Option<[u8; stepaway_os::beacon::PAYLOAD_LEN]>,
    ) -> Result<(), OsError> {
        match self {
            #[cfg(target_os = "linux")]
            AnyBeacon::BlueZ(b) => b.set_payload(payload).await,
            #[cfg(windows)]
            AnyBeacon::Windows(b) => b.set_payload(payload).await,
            AnyBeacon::Null(b) => b.set_payload(payload).await,
        }
    }
}

#[cfg(target_os = "linux")]
async fn connect_beacon() -> AnyBeacon {
    match stepaway_os::beacon::BlueZBeacon::connect().await {
        Ok(b) => AnyBeacon::BlueZ(b),
        Err(e) => {
            warn!("beacon unavailable: {e}");
            AnyBeacon::Null(NullBeacon)
        }
    }
}
#[cfg(windows)]
async fn connect_beacon() -> AnyBeacon {
    AnyBeacon::Windows(stepaway_os::beacon::WindowsBeacon::new())
}

type Actions = actions::LockActions<AnyMedia, AnyServices, AnyApps>;

#[cfg(target_os = "linux")]
async fn connect_media() -> AnyMedia {
    match stepaway_os::media::MprisMedia::connect().await {
        Ok(m) => AnyMedia::Mpris(m),
        Err(e) => {
            warn!("media control unavailable: {e}");
            AnyMedia::Null(NullMedia)
        }
    }
}
#[cfg(windows)]
async fn connect_media() -> AnyMedia {
    AnyMedia::Windows(stepaway_os::media::WindowsMedia)
}

#[cfg(target_os = "linux")]
async fn connect_services() -> AnyServices {
    if services::SystemdUser::available().await {
        AnyServices::Systemd(services::SystemdUser)
    } else {
        AnyServices::None(NoServices)
    }
}
#[cfg(windows)]
async fn connect_services() -> AnyServices {
    AnyServices::Windows(services::windows::WindowsServices)
}

#[cfg(target_os = "linux")]
async fn connect_apps() -> AnyApps {
    AnyApps::Xdg(apps::linux::XdgApps)
}
#[cfg(windows)]
async fn connect_apps() -> AnyApps {
    AnyApps::Windows(apps::windows::WindowsApps)
}

const SCAN_WATCHDOG: Duration = Duration::from_secs(10);

async fn apply(out: Output, shared: &Shared, backend: &Backend, actions: &Actions) {
    for ev in &out.events {
        if let engine::Event::State { from, to } = ev {
            info!(
                "state {} -> {}",
                engine::state_name(*from),
                engine::state_name(*to)
            );
        }
        shared.publish(ev);
    }
    for eff in out.effects {
        match eff {
            Effect::Lock => {
                info!("locking the session");
                match backend.lock().await {
                    Ok(()) => {
                        // pause music/videos and stop the user's listed services
                        let settings = shared.engine().settings().clone();
                        actions.on_lock(&settings).await;
                    }
                    Err(e) => {
                        error!("lock failed: {e}");
                        let retry = shared.engine().on_lock_failed();
                        for ev in &retry.events {
                            shared.publish(ev);
                        }
                    }
                }
            }
            Effect::Unlock => {
                // Extra guard: only ever unlock a session that really is locked.
                match backend.is_locked().await {
                    Ok(true) => {
                        info!("unlocking the session");
                        if let Err(e) = backend.unlock().await {
                            warn!("unlock failed: {e}");
                        }
                    }
                    Ok(false) => {}
                    Err(e) => warn!("not unlocking, lock state unknown: {e}"),
                }
            }
        }
    }
}

async fn run() -> anyhow::Result<()> {
    let settings_path = paths::config_file();
    let settings = match Settings::load(&settings_path) {
        Ok(s) => s,
        Err(e) => {
            warn!("invalid config ({e}); using defaults for this run");
            Settings::default()
        }
    };
    let store =
        Store::load(&paths::devices_file()).context("could not read the paired devices file")?;
    let backend = connect_backend()
        .await
        .context("could not connect to the OS lock service")?;
    // Unlock is only allowed once a user session has been seen unlocked (never straight after boot).
    let locked_at_start = backend.is_locked().await.unwrap_or(true);
    let engine = Engine::new(settings, Some(settings_path), store, !locked_at_start);
    let shared = Shared::new(engine);
    shared.engine().on_session(locked_at_start, 0);

    let actions = Arc::new(Actions::new(
        connect_media().await,
        connect_services().await,
        connect_apps().await,
    ));
    shared.caps_media.store(
        !matches!(actions.media(), AnyMedia::Null(_)),
        std::sync::atomic::Ordering::Relaxed,
    );
    shared.caps_services.store(
        !matches!(actions.services(), AnyServices::None(_)),
        std::sync::atomic::Ordering::Relaxed,
    );
    shared.caps_apps.store(
        !matches!(actions.apps(), AnyApps::None(_)),
        std::sync::atomic::Ordering::Relaxed,
    );
    let app_actions = actions.clone();
    shared.set_app_lister(Box::new(move || {
        let a = app_actions.clone();
        Box::pin(async move {
            serde_json::to_value(a.apps().list().await).unwrap_or_else(|_| serde_json::json!([]))
        })
    }));
    let service_actions = actions.clone();
    shared.set_service_lister(Box::new(move || {
        let a = service_actions.clone();
        Box::pin(async move {
            serde_json::to_value(a.services().list_running().await)
                .unwrap_or_else(|_| serde_json::json!([]))
        })
    }));
    let beacon = connect_beacon().await;
    shared.caps_beacon.store(
        !matches!(beacon, AnyBeacon::Null(_)),
        std::sync::atomic::Ordering::Relaxed,
    );
    let mut beacon_window = u64::MAX;
    let mut was_locked = locked_at_start;

    let ipc_shared = shared.clone();
    tokio::spawn(async move {
        if let Err(e) = ipc::serve(ipc_shared).await {
            error!("IPC server stopped: {e}");
        }
    });

    let mut source: Option<BtleplugSource> = None;
    let mut retry = tokio::time::interval(Duration::from_secs(2));
    // BlueZ can stop discovering (adapter power cycle, suspend) without telling btleplug, so a
    // scanner that has produced nothing for a while is restarted.
    let mut last_adv = std::time::Instant::now();
    let mut tick = tokio::time::interval(Duration::from_millis(500));
    let mut ticks = 0u64;
    info!("stepawayd started");
    loop {
        tokio::select! {
            _ = shutdown_signal() => break,
            _ = tick.tick() => {
                ticks += 1;
                // the beacon carries a token that changes every window
                let window = Shared::now_unix() / stepaway_core::token::WINDOW_SECS;
                if window != beacon_window {
                    beacon_window = window;
                    let payload = shared.engine().beacon_payload(Shared::now_unix());
                    if let Err(e) = beacon.set_payload(payload).await {
                        tracing::debug!("beacon update failed: {e}");
                    }
                }
                let now = shared.now_ms();
                if source.is_some() && last_adv.elapsed() > SCAN_WATCHDOG {
                    info!("no advertisements for {SCAN_WATCHDOG:?}; restarting the Bluetooth scan");
                    source = None;
                    last_adv = std::time::Instant::now();
                }
                let mut out = shared.engine().on_tick(now);
                if ticks.is_multiple_of(2) {
                    if let Ok(locked) = backend.is_locked().await {
                        if was_locked && !locked {
                            // unlocked (by us or by the user): bring back what we paused or stopped
                            let settings = shared.engine().settings().clone();
                            actions.on_unlock(&settings).await;
                        }
                        was_locked = locked;
                        let o = shared.engine().on_session(locked, now);
                        out.effects.extend(o.effects);
                        out.events.extend(o.events);
                    }
                }
                apply(out, &shared, &backend, &actions).await;
            }
            adv = next_adv(&mut source) => match adv {
                Some(ev) => {
                    last_adv = std::time::Instant::now();
                    let (now_unix, now_ms) = (Shared::now_unix(), shared.now_ms());
                    let out = match ev {
                        ScanEvent::Stepaway(a) => shared.engine().on_advertisement(&a, now_unix, now_ms),
                        ScanEvent::PairingChunk(c) => shared.engine().on_pairing_chunk(&c, now_unix),
                        ScanEvent::Other(o) => shared.engine().on_other(&o, now_unix, now_ms),
                    };
                    apply(out, &shared, &backend, &actions).await;
                }
                None => {
                    warn!("Bluetooth scanning stopped; will retry");
                    source = None;
                }
            },
            _ = retry.tick(), if source.is_none() => match BtleplugSource::start().await {
                Ok(s) => {
                    info!("Bluetooth scanning started");
                    shared.scanning.store(true, std::sync::atomic::Ordering::Relaxed);
                    last_adv = std::time::Instant::now();
                    source = Some(s);
                }
                Err(e) => {
                    if shared.scanning.swap(false, std::sync::atomic::Ordering::Relaxed) {
                        warn!("Bluetooth unavailable: {e}");
                    }
                }
            },
        }
    }
    let _ = beacon.set_payload(None).await;
    info!("stepawayd stopped");
    #[cfg(unix)]
    let _ = std::fs::remove_file(paths::socket_path());
    let _ = Arc::strong_count(&shared);
    Ok(())
}

async fn next_adv(source: &mut Option<BtleplugSource>) -> Option<ScanEvent> {
    match source {
        Some(s) => s.next().await,
        None => std::future::pending().await,
    }
}

async fn shutdown_signal() {
    #[cfg(unix)]
    {
        use tokio::signal::unix::{signal, SignalKind};
        match signal(SignalKind::terminate()) {
            Ok(mut term) => {
                tokio::select! {
                    _ = tokio::signal::ctrl_c() => {}
                    _ = term.recv() => {}
                }
            }
            Err(_) => {
                let _ = tokio::signal::ctrl_c().await;
            }
        }
    }
    #[cfg(not(unix))]
    {
        let _ = tokio::signal::ctrl_c().await;
    }
}
