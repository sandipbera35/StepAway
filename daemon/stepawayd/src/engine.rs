//! The daemon's brain: settings, paired devices, pairing, calibration and the state machine.
//! Synchronous and free of Bluetooth/OS calls: it returns `Effect`s for the runner to execute.

use std::collections::HashMap;
use std::path::PathBuf;

use serde_json::{json, Value};
use stepaway_ble::{Advertisement, OtherAdv};
use stepaway_core::calibration;
use stepaway_core::distance::DistanceModel;
use stepaway_core::filter::RssiFilter;
use stepaway_core::offer::{self, Reassembler};
use stepaway_core::pairing::pairing_uri;
use stepaway_core::state::{Action, Input, Machine, State, UnlockBlock};
use stepaway_core::token::{self, Secret, VerifyError};

use crate::config::Settings;
use crate::store::{valid_address, valid_kind, Device, Store};

pub const PAIRING_TTL_S: u64 = 300;
/// Time to walk into position before a calibration measurement starts.
pub const CALIBRATION_LEAD_MS: u64 = 5_000;
pub const CALIBRATION_MS: u64 = 10_000;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Effect {
    Lock,
    Unlock,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Event {
    Rssi {
        device_id: u16,
        rssi: i16,
        filtered: f64,
        distance_m: f64,
    },
    /// The distance the state machine acts on, after combining all paired devices.
    Presence {
        distance_m: f64,
    },
    State {
        from: State,
        to: State,
    },
    DevicePaired {
        device_id: u16,
        name: String,
    },
    /// A code-paired device (smartwatch) could not be paired.
    CodePairingFailed {
        reason: String,
    },
    Calibration {
        step: String,
        rssi: Option<f64>,
    },
    CalibrationDone {
        tx_power_1m: f64,
        n: f64,
        device_id: Option<u16>,
    },
    CalibrationFailed {
        reason: String,
    },
}

impl Event {
    /// JSON-RPC notification (SPEC §4).
    pub fn to_notification(&self, now_unix: u64) -> Value {
        let (method, params) = match self {
            Event::Rssi {
                device_id,
                rssi,
                filtered,
                distance_m,
            } => (
                "rssiUpdate",
                json!({"device_id": device_id, "rssi": rssi, "filtered_rssi": filtered, "distance_m": distance_m, "t": now_unix}),
            ),
            Event::Presence { distance_m } => (
                "presenceUpdate",
                json!({"distance_m": distance_m, "t": now_unix}),
            ),
            Event::State { from, to } => (
                "stateChanged",
                json!({"from": state_name(*from), "to": state_name(*to), "reason": "presence"}),
            ),
            Event::DevicePaired { device_id, name } => (
                "devicePaired",
                json!({"device_id": device_id, "name": name}),
            ),
            Event::CodePairingFailed { reason } => ("pairingFailed", json!({"reason": reason})),
            Event::Calibration { step, rssi } => (
                "calibrationStep",
                json!({"step": step, "median_rssi": rssi}),
            ),
            Event::CalibrationDone {
                tx_power_1m,
                n,
                device_id,
            } => (
                "calibrationDone",
                json!({"tx_power_1m": tx_power_1m, "path_loss_n": n, "device_id": device_id}),
            ),
            Event::CalibrationFailed { reason } => ("calibrationFailed", json!({"reason": reason})),
        };
        json!({"jsonrpc": "2.0", "method": method, "params": params})
    }
}

pub fn state_name(s: State) -> &'static str {
    match s {
        State::Unknown => "UNKNOWN",
        State::Near => "NEAR",
        State::Leaving => "LEAVING",
        State::Away => "AWAY",
        State::Locked => "LOCKED",
        State::Override => "OVERRIDE",
    }
}

#[derive(Debug, Default)]
pub struct Output {
    pub effects: Vec<Effect>,
    pub events: Vec<Event>,
}

struct Pending {
    device_id: u16,
    secret: Secret,
    name: String,
    kind: String,
    expires_unix: u64,
}

/// Waiting for a device to broadcast its pairing offer, protected by the code the user typed.
struct PendingCode {
    key: [u8; 32],
    name: Option<String>,
    expires_unix: u64,
    chunks: Reassembler,
    wrong_attempts: u8,
}

struct Calib {
    step: String,
    /// Only samples from this device count; `None` calibrates the shared default model.
    device: Option<u16>,
    started_ms: u64,
    samples: Vec<f64>,
}

/// Distance used for a device that has not been heard for a while.
const FAR_M: f64 = 1000.0;
/// How long a device stays in the "nearby" list after its last advertisement.
const NEARBY_TTL_S: u64 = 20;
const NEARBY_MAX: usize = 200;

struct Seen {
    distance_m: f64,
    last_ms: u64,
}

struct Nearby {
    name: Option<String>,
    rssi: i16,
    last_unix: u64,
}

/// A Bluetooth device that is not a StepAway device, offered for lock-only tracking.
#[derive(Debug, Clone, PartialEq)]
pub struct NearbyDevice {
    pub address: String,
    pub name: Option<String>,
    pub rssi: i16,
}

#[derive(Debug, thiserror::Error)]
pub enum EngineError {
    #[error("{0}")]
    Invalid(String),
    #[error("unknown device")]
    UnknownDevice,
}

pub struct Engine {
    settings: Settings,
    settings_path: Option<PathBuf>,
    store: Store,
    machine: Machine,
    model: DistanceModel,
    filters: HashMap<u16, RssiFilter>,
    presence: HashMap<u16, Seen>,
    nearby: HashMap<String, Nearby>,
    /// Flags of the latest verified token per device (bit 0: the phone is unlocked).
    flags: HashMap<u16, u8>,
    pending: Option<Pending>,
    pending_code: Option<PendingCode>,
    calib: Option<Calib>,
    calib_near: Option<f64>,
    paused: bool,
    session_locked: bool,
}

impl Engine {
    /// `unlock_allowed` must be false if the daemon starts while the session is still at the
    /// boot-time login screen.
    pub fn new(
        settings: Settings,
        settings_path: Option<PathBuf>,
        store: Store,
        unlock_allowed: bool,
    ) -> Self {
        let machine = Machine::new(settings.machine_config(), unlock_allowed);
        let model = settings.model();
        Self {
            settings,
            settings_path,
            store,
            machine,
            model,
            filters: HashMap::new(),
            presence: HashMap::new(),
            nearby: HashMap::new(),
            flags: HashMap::new(),
            pending: None,
            pending_code: None,
            calib: None,
            calib_near: None,
            paused: false,
            session_locked: false,
        }
    }

    pub fn settings(&self) -> &Settings {
        &self.settings
    }

    pub fn state(&self) -> State {
        self.machine.state()
    }

    /// Why unlock is not happening right now (see `Machine::unlock_block`).
    pub fn unlock_block(&self, now_ms: u64) -> Option<UnlockBlock> {
        match self.machine.unlock_block(now_ms) {
            // The machine only knows "no fresh signed signal"; with the phone-unlocked rule on,
            // that is more precisely "the phone is locked".
            Some(UnlockBlock::NeedsFreshAuth) if self.settings.unlock_requires_phone_unlocked => {
                Some(UnlockBlock::PhoneLocked)
            }
            other => other,
        }
    }

    pub fn paused(&self) -> bool {
        self.paused
    }

    pub fn devices(&self) -> &[Device] {
        self.store.list()
    }

    fn step(&mut self, input: Input, out: &mut Output) {
        let before = self.machine.state();
        match self.machine.step(input) {
            Action::Lock => out.effects.push(Effect::Lock),
            Action::Unlock => out.effects.push(Effect::Unlock),
            Action::None => {}
        }
        let after = self.machine.state();
        if before != after {
            out.events.push(Event::State {
                from: before,
                to: after,
            });
        }
    }

    /// The distance model for a device: its own calibration if it has one, else the shared one.
    pub fn model_for(&self, id: u16) -> DistanceModel {
        match self.store.get(id) {
            Some(d) => DistanceModel {
                tx_power_1m: d.tx_power_1m.unwrap_or(self.model.tx_power_1m),
                n: d.path_loss_n.unwrap_or(self.model.n),
            },
            None => self.model,
        }
    }

    /// One distance for the state machine from all paired devices, following `presence_rule`.
    /// `None` while no device has been heard recently (the machine's own timeout takes over).
    fn effective_distance(&self, now_ms: u64) -> Option<f64> {
        let timeout = self.settings.lost_timeout_s * 1000;
        let mut live = Vec::new();
        let mut missing = false;
        for d in self.store.list() {
            match self.presence.get(&d.device_id) {
                Some(p) if now_ms.saturating_sub(p.last_ms) <= timeout => live.push(p.distance_m),
                _ => missing = true,
            }
        }
        if live.is_empty() {
            return None;
        }
        if self.settings.presence_rule == "all" {
            if missing {
                return Some(FAR_M);
            }
            return live.into_iter().reduce(f64::max);
        }
        live.into_iter().reduce(f64::min)
    }

    /// Record a sample from one device and let the state machine act on the combined distance.
    fn feed(&mut self, id: u16, distance_m: f64, auth_fresh: bool, now_ms: u64, out: &mut Output) {
        self.presence.insert(
            id,
            Seen {
                distance_m,
                last_ms: now_ms,
            },
        );
        let Some(effective) = self.effective_distance(now_ms) else {
            return;
        };
        out.events.push(Event::Presence {
            distance_m: effective,
        });
        self.step(
            Input::Sample {
                now_ms,
                distance_m: effective,
                auth_fresh,
            },
            out,
        );
    }

    /// An advertisement from a Bluetooth device that is not a StepAway device.
    pub fn on_other(&mut self, adv: &OtherAdv, now_unix: u64, now_ms: u64) -> Output {
        let mut out = Output::default();
        if self.nearby.len() >= NEARBY_MAX {
            self.nearby
                .retain(|_, n| now_unix.saturating_sub(n.last_unix) <= NEARBY_TTL_S);
        }
        if self.nearby.len() < NEARBY_MAX || self.nearby.contains_key(&adv.id) {
            self.nearby.insert(
                adv.id.to_ascii_uppercase(),
                Nearby {
                    name: adv.name.clone(),
                    rssi: adv.rssi,
                    last_unix: now_unix,
                },
            );
        }
        let Some(dev) = self.store.list().iter().find(|d| {
            d.presence_only && d.address.as_deref() == Some(adv.id.to_ascii_uppercase().as_str())
        }) else {
            return out;
        };
        let id = dev.device_id;
        if let Some(d) = self.store.get_mut(id) {
            d.last_seen_unix = Some(now_unix);
        }
        let rssi = f64::from(adv.rssi);
        if let Some(c) = &mut self.calib {
            if c.device.is_none_or(|d| d == id)
                && now_ms.saturating_sub(c.started_ms) >= CALIBRATION_LEAD_MS
            {
                c.samples.push(rssi);
            }
        }
        let Some(filtered) = self.filters.entry(id).or_default().push(rssi) else {
            return out;
        };
        let distance_m = self.model_for(id).distance_m(filtered);
        out.events.push(Event::Rssi {
            device_id: id,
            rssi: adv.rssi,
            filtered,
            distance_m,
        });
        // never authenticated: it can lock the computer but never unlock it
        self.feed(id, distance_m, false, now_ms, &mut out);
        self.check_calibration(now_ms, &mut out);
        out
    }

    /// The beacon payload for this moment: a signed token for one authenticated device, rotating
    /// through all of them every token window. `None` when the beacon is off or nobody is paired.
    pub fn beacon_payload(&self, now_unix: u64) -> Option<[u8; token::PAYLOAD_LEN]> {
        if !self.settings.beacon_enabled {
            return None;
        }
        let paired: Vec<(u16, Secret)> = self
            .store
            .list()
            .iter()
            .filter(|d| !d.presence_only)
            .filter_map(|d| d.secret().map(|s| (d.device_id, s)))
            .collect();
        if paired.is_empty() {
            return None;
        }
        let window = now_unix / token::WINDOW_SECS;
        let (id, secret) = &paired[(window % paired.len() as u64) as usize];
        Some(token::build_payload(secret, *id, 0, now_unix))
    }

    /// Bluetooth devices seen in the last few seconds that are not yet on the device list.
    pub fn nearby_devices(&self, now_unix: u64) -> Vec<NearbyDevice> {
        let known: Vec<&str> = self
            .store
            .list()
            .iter()
            .filter_map(|d| d.address.as_deref())
            .collect();
        let mut v: Vec<NearbyDevice> = self
            .nearby
            .iter()
            .filter(|(addr, n)| {
                now_unix.saturating_sub(n.last_unix) <= NEARBY_TTL_S
                    && !known.contains(&addr.as_str())
            })
            .map(|(addr, n)| NearbyDevice {
                address: addr.clone(),
                name: n.name.clone(),
                rssi: n.rssi,
            })
            .collect();
        v.sort_by(|a, b| b.rssi.cmp(&a.rssi).then_with(|| a.address.cmp(&b.address)));
        v
    }

    /// Track a plain Bluetooth device (lock only). Returns its new device id.
    pub fn add_presence_device(
        &mut self,
        address: &str,
        name: &str,
        kind: &str,
        now_unix: u64,
    ) -> Result<u16, EngineError> {
        if !valid_address(address) {
            return Err(EngineError::Invalid("not a Bluetooth address".into()));
        }
        if !valid_kind(kind) {
            return Err(EngineError::Invalid("unknown device kind".into()));
        }
        let address = address.to_ascii_uppercase();
        if self
            .store
            .list()
            .iter()
            .any(|d| d.address.as_deref() == Some(address.as_str()))
        {
            return Err(EngineError::Invalid(
                "this device is already on the list".into(),
            ));
        }
        let name = name.trim();
        let name = if name.is_empty() {
            address.clone()
        } else {
            name.chars().take(64).collect()
        };
        let id = self.fresh_device_id()?;
        self.store
            .add(Device::presence_only(id, name, kind, &address, now_unix));
        self.save_store();
        Ok(id)
    }

    fn fresh_device_id(&self) -> Result<u16, EngineError> {
        let mut raw = [0u8; 2];
        getrandom::fill(&mut raw)
            .map_err(|e| EngineError::Invalid(format!("random source failed: {e}")))?;
        let mut id = u16::from_be_bytes(raw);
        while id == 0
            || self.store.get(id).is_some()
            || self.pending.as_ref().is_some_and(|p| p.device_id == id)
        {
            id = id.wrapping_add(1);
        }
        Ok(id)
    }

    /// Rename a device or change its kind.
    pub fn update_device(
        &mut self,
        id: u16,
        name: Option<&str>,
        kind: Option<&str>,
    ) -> Result<(), EngineError> {
        if let Some(k) = kind {
            if !valid_kind(k) {
                return Err(EngineError::Invalid("unknown device kind".into()));
            }
        }
        let d = self.store.get_mut(id).ok_or(EngineError::UnknownDevice)?;
        if let Some(n) = name.map(str::trim).filter(|n| !n.is_empty()) {
            d.name = n.chars().take(64).collect();
        }
        if let Some(k) = kind {
            d.kind = k.to_owned();
        }
        self.save_store();
        Ok(())
    }

    pub fn on_advertisement(&mut self, adv: &Advertisement, now_unix: u64, now_ms: u64) -> Output {
        let mut out = Output::default();
        let p = &adv.payload;
        let id = u16::from_be_bytes([p[1], p[2]]);

        if let Some(pend) = &self.pending {
            if now_unix > pend.expires_unix {
                self.pending = None;
            } else if let (true, Ok(accepted)) = (
                pend.device_id == id,
                token::verify(&pend.secret, id, p, now_unix, None),
            ) {
                if let Some(pend) = self.pending.take() {
                    // The counter's unit depends on the phone's protocol version (10 s or 30 s
                    // windows), so take it from the token that was just verified.
                    self.store.add(
                        Device::new(
                            id,
                            pend.name.clone(),
                            &pend.secret,
                            now_unix,
                            Some(accepted.counter),
                        )
                        .with_kind(&pend.kind),
                    );
                    self.save_store();
                    out.events.push(Event::DevicePaired {
                        device_id: id,
                        name: pend.name,
                    });
                }
            }
        }

        let Some(dev) = self.store.get(id) else {
            return out;
        };
        let Some(secret) = dev.secret() else {
            return out;
        };
        let auth_fresh = match token::verify(&secret, id, p, now_unix, dev.last_counter) {
            Ok(acc) => {
                if let Some(d) = self.store.get_mut(id) {
                    d.last_counter = Some(acc.counter);
                }
                self.save_store();
                self.flags.insert(id, acc.flags);
                // With the extra rule on, a token from a locked phone is only a keep-alive:
                // it can keep the computer unlocked but never unlocks it.
                !self.settings.unlock_requires_phone_unlocked
                    || acc.flags & token::FLAG_PHONE_UNLOCKED != 0
            }
            Err(VerifyError::Replay) => false, // same window: valid keep-alive
            Err(_) => return out,              // anything else: ignore (never unlock on doubt)
        };
        if let Some(d) = self.store.get_mut(id) {
            d.last_seen_unix = Some(now_unix);
        }

        let rssi = f64::from(adv.rssi);
        if let Some(c) = &mut self.calib {
            if c.device.is_none_or(|d| d == id)
                && now_ms.saturating_sub(c.started_ms) >= CALIBRATION_LEAD_MS
            {
                c.samples.push(rssi);
            }
        }
        let Some(filtered) = self.filters.entry(id).or_default().push(rssi) else {
            return out;
        };
        let distance_m = self.model_for(id).distance_m(filtered);
        out.events.push(Event::Rssi {
            device_id: id,
            rssi: adv.rssi,
            filtered,
            distance_m,
        });
        self.feed(id, distance_m, auth_fresh, now_ms, &mut out);
        self.check_calibration(now_ms, &mut out);
        out
    }

    pub fn on_tick(&mut self, now_ms: u64) -> Output {
        let mut out = Output::default();
        self.step(Input::Tick { now_ms }, &mut out);
        self.check_calibration(now_ms, &mut out);
        out
    }

    /// Report the session lock state seen by the OS; only transitions matter.
    pub fn on_session(&mut self, locked: bool, now_ms: u64) -> Output {
        let mut out = Output::default();
        if locked != self.session_locked {
            self.session_locked = locked;
            let input = if locked {
                Input::SessionLocked
            } else {
                Input::SessionUnlocked { now_ms }
            };
            self.step(input, &mut out);
        }
        out
    }

    pub fn on_lock_failed(&mut self) -> Output {
        let mut out = Output::default();
        self.step(Input::LockFailed, &mut out);
        out
    }

    pub fn set_paused(&mut self, paused: bool) {
        self.paused = paused;
        let mut sink = Output::default();
        self.step(if paused { Input::Pause } else { Input::Resume }, &mut sink);
    }

    pub fn start_pairing(
        &mut self,
        name: Option<String>,
        kind: Option<&str>,
        now_unix: u64,
    ) -> Result<(String, String, u64), EngineError> {
        let kind = kind.unwrap_or("phone");
        if !valid_kind(kind) {
            return Err(EngineError::Invalid("unknown device kind".into()));
        }
        let mut raw = [0u8; 34];
        getrandom::fill(&mut raw)
            .map_err(|e| EngineError::Invalid(format!("random source failed: {e}")))?;
        let mut sec = [0u8; 32];
        sec.copy_from_slice(&raw[..32]);
        let mut device_id = u16::from_be_bytes([raw[32], raw[33]]);
        while device_id == 0 || self.store.get(device_id).is_some() {
            device_id = device_id.wrapping_add(1);
        }
        let secret = Secret::new(sec);
        let desktop = self.settings.desktop_name.clone();
        let uri = pairing_uri(device_id, &secret, &desktop);
        let code = token::verification_code(&secret);
        let expires = now_unix + PAIRING_TTL_S;
        let name = name
            .filter(|n| !n.trim().is_empty())
            .unwrap_or_else(|| "Phone".into());
        self.pending = Some(Pending {
            device_id,
            secret,
            name,
            kind: kind.to_owned(),
            expires_unix: expires,
        });
        Ok((uri, code, expires))
    }

    pub fn cancel_pairing(&mut self) {
        self.pending = None;
        self.pending_code = None;
    }

    /// Start listening for a device that shows `code_text` (smartwatches). Returns when the
    /// attempt expires.
    pub fn start_code_pairing(
        &mut self,
        code_text: &str,
        name: Option<String>,
        now_unix: u64,
    ) -> Result<u64, EngineError> {
        let code = offer::parse_code(code_text)
            .ok_or_else(|| EngineError::Invalid("that code does not look right".into()))?;
        let expires = now_unix + PAIRING_TTL_S;
        self.pending_code = Some(PendingCode {
            key: offer::derive_key(&code),
            name: name.map(|n| n.trim().to_owned()).filter(|n| !n.is_empty()),
            expires_unix: expires,
            chunks: Reassembler::default(),
            wrong_attempts: 0,
        });
        Ok(expires)
    }

    /// A pairing-offer chunk was heard. When the offer is complete and the code opens it, the
    /// device is stored exactly as if it had been paired with a QR code.
    pub fn on_pairing_chunk(&mut self, chunk: &[u8; offer::CHUNK_LEN], now_unix: u64) -> Output {
        let mut out = Output::default();
        let Some(p) = &mut self.pending_code else {
            return out;
        };
        if now_unix > p.expires_unix {
            self.pending_code = None;
            return out;
        }
        let Some(blob) = p.chunks.push(chunk) else {
            return out;
        };
        let Some(opened) = offer::open(&p.key, &blob) else {
            p.wrong_attempts += 1;
            if p.wrong_attempts >= 3 {
                self.pending_code = None;
                out.events.push(Event::CodePairingFailed {
                    reason: "the code did not match; check it on the device and try again".into(),
                });
            }
            return out;
        };
        let Some(p) = self.pending_code.take() else {
            return out;
        };
        if opened.device_id == 0 || self.store.get(opened.device_id).is_some() {
            out.events.push(Event::CodePairingFailed {
                reason: "this device is already paired or its id is taken; try again".into(),
            });
            return out;
        }
        let kind = match opened.kind {
            0 => "phone",
            1 => "tablet",
            2 => "watch",
            _ => "other",
        };
        let name = p.name.unwrap_or_else(|| match kind {
            "watch" => "Smartwatch".to_owned(),
            "tablet" => "Tablet".to_owned(),
            "phone" => "Phone".to_owned(),
            _ => "Device".to_owned(),
        });
        self.store.add(
            Device::new(
                opened.device_id,
                name.clone(),
                &opened.secret,
                now_unix,
                None,
            )
            .with_kind(kind),
        );
        self.save_store();
        out.events.push(Event::DevicePaired {
            device_id: opened.device_id,
            name,
        });
        out
    }

    pub fn is_device_paired(&self, id: u16) -> bool {
        self.store.get(id).is_some()
    }

    pub fn remove_device(&mut self, id: u16) -> Result<(), EngineError> {
        if !self.store.remove(id) {
            return Err(EngineError::UnknownDevice);
        }
        self.filters.remove(&id);
        self.presence.remove(&id);
        self.flags.remove(&id);
        self.save_store();
        Ok(())
    }

    pub fn set_settings(&mut self, patch: &Value) -> Result<&Settings, EngineError> {
        let next = self
            .settings
            .with_patch(patch)
            .map_err(EngineError::Invalid)?;
        self.apply_settings(next);
        Ok(&self.settings)
    }

    fn apply_settings(&mut self, next: Settings) {
        self.machine.set_config(next.machine_config());
        self.model = next.model();
        self.settings = next;
        if let Some(p) = &self.settings_path {
            if let Err(e) = self.settings.save(p) {
                tracing::warn!("could not save settings: {e}");
            }
        }
    }

    #[cfg(test)]
    pub fn start_calibration(&mut self, step: &str, now_ms: u64) -> Result<(), EngineError> {
        self.start_calibration_for(step, None, now_ms)
    }

    /// Calibrate one device (its own distance model) or, with `None`, the shared default.
    pub fn start_calibration_for(
        &mut self,
        step: &str,
        device: Option<u16>,
        now_ms: u64,
    ) -> Result<(), EngineError> {
        if let Some(id) = device {
            if self.store.get(id).is_none() {
                return Err(EngineError::UnknownDevice);
            }
        }
        if step != "near" && step != "far" {
            return Err(EngineError::Invalid(
                "step must be \"near\" or \"far\"".into(),
            ));
        }
        if step == "far" && self.calib_near.is_none() {
            return Err(EngineError::Invalid("run the \"near\" step first".into()));
        }
        if step == "near" {
            self.calib_near = None;
        }
        self.calib = Some(Calib {
            step: step.into(),
            device,
            started_ms: now_ms,
            samples: Vec::new(),
        });
        Ok(())
    }

    fn check_calibration(&mut self, now_ms: u64, out: &mut Output) {
        let Some(c) = &self.calib else { return };
        if now_ms.saturating_sub(c.started_ms) < CALIBRATION_LEAD_MS + CALIBRATION_MS {
            return;
        }
        let Some(c) = self.calib.take() else { return };
        let Some(med) = calibration::median(&c.samples) else {
            out.events.push(Event::CalibrationFailed {
                reason: "no signal from the device during the measurement".into(),
            });
            return;
        };
        out.events.push(Event::Calibration {
            step: c.step.clone(),
            rssi: Some(med),
        });
        if c.step == "near" {
            self.calib_near = Some(med);
            return;
        }
        let Some(near) = self.calib_near.take() else {
            return;
        };
        match calibration::calibrate(near, med, self.settings.lock_distance_m) {
            Some(m) => {
                let mut next = self.settings.clone();
                next.calibrated = true;
                match c.device {
                    // one device: store its own model and leave the shared default alone
                    Some(id) => {
                        if let Some(d) = self.store.get_mut(id) {
                            d.tx_power_1m = Some(m.tx_power_1m);
                            d.path_loss_n = Some(m.n);
                        }
                        self.save_store();
                    }
                    None => {
                        next.tx_power_1m = m.tx_power_1m;
                        next.path_loss_n = m.n;
                    }
                }
                if next.validate().is_ok() {
                    self.apply_settings(next);
                    out.events.push(Event::CalibrationDone {
                        tx_power_1m: m.tx_power_1m,
                        n: m.n,
                        device_id: c.device,
                    });
                    return;
                }
                out.events.push(Event::CalibrationFailed {
                    reason: "measured values out of range".into(),
                });
            }
            None => out.events.push(Event::CalibrationFailed {
                reason: "the far reading was not weaker than the near reading; try again".into(),
            }),
        }
    }

    fn save_store(&self) {
        if let Err(e) = self.store.save() {
            tracing::warn!("could not save paired devices: {e}");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use stepaway_ble::OtherAdv;
    use stepaway_core::token::build_payload;

    const T0: u64 = 1_700_000_000;

    fn engine(unlock: bool) -> (Engine, Secret) {
        let secret = Secret::new([5; 32]);
        let mut store = Store::in_memory();
        store.add(Device::new(0x0102, "Phone".into(), &secret, T0, None));
        let s = Settings {
            unlock_enabled: unlock,
            ..Settings::default()
        };
        (Engine::new(s, None, store, true), secret)
    }

    fn adv(secret: &Secret, id: u16, t: u64, rssi: i16) -> Advertisement {
        Advertisement {
            rssi,
            payload: build_payload(secret, id, 0, t),
        }
    }

    /// RSSI giving ~0.6 m / ~8 m with the default model (-59 dBm at 1 m, n = 2).
    const NEAR: i16 = -55;
    const FAR: i16 = -77;

    #[test]
    fn walking_away_locks_once_and_never_unlocks_by_default() {
        let (mut e, s) = engine(false);
        let mut effects = Vec::new();
        for i in 0..80u64 {
            let rssi = if i < 20 { NEAR } else { FAR };
            let o = e.on_advertisement(&adv(&s, 0x0102, T0 + i, rssi), T0 + i, i * 1000);
            effects.extend(o.effects);
        }
        for i in 80..140u64 {
            let o = e.on_advertisement(&adv(&s, 0x0102, T0 + i, NEAR), T0 + i, i * 1000);
            effects.extend(o.effects);
        }
        assert_eq!(effects, vec![Effect::Lock]);
        assert_eq!(e.state(), State::Locked);
    }

    #[test]
    fn unlock_when_enabled_after_fresh_token() {
        let (mut e, s) = engine(true);
        let mut effects = Vec::new();
        for i in 0..140u64 {
            let rssi = if (20..80).contains(&i) { FAR } else { NEAR };
            effects.extend(
                e.on_advertisement(&adv(&s, 0x0102, T0 + i, rssi), T0 + i, i * 1000)
                    .effects,
            );
        }
        assert_eq!(effects, vec![Effect::Lock, Effect::Unlock]);
    }

    fn adv_flags(secret: &Secret, id: u16, t: u64, rssi: i16, flags: u8) -> Advertisement {
        Advertisement {
            rssi,
            payload: build_payload(secret, id, flags, t),
        }
    }

    fn walk_away_and_back(e: &mut Engine, s: &Secret, flags: u8) -> Vec<Effect> {
        let mut effects = Vec::new();
        for i in 0..140u64 {
            let rssi = if (20..80).contains(&i) { FAR } else { NEAR };
            // a new signed token every window (10 s): use distinct counters via the time
            let t = T0 + i * 10;
            effects.extend(
                e.on_advertisement(&adv_flags(s, 0x0102, t, rssi, flags), t, i * 1000)
                    .effects,
            );
        }
        effects
    }

    #[test]
    fn locked_phone_does_not_unlock_when_the_rule_is_on() {
        let (mut e, s) = engine(true);
        e.set_settings(&serde_json::json!({"unlock_requires_phone_unlocked": true}))
            .unwrap();
        let effects = walk_away_and_back(&mut e, &s, 0); // phone locked in the pocket
        assert_eq!(effects, vec![Effect::Lock], "must stay locked");
        assert_eq!(e.unlock_block(139_000), Some(UnlockBlock::PhoneLocked));
    }

    #[test]
    fn unlocked_phone_unlocks_when_the_rule_is_on() {
        let (mut e, s) = engine(true);
        e.set_settings(&serde_json::json!({"unlock_requires_phone_unlocked": true}))
            .unwrap();
        let effects = walk_away_and_back(&mut e, &s, token::FLAG_PHONE_UNLOCKED);
        assert_eq!(effects, vec![Effect::Lock, Effect::Unlock]);
    }

    #[test]
    fn locked_phone_still_unlocks_when_the_rule_is_off() {
        let (mut e, s) = engine(true);
        let effects = walk_away_and_back(&mut e, &s, 0);
        assert_eq!(effects, vec![Effect::Lock, Effect::Unlock]);
    }

    #[test]
    fn forged_or_unknown_adverts_are_ignored() {
        let (mut e, s) = engine(true);
        let bad = Secret::new([6; 32]);
        assert!(e
            .on_advertisement(&adv(&bad, 0x0102, T0, NEAR), T0, 0)
            .events
            .is_empty());
        assert!(e
            .on_advertisement(&adv(&s, 0x0999, T0, NEAR), T0, 0)
            .events
            .is_empty());
        assert_eq!(e.state(), State::Unknown);
    }

    #[test]
    fn replayed_old_counter_is_ignored_but_same_window_is_keepalive() {
        let (mut e, s) = engine(false);
        let first = adv(&s, 0x0102, T0 + 100, NEAR);
        assert!(!e.on_advertisement(&first, T0 + 100, 0).events.is_empty());
        // same window: keep-alive, still produces an RSSI event
        assert!(!e.on_advertisement(&first, T0 + 101, 1000).events.is_empty());
        // older window (inside the skew tolerance): stale -> ignored
        let old = adv(&s, 0x0102, T0 + 60, NEAR);
        assert!(e.on_advertisement(&old, T0 + 101, 2000).events.is_empty());
    }

    #[test]
    fn pairing_completes_with_valid_token_and_expires() {
        let (mut e, _) = engine(false);
        let (uri, code, exp) = e.start_pairing(Some("Moto".into()), None, T0).unwrap();
        assert!(uri.starts_with("stepaway://pair?v=1&id="));
        assert_eq!(code.len(), 6);
        assert_eq!(exp, T0 + PAIRING_TTL_S);
        let p = stepaway_core::pairing::parse_pairing_uri(&uri).unwrap();
        assert!(!e.is_device_paired(p.device_id));
        let o = e.on_advertisement(&adv(&p.secret, p.device_id, T0 + 5, NEAR), T0 + 5, 0);
        assert!(o
            .events
            .iter()
            .any(|ev| matches!(ev, Event::DevicePaired { .. })));
        assert!(e.is_device_paired(p.device_id));

        let (uri2, _, _) = e.start_pairing(None, None, T0).unwrap();
        let p2 = stepaway_core::pairing::parse_pairing_uri(&uri2).unwrap();
        let late = T0 + PAIRING_TTL_S + 1;
        e.on_advertisement(&adv(&p2.secret, p2.device_id, late, NEAR), late, 0);
        assert!(!e.is_device_paired(p2.device_id));
    }

    #[test]
    fn settings_patch_updates_machine_and_rejects_bad_values() {
        let (mut e, _) = engine(false);
        assert!(e.set_settings(&json!({"lock_distance_m": 5.0})).is_ok());
        assert_eq!(e.settings().lock_distance_m, 5.0);
        assert!(e.set_settings(&json!({"lock_distance_m": 0.1})).is_err());
        assert_eq!(e.settings().lock_distance_m, 5.0);
    }

    #[test]
    fn calibration_flow_updates_model() {
        let (mut e, s) = engine(false);
        e.start_calibration("near", 0).unwrap();
        assert!(
            e.start_calibration("far", 0).is_err(),
            "far needs a finished near step"
        );
        let mut done = false;
        let mut t = 0u64;
        while t <= CALIBRATION_LEAD_MS + CALIBRATION_MS + 1000 {
            e.on_advertisement(&adv(&s, 0x0102, T0 + t / 1000, -50), T0 + t / 1000, t);
            t += 500;
        }
        e.start_calibration("far", t).unwrap();
        let start = t;
        while t <= start + CALIBRATION_LEAD_MS + CALIBRATION_MS + 1000 {
            let o = e.on_advertisement(
                &adv(&s, 0x0102, T0 + 200 + t / 1000, -70),
                T0 + 200 + t / 1000,
                t,
            );
            done |= o
                .events
                .iter()
                .any(|ev| matches!(ev, Event::CalibrationDone { .. }));
            t += 500;
        }
        assert!(done);
        assert!(e.settings().calibrated);
        let m = e.settings().model();
        assert!((m.distance_m(-70.0) - e.settings().lock_distance_m).abs() < 1e-6);
    }

    #[test]
    fn samples_taken_while_walking_into_position_are_ignored() {
        let (mut e, s) = engine(false);
        e.start_calibration("near", 0).unwrap();
        // strong signal for the first 5 s (still walking), the real position afterwards
        for i in 0..(CALIBRATION_LEAD_MS / 500) {
            e.on_advertisement(&adv(&s, 0x0102, T0 + i / 2, -30), T0 + i / 2, i * 500);
        }
        let mut t = CALIBRATION_LEAD_MS;
        let mut near = None;
        while t <= CALIBRATION_LEAD_MS + CALIBRATION_MS + 1000 {
            let o = e.on_advertisement(&adv(&s, 0x0102, T0 + t / 1000, -52), T0 + t / 1000, t);
            for ev in o.events {
                if let Event::Calibration { rssi, .. } = ev {
                    near = rssi;
                }
            }
            t += 500;
        }
        assert_eq!(near, Some(-52.0));
    }

    #[test]
    fn phone_with_the_older_app_still_pairs_and_works() {
        let (mut e, _) = engine(false);
        let (uri, _, _) = e.start_pairing(Some("Old phone".into()), None, T0).unwrap();
        let p = stepaway_core::pairing::parse_pairing_uri(&uri).unwrap();
        let legacy = |t: u64| Advertisement {
            rssi: NEAR,
            payload: token::build_payload_versioned(
                &p.secret,
                token::LEGACY_VERSION,
                p.device_id,
                0,
                t,
            ),
        };
        let o = e.on_advertisement(&legacy(T0 + 5), T0 + 5, 0);
        assert!(o
            .events
            .iter()
            .any(|ev| matches!(ev, Event::DevicePaired { .. })));
        // later legacy tokens (new 30 s window) are accepted as fresh authentications
        let a2 = legacy(T0 + 45);
        let o = e.on_advertisement(&a2, T0 + 45, 40_000);
        assert!(o.events.iter().any(|ev| matches!(ev, Event::Rssi { .. })));
        assert_eq!(e.state(), State::Near);
    }

    #[test]
    fn pause_blocks_locking() {
        let (mut e, s) = engine(false);
        e.on_advertisement(&adv(&s, 0x0102, T0, NEAR), T0, 0);
        e.set_paused(true);
        let mut effects = Vec::new();
        for i in 1..60u64 {
            effects.extend(
                e.on_advertisement(&adv(&s, 0x0102, T0 + i, FAR), T0 + i, i * 1000)
                    .effects,
            );
        }
        assert!(effects.is_empty());
    }

    // ---- several devices, kinds and lock-only devices ----

    fn two_devices(rule: &str) -> (Engine, Secret, Secret) {
        let (a, b) = (Secret::new([5; 32]), Secret::new([6; 32]));
        let mut store = Store::in_memory();
        store.add(Device::new(0x0102, "Phone".into(), &a, T0, None));
        store.add(Device::new(0x0203, "Watch".into(), &b, T0, None).with_kind("watch"));
        let s = Settings {
            presence_rule: rule.into(),
            ..Settings::default()
        };
        (Engine::new(s, None, store, true), a, b)
    }

    fn feed2(
        e: &mut Engine,
        a: &Secret,
        b: &Secret,
        secs: std::ops::Range<u64>,
        phone: Option<i16>,
        watch: Option<i16>,
    ) -> Vec<Effect> {
        let mut fx = Vec::new();
        for i in secs {
            if let Some(r) = phone {
                fx.extend(
                    e.on_advertisement(&adv(a, 0x0102, T0 + i, r), T0 + i, i * 1000)
                        .effects,
                );
            }
            if let Some(r) = watch {
                fx.extend(
                    e.on_advertisement(&adv(b, 0x0203, T0 + i, r), T0 + i, i * 1000)
                        .effects,
                );
            }
        }
        fx
    }

    #[test]
    fn any_rule_stays_near_while_one_device_is_near() {
        let (mut e, a, b) = two_devices("any");
        // phone left on the desk, watch walks away: you are still "near" because the phone is
        let fx = feed2(&mut e, &a, &b, 0..60, Some(NEAR), Some(FAR));
        assert!(fx.is_empty(), "{fx:?}");
        assert_eq!(e.state(), State::Near);
    }

    #[test]
    fn any_rule_locks_when_every_device_is_away() {
        let (mut e, a, b) = two_devices("any");
        feed2(&mut e, &a, &b, 0..10, Some(NEAR), Some(NEAR));
        let fx = feed2(&mut e, &a, &b, 10..60, Some(FAR), Some(FAR));
        assert_eq!(fx, vec![Effect::Lock]);
    }

    #[test]
    fn all_rule_locks_when_any_device_leaves() {
        let (mut e, a, b) = two_devices("all");
        feed2(&mut e, &a, &b, 0..10, Some(NEAR), Some(NEAR));
        // the watch leaves while the phone stays on the desk
        let fx = feed2(&mut e, &a, &b, 10..60, Some(NEAR), Some(FAR));
        assert_eq!(fx, vec![Effect::Lock]);
    }

    #[test]
    fn all_rule_treats_a_silent_device_as_away() {
        let (mut e, a, b) = two_devices("all");
        feed2(&mut e, &a, &b, 0..10, Some(NEAR), Some(NEAR));
        // the watch stops transmitting (battery, out of range); the phone is still near
        let fx = feed2(&mut e, &a, &b, 10..60, Some(NEAR), None);
        assert_eq!(fx, vec![Effect::Lock]);
    }

    #[test]
    fn each_device_can_have_its_own_distance_calibration() {
        let (mut e, a, b) = two_devices("any");
        e.start_calibration_for("near", Some(0x0203), 0).unwrap();
        let mut t = 0u64;
        while t <= CALIBRATION_LEAD_MS + CALIBRATION_MS + 1000 {
            e.on_advertisement(&adv(&b, 0x0203, T0 + t / 1000, -40), T0 + t / 1000, t);
            e.on_advertisement(&adv(&a, 0x0102, T0 + t / 1000, -90), T0 + t / 1000, t); // other device is ignored
            t += 500;
        }
        e.start_calibration_for("far", Some(0x0203), t).unwrap();
        let start = t;
        let mut done = None;
        while t <= start + CALIBRATION_LEAD_MS + CALIBRATION_MS + 1000 {
            let o = e.on_advertisement(
                &adv(&b, 0x0203, T0 + 200 + t / 1000, -60),
                T0 + 200 + t / 1000,
                t,
            );
            for ev in o.events {
                if let Event::CalibrationDone { device_id, .. } = ev {
                    done = Some(device_id);
                }
            }
            t += 500;
        }
        assert_eq!(done, Some(Some(0x0203)));
        assert!(
            (e.model_for(0x0203).distance_m(-60.0) - e.settings().lock_distance_m).abs() < 1e-6
        );
        assert_eq!(
            e.model_for(0x0102),
            e.settings().model(),
            "the phone keeps the shared model"
        );
        assert!(e.settings().calibrated);
    }

    #[test]
    fn pairing_remembers_the_device_kind_and_rejects_unknown_kinds() {
        let (mut e, _) = engine(false);
        assert!(e.start_pairing(None, Some("toaster"), T0).is_err());
        let (uri, _, _) = e
            .start_pairing(Some("My watch".into()), Some("watch"), T0)
            .unwrap();
        let p = stepaway_core::pairing::parse_pairing_uri(&uri).unwrap();
        e.on_advertisement(&adv(&p.secret, p.device_id, T0 + 5, NEAR), T0 + 5, 0);
        assert_eq!(
            e.devices()
                .iter()
                .find(|d| d.device_id == p.device_id)
                .unwrap()
                .kind,
            "watch"
        );
    }

    fn other(id: &str, name: Option<&str>, rssi: i16) -> OtherAdv {
        OtherAdv {
            id: id.into(),
            name: name.map(str::to_owned),
            rssi,
        }
    }

    #[test]
    fn nearby_devices_are_listed_strongest_first_and_expire() {
        let (mut e, _) = engine(false);
        e.on_other(&other("aa:bb:cc:dd:ee:01", Some("Band"), -70), T0, 0);
        e.on_other(&other("AA:BB:CC:DD:EE:02", None, -50), T0, 0);
        let list = e.nearby_devices(T0 + 1);
        assert_eq!(
            list.iter().map(|n| n.address.as_str()).collect::<Vec<_>>(),
            ["AA:BB:CC:DD:EE:02", "AA:BB:CC:DD:EE:01"]
        );
        assert_eq!(list[1].name.as_deref(), Some("Band"));
        assert!(e.nearby_devices(T0 + NEARBY_TTL_S + 5).is_empty());
    }

    #[test]
    fn a_plain_bluetooth_device_can_lock_but_never_unlock() {
        let (mut e, _) = engine(true); // unlock is enabled
                                       // drop the authenticated phone so only the band matters
        e.remove_device(0x0102).unwrap();
        let id = e
            .add_presence_device("aa:bb:cc:dd:ee:03", "My band", "watch", T0)
            .unwrap();
        assert!(e.nearby_devices(T0).is_empty());
        let band = |rssi| other("AA:BB:CC:DD:EE:03", Some("My band"), rssi);
        let mut fx = Vec::new();
        for i in 0..20u64 {
            fx.extend(e.on_other(&band(NEAR), T0 + i, i * 1000).effects);
        }
        assert_eq!(e.state(), State::Near);
        for i in 20..80u64 {
            fx.extend(e.on_other(&band(FAR), T0 + i, i * 1000).effects);
        }
        for i in 80..160u64 {
            fx.extend(e.on_other(&band(NEAR), T0 + i, i * 1000).effects);
        }
        assert_eq!(
            fx,
            vec![Effect::Lock],
            "locks, and is never allowed to unlock: {fx:?}"
        );
        assert!(e
            .devices()
            .iter()
            .any(|d| d.device_id == id && d.presence_only));
    }

    #[test]
    fn presence_devices_are_validated_and_not_added_twice() {
        let (mut e, _) = engine(false);
        assert!(e
            .add_presence_device("not-an-address", "x", "watch", T0)
            .is_err());
        assert!(e
            .add_presence_device("AA:BB:CC:DD:EE:04", "x", "toaster", T0)
            .is_err());
        let id = e
            .add_presence_device("AA:BB:CC:DD:EE:04", "  ", "other", T0)
            .unwrap();
        assert_eq!(
            e.devices().iter().find(|d| d.device_id == id).unwrap().name,
            "AA:BB:CC:DD:EE:04",
            "blank names fall back to the address"
        );
        assert!(e
            .add_presence_device("aa:bb:cc:dd:ee:04", "again", "other", T0)
            .is_err());
    }

    #[test]
    fn devices_can_be_renamed_and_retyped() {
        let (mut e, _) = engine(false);
        e.update_device(0x0102, Some("  Sandip's phone "), Some("tablet"))
            .unwrap();
        let d = e.devices().iter().find(|d| d.device_id == 0x0102).unwrap();
        assert_eq!(
            (d.name.as_str(), d.kind.as_str()),
            ("Sandip's phone", "tablet")
        );
        assert!(e.update_device(0x0102, None, Some("toaster")).is_err());
        assert!(e.update_device(0x7777, Some("x"), None).is_err());
    }

    #[test]
    fn beacon_rotates_through_authenticated_devices_with_valid_tokens() {
        let (mut e, a, b) = two_devices("any");
        e.add_presence_device("AA:BB:CC:DD:EE:07", "Band", "other", T0)
            .unwrap();
        let mut seen = std::collections::HashSet::new();
        for w in 0..6u64 {
            let t = T0 + w * token::WINDOW_SECS;
            let p = e.beacon_payload(t).unwrap();
            let id = u16::from_be_bytes([p[1], p[2]]);
            let secret = if id == 0x0102 { &a } else { &b };
            assert!(
                token::verify(secret, id, &p, t, None).is_ok(),
                "the device can verify its own beacon"
            );
            seen.insert(id);
        }
        assert_eq!(
            seen.len(),
            2,
            "both paired devices get their turn, the lock-only band never"
        );
    }

    #[test]
    fn beacon_is_off_when_disabled_or_nobody_is_paired() {
        let (mut e, _) = engine(false);
        assert!(e.beacon_payload(T0).is_some());
        e.set_settings(&json!({"beacon_enabled": false})).unwrap();
        assert!(e.beacon_payload(T0).is_none());
        let empty = Engine::new(Settings::default(), None, Store::in_memory(), true);
        assert!(empty.beacon_payload(T0).is_none());
    }

    // ---- pairing by code (smartwatches) ----

    fn offer_chunks(
        code: &[u8; offer::CODE_LEN],
        secret: &Secret,
        id: u16,
        kind: u8,
        nonce: u8,
        session: u8,
    ) -> [[u8; offer::CHUNK_LEN]; offer::CHUNK_COUNT] {
        let blob = offer::seal(
            &offer::derive_key(code),
            &[nonce; offer::NONCE_LEN],
            secret,
            id,
            kind,
        );
        offer::split_chunks(&blob, session)
    }

    #[test]
    fn a_watch_pairs_by_code_and_then_authenticates_like_any_device() {
        let (mut e, _) = engine(false);
        let code = [9u8; offer::CODE_LEN];
        let secret = Secret::new([0x33; 32]);
        e.start_code_pairing(
            &offer::encode_code(&code).to_lowercase(),
            Some("My watch".into()),
            T0,
        )
        .unwrap();
        let mut events = Vec::new();
        for c in offer_chunks(&code, &secret, 0x0777, 2, 1, 5).iter().rev() {
            events.extend(e.on_pairing_chunk(c, T0 + 3).events);
        }
        assert!(
            events.iter().any(|ev| matches!(
                ev,
                Event::DevicePaired {
                    device_id: 0x0777,
                    ..
                }
            )),
            "{events:?}"
        );
        let d = e.devices().iter().find(|d| d.device_id == 0x0777).unwrap();
        assert_eq!((d.kind.as_str(), d.name.as_str()), ("watch", "My watch"));
        // the watch now advertises tokens made with the secret it sent
        let o = e.on_advertisement(&adv(&secret, 0x0777, T0 + 10, NEAR), T0 + 10, 10_000);
        assert!(o.events.iter().any(|ev| matches!(
            ev,
            Event::Rssi {
                device_id: 0x0777,
                ..
            }
        )));
    }

    #[test]
    fn a_wrong_code_never_pairs_and_gives_up_after_three_offers() {
        let (mut e, _) = engine(false);
        e.start_code_pairing(&offer::encode_code(&[1; offer::CODE_LEN]), None, T0)
            .unwrap();
        let mut failed = false;
        for n in 0..3u8 {
            for c in offer_chunks(
                &[2; offer::CODE_LEN],
                &Secret::new([4; 32]),
                0x0888,
                2,
                n,
                n,
            ) {
                failed |= e
                    .on_pairing_chunk(&c, T0 + 1)
                    .events
                    .iter()
                    .any(|ev| matches!(ev, Event::CodePairingFailed { .. }));
            }
        }
        assert!(failed);
        assert!(!e.is_device_paired(0x0888));
        // and it stopped listening: even a correct offer is ignored now
        for c in offer_chunks(
            &[1; offer::CODE_LEN],
            &Secret::new([4; 32]),
            0x0888,
            2,
            9,
            9,
        ) {
            e.on_pairing_chunk(&c, T0 + 2);
        }
        assert!(!e.is_device_paired(0x0888));
    }

    #[test]
    fn code_pairing_needs_a_valid_code_expires_and_can_be_cancelled() {
        let (mut e, _) = engine(false);
        assert!(e.start_code_pairing("nonsense", None, T0).is_err());
        let code = [5u8; offer::CODE_LEN];
        e.start_code_pairing(&offer::encode_code(&code), None, T0)
            .unwrap();
        for c in offer_chunks(&code, &Secret::new([6; 32]), 0x0999, 2, 1, 1) {
            e.on_pairing_chunk(&c, T0 + PAIRING_TTL_S + 1); // too late
        }
        assert!(!e.is_device_paired(0x0999));
        e.start_code_pairing(&offer::encode_code(&code), None, T0)
            .unwrap();
        e.cancel_pairing();
        for c in offer_chunks(&code, &Secret::new([6; 32]), 0x0999, 2, 1, 1) {
            e.on_pairing_chunk(&c, T0 + 1);
        }
        assert!(!e.is_device_paired(0x0999));
    }

    #[test]
    fn an_id_that_is_already_paired_is_refused() {
        let (mut e, _) = engine(false);
        let code = [5u8; offer::CODE_LEN];
        e.start_code_pairing(&offer::encode_code(&code), None, T0)
            .unwrap();
        let mut failed = false;
        for c in offer_chunks(&code, &Secret::new([6; 32]), 0x0102, 2, 1, 1) {
            failed |= e
                .on_pairing_chunk(&c, T0 + 1)
                .events
                .iter()
                .any(|ev| matches!(ev, Event::CodePairingFailed { .. }));
        }
        assert!(failed, "0x0102 belongs to the existing phone");
    }

    #[test]
    fn presence_rule_is_validated() {
        let (mut e, _) = engine(false);
        assert!(e.set_settings(&json!({"presence_rule": "all"})).is_ok());
        assert!(e.set_settings(&json!({"presence_rule": "some"})).is_err());
    }
}
