//! JSON-RPC 2.0 server (newline-delimited) over a Unix socket / Windows named pipe.
//! Only the daemon's own user may connect.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use serde_json::{json, Value};
use tokio::io::{AsyncBufReadExt, AsyncRead, AsyncWrite, AsyncWriteExt, BufReader};
use tokio::sync::broadcast;

use crate::engine::{state_name, Engine, EngineError, Event};

pub const PROTOCOL_VERSION: u32 = 1;
const ERR_PARSE: i64 = -32700;
const ERR_INVALID: i64 = -32600;
const ERR_METHOD: i64 = -32601;
const ERR_PARAMS: i64 = -32602;
const ERR_UNKNOWN_DEVICE: i64 = -32002;

pub struct Shared {
    engine: Mutex<Engine>,
    pub events: broadcast::Sender<String>,
    pub scanning: AtomicBool,
    /// What this machine can do besides locking (reported to the UI).
    pub caps_media: AtomicBool,
    pub caps_services: AtomicBool,
    pub caps_apps: AtomicBool,
    pub caps_beacon: AtomicBool,
    app_lister: std::sync::OnceLock<Lister>,
    service_lister: std::sync::OnceLock<Lister>,
    start: Instant,
}

/// Async callback returning a JSON list (applications or services) for the pickers.
pub type Lister = Box<
    dyn Fn() -> std::pin::Pin<Box<dyn std::future::Future<Output = Value> + Send>> + Send + Sync,
>;

impl Shared {
    pub fn new(engine: Engine) -> Arc<Self> {
        let (events, _) = broadcast::channel(256);
        Arc::new(Self {
            engine: Mutex::new(engine),
            events,
            scanning: AtomicBool::new(false),
            caps_media: AtomicBool::new(false),
            caps_services: AtomicBool::new(false),
            caps_apps: AtomicBool::new(false),
            caps_beacon: AtomicBool::new(false),
            app_lister: std::sync::OnceLock::new(),
            service_lister: std::sync::OnceLock::new(),
            start: Instant::now(),
        })
    }

    /// Registers how `listApps` / `listServices` find their entries (set once at startup).
    pub fn set_app_lister(&self, f: Lister) {
        let _ = self.app_lister.set(f);
    }

    pub fn set_service_lister(&self, f: Lister) {
        let _ = self.service_lister.set(f);
    }

    pub async fn list(&self, apps: bool) -> Value {
        let lister = if apps {
            self.app_lister.get()
        } else {
            self.service_lister.get()
        };
        match lister {
            Some(f) => f().await,
            None => json!([]),
        }
    }

    /// A poisoned lock only means a panic elsewhere; the engine state is still consistent.
    pub fn engine(&self) -> MutexGuard<'_, Engine> {
        self.engine.lock().unwrap_or_else(|e| e.into_inner())
    }

    pub fn now_ms(&self) -> u64 {
        self.start.elapsed().as_millis() as u64
    }

    pub fn now_unix() -> u64 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0)
    }

    pub fn publish(&self, ev: &Event) {
        // No subscribers is fine.
        let _ = self
            .events
            .send(ev.to_notification(Self::now_unix()).to_string());
    }
}

type RpcResult = Result<Value, (i64, String)>;

fn engine_err(e: EngineError) -> (i64, String) {
    let code = match e {
        EngineError::Invalid(_) => ERR_PARAMS,
        EngineError::UnknownDevice => ERR_UNKNOWN_DEVICE,
    };
    (code, e.to_string())
}

fn device_id(params: &Value) -> Result<u16, (i64, String)> {
    params
        .get("device_id")
        .and_then(Value::as_u64)
        .and_then(|v| u16::try_from(v).ok())
        .ok_or((ERR_PARAMS, "device_id (0-65535) required".into()))
}

pub fn dispatch(shared: &Shared, method: &str, params: &Value) -> RpcResult {
    let now_unix = Shared::now_unix();
    let mut e = shared.engine();
    match method {
        "status" => {
            let timeout = e.settings().lost_timeout_s;
            let present: Vec<u16> = e
                .devices()
                .iter()
                .filter(|d| d.last_seen_unix.is_some_and(|t| now_unix.saturating_sub(t) <= timeout))
                .map(|d| d.device_id)
                .collect();
            Ok(json!({
                "protocol": PROTOCOL_VERSION,
                "version": env!("CARGO_PKG_VERSION"),
                "state": state_name(e.state()),
                "paused": e.paused(),
                "scanning": shared.scanning.load(Ordering::Relaxed),
                "unlock_enabled": e.settings().unlock_enabled,
                "unlock_block": e.unlock_block(shared.now_ms()).map(|b| b.as_str()),
                "presence_rule": e.settings().presence_rule,
                "capabilities": {
                    "media": shared.caps_media.load(Ordering::Relaxed),
                    "services": shared.caps_services.load(Ordering::Relaxed),
                    "apps": shared.caps_apps.load(Ordering::Relaxed),
                    "beacon": shared.caps_beacon.load(Ordering::Relaxed),
                },
                "devices_present": present,
            }))
        }
        "listDevices" => Ok(Value::Array(
            e.devices()
                .iter()
                .map(|d| {
                    json!({
                        "device_id": d.device_id, "name": d.name, "kind": d.kind, "paired_at": d.paired_at,
                        "last_seen": d.last_seen_unix, "presence_only": d.presence_only, "address": d.address,
                        "calibrated": d.tx_power_1m.is_some(),
                    })
                })
                .collect(),
        )),
        "startPairing" => {
            let name = params.get("name").and_then(Value::as_str).map(str::to_owned);
            let kind = params.get("kind").and_then(Value::as_str);
            let (uri, code, expires) = e.start_pairing(name, kind, now_unix).map_err(engine_err)?;
            Ok(json!({"qr_uri": uri, "verification_code": code, "expires_at": expires}))
        }
        "startCodePairing" => {
            let code = params.get("code").and_then(Value::as_str).unwrap_or("");
            let name = params.get("name").and_then(Value::as_str).map(str::to_owned);
            let expires = e.start_code_pairing(code, name, now_unix).map_err(engine_err)?;
            Ok(json!({"expires_at": expires}))
        }
        "listNearby" => Ok(Value::Array(
            e.nearby_devices(now_unix)
                .into_iter()
                .map(|n| json!({"address": n.address, "name": n.name, "rssi": n.rssi}))
                .collect(),
        )),
        "addPresenceDevice" => {
            let address = params.get("address").and_then(Value::as_str).unwrap_or("");
            let name = params.get("name").and_then(Value::as_str).unwrap_or("");
            let kind = params.get("kind").and_then(Value::as_str).unwrap_or("other");
            let id = e.add_presence_device(address, name, kind, now_unix).map_err(engine_err)?;
            Ok(json!({"device_id": id}))
        }
        "updateDevice" => {
            let name = params.get("name").and_then(Value::as_str);
            let kind = params.get("kind").and_then(Value::as_str);
            e.update_device(device_id(params)?, name, kind).map_err(engine_err)?;
            Ok(json!({"ok": true}))
        }
        "cancelPairing" => {
            e.cancel_pairing();
            Ok(json!({"ok": true}))
        }
        "confirmPairing" => Ok(json!({"ok": e.is_device_paired(device_id(params)?)})),
        "removeDevice" => {
            e.remove_device(device_id(params)?).map_err(engine_err)?;
            Ok(json!({"ok": true}))
        }
        "getConfig" => serde_json::to_value(e.settings()).map_err(|x| (ERR_PARAMS, x.to_string())),
        "setConfig" => {
            let s = e.set_settings(params).map_err(engine_err)?;
            serde_json::to_value(s).map_err(|x| (ERR_PARAMS, x.to_string()))
        }
        "startCalibration" => {
            let step = params.get("step").and_then(Value::as_str).unwrap_or("");
            let device = match params.get("device_id") {
                None | Some(Value::Null) => None,
                Some(_) => Some(device_id(params)?),
            };
            e.start_calibration_for(step, device, shared.now_ms()).map_err(engine_err)?;
            Ok(json!({"ok": true}))
        }
        "pause" | "resume" => {
            e.set_paused(method == "pause");
            Ok(json!({"ok": true}))
        }
        _ => Err((ERR_METHOD, format!("unknown method: {method}"))),
    }
}

/// Handle one JSON-RPC request line; returns the response line (None for notifications).
pub fn handle_line(shared: &Shared, line: &str) -> Option<String> {
    let req: Value = match serde_json::from_str(line) {
        Ok(v) => v,
        Err(_) => return Some(error_response(Value::Null, ERR_PARSE, "parse error")),
    };
    let id = req.get("id").cloned();
    let Some(method) = req.get("method").and_then(Value::as_str) else {
        return Some(error_response(
            id.unwrap_or(Value::Null),
            ERR_INVALID,
            "invalid request",
        ));
    };
    let params = req.get("params").cloned().unwrap_or_else(|| json!({}));
    let result = dispatch(shared, method, &params);
    let id = id?; // a request without id is a notification: no reply
    Some(match result {
        Ok(v) => json!({"jsonrpc": "2.0", "id": id, "result": v}).to_string(),
        Err((code, msg)) => error_response(id, code, &msg),
    })
}

fn error_response(id: Value, code: i64, msg: &str) -> String {
    json!({"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": msg}}).to_string()
}

/// Like [`handle_line`], plus the methods that need to wait for the operating system.
pub async fn handle_line_async(shared: &Shared, line: &str) -> Option<String> {
    if let Ok(req) = serde_json::from_str::<Value>(line) {
        let method = req.get("method").and_then(Value::as_str);
        if method == Some("listServices") || method == Some("listApps") {
            let id = req.get("id").cloned()?;
            let list = shared.list(method == Some("listApps")).await;
            return Some(json!({"jsonrpc": "2.0", "id": id, "result": list}).to_string());
        }
    }
    handle_line(shared, line)
}

pub async fn serve_connection<R, W>(reader: R, mut writer: W, shared: Arc<Shared>)
where
    R: AsyncRead + Unpin,
    W: AsyncWrite + Unpin,
{
    let mut lines = BufReader::new(reader).lines();
    let mut rx = shared.events.subscribe();
    loop {
        tokio::select! {
            line = lines.next_line() => match line {
                Ok(Some(l)) if l.trim().is_empty() => {}
                Ok(Some(l)) => {
                    if let Some(resp) = handle_line_async(&shared, &l).await {
                        if write_line(&mut writer, &resp).await.is_err() { break; }
                    }
                }
                _ => break,
            },
            ev = rx.recv() => match ev {
                Ok(s) => { if write_line(&mut writer, &s).await.is_err() { break; } }
                Err(broadcast::error::RecvError::Lagged(_)) => {}
                Err(broadcast::error::RecvError::Closed) => break,
            },
        }
    }
}

async fn write_line<W: AsyncWrite + Unpin>(w: &mut W, s: &str) -> std::io::Result<()> {
    w.write_all(s.as_bytes()).await?;
    w.write_all(b"\n").await?;
    w.flush().await
}

#[cfg(unix)]
pub async fn serve(shared: Arc<Shared>) -> anyhow::Result<()> {
    use std::os::unix::fs::{MetadataExt, PermissionsExt};
    use tokio::net::{UnixListener, UnixStream};

    let path = crate::paths::socket_path();
    if path.exists() {
        if UnixStream::connect(&path).await.is_ok() {
            anyhow::bail!("another stepawayd is already running ({})", path.display());
        }
        std::fs::remove_file(&path)?;
    }
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let listener = UnixListener::bind(&path)?;
    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600))?;
    let my_uid = std::fs::metadata(&path)?.uid();
    tracing::info!("IPC listening on {}", path.display());
    loop {
        let (stream, _) = listener.accept().await?;
        match stream.peer_cred() {
            Ok(c) if c.uid() == my_uid => {}
            _ => {
                tracing::warn!("rejected IPC peer with a different uid");
                continue;
            }
        }
        let (r, w) = stream.into_split();
        tokio::spawn(serve_connection(r, w, shared.clone()));
    }
}

#[cfg(windows)]
struct PipeSecurity(windows_sys::Win32::Security::SECURITY_ATTRIBUTES);

// SAFETY: the descriptor is a private heap allocation that is only read through this value.
#[cfg(windows)]
unsafe impl Send for PipeSecurity {}

#[cfg(windows)]
impl PipeSecurity {
    /// Owner and SYSTEM only: no other user, no "Everyone" read access.
    fn owner_only() -> anyhow::Result<Self> {
        use windows_sys::Win32::Security::Authorization::ConvertStringSecurityDescriptorToSecurityDescriptorW;
        use windows_sys::Win32::Security::SECURITY_ATTRIBUTES;
        let sddl: Vec<u16> = "D:P(A;;GA;;;OW)(A;;GA;;;SY)\0".encode_utf16().collect();
        let mut psd: *mut core::ffi::c_void = std::ptr::null_mut();
        // SAFETY: sddl is NUL-terminated; psd receives a LocalAlloc'd descriptor freed in Drop.
        let ok = unsafe {
            ConvertStringSecurityDescriptorToSecurityDescriptorW(
                sddl.as_ptr(),
                1,
                &mut psd,
                std::ptr::null_mut(),
            )
        };
        if ok == 0 {
            anyhow::bail!("could not build the pipe security descriptor");
        }
        Ok(Self(SECURITY_ATTRIBUTES {
            nLength: std::mem::size_of::<SECURITY_ATTRIBUTES>() as u32,
            lpSecurityDescriptor: psd,
            bInheritHandle: 0,
        }))
    }
}

#[cfg(windows)]
impl Drop for PipeSecurity {
    fn drop(&mut self) {
        // SAFETY: allocated by ConvertStringSecurityDescriptorToSecurityDescriptorW.
        unsafe { windows_sys::Win32::Foundation::LocalFree(self.0.lpSecurityDescriptor) };
    }
}

#[cfg(windows)]
pub async fn serve(shared: Arc<Shared>) -> anyhow::Result<()> {
    use tokio::net::windows::named_pipe::ServerOptions;

    let name = crate::paths::pipe_name();
    let mut sec = PipeSecurity::owner_only()?;
    let mut first = true;
    tracing::info!("IPC listening on {name}");
    loop {
        let mut opts = ServerOptions::new();
        opts.first_pipe_instance(first).reject_remote_clients(true);
        // SAFETY: `sec` and the descriptor it points to outlive this call.
        let server = unsafe {
            opts.create_with_security_attributes_raw(
                &name,
                (&mut sec.0 as *mut windows_sys::Win32::Security::SECURITY_ATTRIBUTES).cast(),
            )
        }?;
        first = false;
        server.connect().await?;
        let (r, w) = tokio::io::split(server);
        tokio::spawn(serve_connection(r, w, shared.clone()));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::Settings;
    use crate::store::Store;

    fn shared() -> Arc<Shared> {
        Shared::new(Engine::new(
            Settings::default(),
            None,
            Store::in_memory(),
            true,
        ))
    }

    fn call(s: &Shared, req: Value) -> Value {
        serde_json::from_str(&handle_line(s, &req.to_string()).unwrap()).unwrap()
    }

    #[test]
    fn status_and_unknown_method() {
        let s = shared();
        let r = call(&s, json!({"jsonrpc":"2.0","id":1,"method":"status"}));
        assert_eq!(r["result"]["state"], "UNKNOWN");
        assert_eq!(r["result"]["protocol"], 1);
        let r = call(&s, json!({"jsonrpc":"2.0","id":2,"method":"nope"}));
        assert_eq!(r["error"]["code"], -32601);
    }

    #[test]
    fn malformed_input_gets_errors_not_panics() {
        let s = shared();
        let r: Value = serde_json::from_str(&handle_line(&s, "{not json").unwrap()).unwrap();
        assert_eq!(r["error"]["code"], -32700);
        let r: Value = serde_json::from_str(&handle_line(&s, "[1,2]").unwrap()).unwrap();
        assert_eq!(r["error"]["code"], -32600);
        assert!(handle_line(&s, r#"{"jsonrpc":"2.0","method":"pause"}"#).is_none());
    }

    #[test]
    fn pairing_config_and_pause_flow() {
        let s = shared();
        let r = call(
            &s,
            json!({"jsonrpc":"2.0","id":1,"method":"startPairing","params":{"name":"Moto"}}),
        );
        assert!(r["result"]["qr_uri"]
            .as_str()
            .unwrap()
            .starts_with("stepaway://pair?"));
        assert_eq!(r["result"]["verification_code"].as_str().unwrap().len(), 6);
        let r = call(
            &s,
            json!({"jsonrpc":"2.0","id":2,"method":"setConfig","params":{"lock_distance_m":4.0}}),
        );
        assert_eq!(r["result"]["lock_distance_m"], 4.0);
        let r = call(
            &s,
            json!({"jsonrpc":"2.0","id":3,"method":"setConfig","params":{"lock_distance_m":0.1}}),
        );
        assert_eq!(r["error"]["code"], -32602);
        call(&s, json!({"jsonrpc":"2.0","id":4,"method":"pause"}));
        let r = call(&s, json!({"jsonrpc":"2.0","id":5,"method":"status"}));
        assert_eq!(r["result"]["paused"], true);
        let r = call(
            &s,
            json!({"jsonrpc":"2.0","id":6,"method":"removeDevice","params":{"device_id":9}}),
        );
        assert_eq!(r["error"]["code"], -32002);
    }

    #[test]
    fn list_devices_never_exposes_secrets() {
        let s = shared();
        let r = call(&s, json!({"jsonrpc":"2.0","id":1,"method":"listDevices"}));
        assert_eq!(r["result"], json!([]));
    }

    #[tokio::test]
    async fn pickers_use_their_own_listers_and_status_reports_capabilities() {
        let s = shared();
        s.set_service_lister(Box::new(|| {
            Box::pin(async { json!([{"id": "syncthing.service", "name": "syncthing"}]) })
        }));
        s.set_app_lister(Box::new(|| {
            Box::pin(async {
                json!([{"id": "firefox.desktop", "name": "Firefox", "running": true}])
            })
        }));
        s.caps_media.store(true, Ordering::Relaxed);
        s.caps_apps.store(true, Ordering::Relaxed);
        let r = handle_line_async(&s, r#"{"jsonrpc":"2.0","id":4,"method":"listServices"}"#)
            .await
            .unwrap();
        assert_eq!(
            serde_json::from_str::<Value>(&r).unwrap()["result"][0]["id"],
            "syncthing.service"
        );
        let r = handle_line_async(&s, r#"{"jsonrpc":"2.0","id":5,"method":"listApps"}"#)
            .await
            .unwrap();
        let v: Value = serde_json::from_str(&r).unwrap();
        assert_eq!(v["result"][0]["id"], "firefox.desktop");
        assert_eq!(v["result"][0]["running"], true);
        let st = call(&s, json!({"jsonrpc":"2.0","id":6,"method":"status"}));
        assert_eq!(st["result"]["version"], env!("CARGO_PKG_VERSION"));
        // unlock is off by default, so that is the reason reported
        assert_eq!(st["result"]["unlock_block"], "disabled");
        assert_eq!(st["result"]["capabilities"]["media"], true);
        assert_eq!(st["result"]["capabilities"]["apps"], true);
        assert_eq!(st["result"]["capabilities"]["services"], false);
    }

    #[test]
    fn code_pairing_over_ipc() {
        let s = shared();
        let r = call(
            &s,
            json!({"jsonrpc":"2.0","id":1,"method":"startCodePairing","params":{"code":"nope"}}),
        );
        assert_eq!(r["error"]["code"], -32602);
        let r = call(
            &s,
            json!({"jsonrpc":"2.0","id":2,"method":"startCodePairing","params":{"code":"000G-40R4-0M30-E209","name":"Watch"}}),
        );
        assert!(r["result"]["expires_at"].as_u64().unwrap() > 0);
        let r = call(&s, json!({"jsonrpc":"2.0","id":3,"method":"cancelPairing"}));
        assert_eq!(r["result"]["ok"], true);
    }

    #[test]
    fn device_methods_over_ipc() {
        let s = shared();
        let r = call(
            &s,
            json!({"jsonrpc":"2.0","id":1,"method":"addPresenceDevice","params":{"address":"AA:BB:CC:DD:EE:05","name":"Band","kind":"watch"}}),
        );
        let id = r["result"]["device_id"].as_u64().unwrap();
        let r = call(
            &s,
            json!({"jsonrpc":"2.0","id":2,"method":"addPresenceDevice","params":{"address":"nope"}}),
        );
        assert_eq!(r["error"]["code"], -32602);
        let r = call(&s, json!({"jsonrpc":"2.0","id":3,"method":"listDevices"}));
        let d = &r["result"][0];
        assert_eq!(
            (
                d["kind"].as_str(),
                d["presence_only"].as_bool(),
                d["address"].as_str()
            ),
            (Some("watch"), Some(true), Some("AA:BB:CC:DD:EE:05"))
        );
        let r = call(
            &s,
            json!({"jsonrpc":"2.0","id":4,"method":"updateDevice","params":{"device_id":id,"name":"Renamed","kind":"other"}}),
        );
        assert_eq!(r["result"]["ok"], true);
        let r = call(
            &s,
            json!({"jsonrpc":"2.0","id":5,"method":"updateDevice","params":{"device_id":id,"kind":"toaster"}}),
        );
        assert_eq!(r["error"]["code"], -32602);
        let r = call(&s, json!({"jsonrpc":"2.0","id":6,"method":"listNearby"}));
        assert_eq!(r["result"], json!([]));
        let r = call(
            &s,
            json!({"jsonrpc":"2.0","id":7,"method":"startPairing","params":{"kind":"watch"}}),
        );
        assert!(r["result"]["qr_uri"]
            .as_str()
            .unwrap()
            .starts_with("stepaway://pair?"));
        let r = call(
            &s,
            json!({"jsonrpc":"2.0","id":8,"method":"startPairing","params":{"kind":"toaster"}}),
        );
        assert_eq!(r["error"]["code"], -32602);
        let r = call(&s, json!({"jsonrpc":"2.0","id":9,"method":"status"}));
        assert_eq!(r["result"]["presence_rule"], "any");
    }

    #[tokio::test]
    async fn listers_without_registration_return_empty_lists() {
        let s = shared();
        for m in ["listServices", "listApps"] {
            let r = handle_line_async(&s, &format!(r#"{{"jsonrpc":"2.0","id":1,"method":"{m}"}}"#))
                .await
                .unwrap();
            assert_eq!(
                serde_json::from_str::<Value>(&r).unwrap()["result"],
                json!([])
            );
        }
    }

    #[tokio::test]
    async fn connection_roundtrip_over_duplex() {
        let s = shared();
        let (client, server) = tokio::io::duplex(4096);
        let (sr, sw) = tokio::io::split(server);
        tokio::spawn(serve_connection(sr, sw, s));
        let (cr, mut cw) = tokio::io::split(client);
        cw.write_all(b"{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"status\"}\n")
            .await
            .unwrap();
        let mut lines = BufReader::new(cr).lines();
        let l = lines.next_line().await.unwrap().unwrap();
        let v: Value = serde_json::from_str(&l).unwrap();
        assert_eq!(v["id"], 7);
    }
}
