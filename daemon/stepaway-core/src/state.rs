//! Presence state machine (docs/plan.md §9). Pure: time is injected, actions are returned.
//!
//! Safety rules enforced here:
//! - default is lock-only; unlock needs `unlock_enabled`;
//! - only a lock this machine triggered can be unlocked by it;
//! - unlock needs a freshly authenticated sample, never just a keep-alive;
//! - no unlock until `unlock_allowed` (false after boot until the first user login/unlock).

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum State {
    Unknown,
    Near,
    Leaving,
    Away,
    /// Locked by us.
    Locked,
    /// User unlocked manually while the device was away; do not re-lock until it returns.
    Override,
}

/// A reason unlock is not happening (see `Machine::unlock_block`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UnlockBlock {
    /// The user has not turned unlock on.
    Disabled,
    /// Protection is paused.
    Paused,
    /// No unlock until the user has logged in once since the daemon started.
    FirstLogin,
    /// The session was locked by something other than StepAway.
    NotOurLock,
    /// No signal from a trusted device recently.
    NoSignal,
    /// The device is farther away than the return distance.
    TooFar,
    /// The device is close, but not for long enough yet.
    ReturnGrace,
    /// Close and long enough, but no freshly signed signal since arriving.
    NeedsFreshAuth,
    /// Unlock needs the phone to be unlocked and it is not. Only reported by the engine, which
    /// knows the phone's flag; the state machine itself does not see it.
    PhoneLocked,
}

impl UnlockBlock {
    /// Stable name used on the IPC interface.
    pub fn as_str(self) -> &'static str {
        match self {
            UnlockBlock::Disabled => "disabled",
            UnlockBlock::Paused => "paused",
            UnlockBlock::FirstLogin => "first_login",
            UnlockBlock::NotOurLock => "not_our_lock",
            UnlockBlock::NoSignal => "no_signal",
            UnlockBlock::TooFar => "too_far",
            UnlockBlock::ReturnGrace => "return_grace",
            UnlockBlock::NeedsFreshAuth => "needs_fresh_auth",
            UnlockBlock::PhoneLocked => "phone_locked",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Action {
    None,
    Lock,
    Unlock,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Input {
    /// A trusted advertisement was seen. `auth_fresh`: counter newer than the last accepted one.
    Sample {
        now_ms: u64,
        distance_m: f64,
        auth_fresh: bool,
    },
    /// Periodic clock tick (detects signal loss).
    Tick {
        now_ms: u64,
    },
    /// The session became locked (any cause).
    SessionLocked,
    /// The session was unlocked (by the user, or by us).
    SessionUnlocked {
        now_ms: u64,
    },
    /// The OS refused our lock request: retry instead of assuming we are locked.
    LockFailed,
    Pause,
    Resume,
}

#[derive(Debug, Clone, Copy)]
pub struct Config {
    pub lock_distance_m: f64,
    pub return_distance_m: f64,
    pub lock_grace_ms: u64,
    pub return_grace_ms: u64,
    pub lost_timeout_ms: u64,
    pub unlock_enabled: bool,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            lock_distance_m: 3.0,
            return_distance_m: 2.0,
            lock_grace_ms: 10_000,
            return_grace_ms: 3_000,
            lost_timeout_ms: 10_000,
            unlock_enabled: false,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Zone {
    Near,
    Far,
}

#[derive(Debug)]
pub struct Machine {
    cfg: Config,
    state: State,
    zone: Option<Zone>,
    zone_since: u64,
    last_seen: Option<u64>,
    last_auth: Option<u64>,
    paused: bool,
    unlock_allowed: bool,
    external_lock: bool,
}

impl Machine {
    /// `unlock_allowed` must be false when the daemon starts before the first login after boot.
    pub fn new(cfg: Config, unlock_allowed: bool) -> Self {
        Self {
            cfg,
            state: State::Unknown,
            zone: None,
            zone_since: 0,
            last_seen: None,
            last_auth: None,
            paused: false,
            unlock_allowed,
            external_lock: false,
        }
    }

    pub fn set_config(&mut self, cfg: Config) {
        self.cfg = cfg;
    }

    pub fn state(&self) -> State {
        self.state
    }

    /// Why the computer would not be unlocked right now, if it were locked by us: the first rule
    /// in the same order `evaluate` applies them. `None` means every condition is met. Used to
    /// tell the user why unlock is not happening; it never changes behaviour.
    pub fn unlock_block(&self, now_ms: u64) -> Option<UnlockBlock> {
        if !self.cfg.unlock_enabled {
            return Some(UnlockBlock::Disabled);
        }
        if self.paused {
            return Some(UnlockBlock::Paused);
        }
        if !self.unlock_allowed {
            return Some(UnlockBlock::FirstLogin);
        }
        if self.external_lock {
            return Some(UnlockBlock::NotOurLock);
        }
        let lost = match self.last_seen {
            None => true,
            Some(seen) => now_ms.saturating_sub(seen) > self.cfg.lost_timeout_ms,
        };
        if lost {
            return Some(UnlockBlock::NoSignal);
        }
        if self.zone != Some(Zone::Near) {
            return Some(UnlockBlock::TooFar);
        }
        if now_ms.saturating_sub(self.zone_since) < self.cfg.return_grace_ms {
            return Some(UnlockBlock::ReturnGrace);
        }
        if !self.last_auth.is_some_and(|a| a >= self.zone_since) {
            return Some(UnlockBlock::NeedsFreshAuth);
        }
        None
    }

    fn set_zone(&mut self, z: Zone, now: u64) {
        if self.zone != Some(z) {
            self.zone = Some(z);
            self.zone_since = now;
        }
    }

    pub fn step(&mut self, input: Input) -> Action {
        match input {
            Input::Sample {
                now_ms,
                distance_m,
                auth_fresh,
            } => {
                self.last_seen = Some(now_ms);
                if auth_fresh {
                    self.last_auth = Some(now_ms);
                }
                if distance_m > self.cfg.lock_distance_m {
                    self.set_zone(Zone::Far, now_ms);
                } else if distance_m <= self.cfg.return_distance_m {
                    self.set_zone(Zone::Near, now_ms);
                } // between thresholds: hysteresis keeps the previous zone
                self.evaluate(now_ms)
            }
            Input::Tick { now_ms } => {
                if let Some(seen) = self.last_seen {
                    if now_ms.saturating_sub(seen) > self.cfg.lost_timeout_ms {
                        self.set_zone(Zone::Far, seen + self.cfg.lost_timeout_ms);
                    }
                }
                self.evaluate(now_ms)
            }
            Input::SessionLocked => {
                if self.state != State::Locked {
                    self.external_lock = true;
                }
                Action::None
            }
            Input::SessionUnlocked { now_ms } => {
                self.unlock_allowed = true;
                self.external_lock = false;
                if self.state == State::Locked {
                    self.state = if self.zone == Some(Zone::Near) {
                        State::Near
                    } else {
                        State::Override
                    };
                    self.zone_since = self.zone_since.min(now_ms);
                }
                Action::None
            }
            Input::LockFailed => {
                if self.state == State::Locked {
                    self.state = State::Leaving;
                }
                Action::None
            }
            Input::Pause => {
                self.paused = true;
                Action::None
            }
            Input::Resume => {
                self.paused = false;
                Action::None
            }
        }
    }

    fn evaluate(&mut self, now: u64) -> Action {
        if self.paused {
            return Action::None;
        }
        match (self.state, self.zone) {
            (State::Unknown | State::Away | State::Override, Some(Zone::Near)) => {
                self.state = State::Near
            }
            (State::Unknown, Some(Zone::Far)) => self.state = State::Away,
            (State::Near, Some(Zone::Far)) => self.state = State::Leaving,
            (State::Leaving, Some(Zone::Near)) => self.state = State::Near,
            (State::Leaving, Some(Zone::Far))
                if now.saturating_sub(self.zone_since) >= self.cfg.lock_grace_ms =>
            {
                if self.external_lock {
                    // Already locked by someone else: nothing to do, and we must never unlock it.
                    self.state = State::Away;
                } else {
                    self.state = State::Locked;
                    return Action::Lock;
                }
            }
            (State::Locked, Some(Zone::Near)) => {
                let near_long_enough =
                    now.saturating_sub(self.zone_since) >= self.cfg.return_grace_ms;
                let authed = self.last_auth.is_some_and(|a| a >= self.zone_since);
                if self.cfg.unlock_enabled && self.unlock_allowed && near_long_enough && authed {
                    self.state = State::Near;
                    return Action::Unlock;
                }
            }
            _ => {}
        }
        Action::None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(now_ms: u64, d: f64) -> Input {
        Input::Sample {
            now_ms,
            distance_m: d,
            auth_fresh: true,
        }
    }

    fn near_machine(cfg: Config) -> Machine {
        let mut m = Machine::new(cfg, true);
        m.step(s(0, 1.0));
        assert_eq!(m.state(), State::Near);
        m
    }

    #[test]
    fn locks_only_after_grace() {
        let mut m = near_machine(Config::default());
        assert_eq!(m.step(s(1_000, 5.0)), Action::None);
        assert_eq!(m.state(), State::Leaving);
        assert_eq!(m.step(s(10_999, 5.0)), Action::None);
        assert_eq!(m.step(s(11_000, 5.0)), Action::Lock);
        assert_eq!(m.state(), State::Locked);
    }

    #[test]
    fn returning_within_grace_cancels() {
        let mut m = near_machine(Config::default());
        m.step(s(1_000, 5.0));
        m.step(s(5_000, 1.0));
        assert_eq!(m.state(), State::Near);
        assert_eq!(m.step(s(30_000, 1.0)), Action::None);
    }

    #[test]
    fn hysteresis_no_flapping_between_thresholds() {
        let mut m = near_machine(Config::default());
        for t in 1..50 {
            assert_eq!(m.step(s(t * 1000, 2.5)), Action::None);
        }
        assert_eq!(m.state(), State::Near);
    }

    #[test]
    fn signal_loss_counts_as_away() {
        let mut m = near_machine(Config::default());
        m.step(Input::Tick { now_ms: 5_000 });
        assert_eq!(m.state(), State::Near);
        m.step(Input::Tick { now_ms: 11_000 });
        assert_eq!(m.state(), State::Leaving);
        assert_eq!(m.step(Input::Tick { now_ms: 21_000 }), Action::Lock);
    }

    #[test]
    fn default_config_never_unlocks() {
        let mut m = near_machine(Config::default());
        m.step(s(1_000, 5.0));
        m.step(s(11_000, 5.0));
        for t in 12..60 {
            assert_eq!(m.step(s(t * 1000, 0.5)), Action::None);
        }
        assert_eq!(m.state(), State::Locked);
    }

    fn locked_with_unlock(allowed: bool) -> Machine {
        let cfg = Config {
            unlock_enabled: true,
            ..Config::default()
        };
        let mut m = Machine::new(cfg, allowed);
        m.step(s(0, 1.0));
        m.step(s(1_000, 5.0));
        assert_eq!(m.step(s(11_000, 5.0)), Action::Lock);
        m
    }

    #[test]
    fn unlocks_after_return_grace_with_fresh_auth() {
        let mut m = locked_with_unlock(true);
        assert_eq!(m.step(s(20_000, 1.0)), Action::None);
        assert_eq!(m.step(s(22_999, 1.0)), Action::None);
        assert_eq!(m.step(s(23_000, 1.0)), Action::Unlock);
        assert_eq!(m.state(), State::Near);
    }

    #[test]
    fn keepalive_without_fresh_auth_never_unlocks() {
        let mut m = locked_with_unlock(true);
        for t in 20..60 {
            let i = Input::Sample {
                now_ms: t * 1000,
                distance_m: 0.5,
                auth_fresh: false,
            };
            assert_eq!(m.step(i), Action::None);
        }
        assert_eq!(m.step(s(61_000, 0.5)), Action::Unlock);
    }

    #[test]
    fn no_unlock_before_first_login() {
        let mut m = locked_with_unlock(false);
        for t in 20..60 {
            assert_eq!(m.step(s(t * 1000, 0.5)), Action::None);
        }
        assert_eq!(m.state(), State::Locked);
    }

    #[test]
    fn external_lock_is_never_unlocked() {
        let cfg = Config {
            unlock_enabled: true,
            ..Config::default()
        };
        let mut m = Machine::new(cfg, true);
        m.step(s(0, 1.0));
        m.step(Input::SessionLocked);
        m.step(s(1_000, 5.0));
        assert_eq!(m.step(s(11_000, 5.0)), Action::None);
        assert_eq!(m.state(), State::Away);
        for t in 12..40 {
            assert_eq!(m.step(s(t * 1000, 0.5)), Action::None);
        }
    }

    #[test]
    fn user_unlock_while_away_enters_override_and_does_not_relock() {
        let mut m = locked_with_unlock(true);
        m.step(Input::SessionUnlocked { now_ms: 15_000 });
        assert_eq!(m.state(), State::Override);
        for t in 16..60 {
            assert_eq!(m.step(s(t * 1000, 6.0)), Action::None);
        }
        m.step(s(61_000, 1.0));
        assert_eq!(m.state(), State::Near);
    }

    #[test]
    fn failed_lock_is_retried() {
        let mut m = near_machine(Config::default());
        m.step(s(1_000, 5.0));
        assert_eq!(m.step(s(11_000, 5.0)), Action::Lock);
        m.step(Input::LockFailed);
        assert_eq!(m.state(), State::Leaving);
        assert_eq!(m.step(s(12_000, 5.0)), Action::Lock);
    }

    #[test]
    fn paused_takes_no_action() {
        let mut m = near_machine(Config::default());
        m.step(Input::Pause);
        m.step(s(1_000, 9.0));
        assert_eq!(m.step(s(60_000, 9.0)), Action::None);
        m.step(Input::Resume);
        assert_eq!(m.state(), State::Near);
    }

    #[test]
    fn unlock_block_names_the_first_unmet_rule() {
        // default config: unlock is off
        let m = Machine::new(Config::default(), true);
        assert_eq!(m.unlock_block(0), Some(UnlockBlock::Disabled));

        let m = locked_with_unlock(false);
        assert_eq!(m.unlock_block(20_000), Some(UnlockBlock::FirstLogin));

        let mut m = locked_with_unlock(true);
        // phone far away at the moment of locking
        m.step(Input::Tick { now_ms: 14_000 });
        assert_eq!(m.unlock_block(14_000), Some(UnlockBlock::TooFar));
        // no samples for longer than the lost timeout
        assert_eq!(m.unlock_block(60_000), Some(UnlockBlock::NoSignal));
        m.step(s(21_000, 1.0));
        assert_eq!(m.unlock_block(21_500), Some(UnlockBlock::ReturnGrace));
        assert_eq!(m.unlock_block(25_000), None);

        m.step(Input::Pause);
        assert_eq!(m.unlock_block(25_000), Some(UnlockBlock::Paused));
    }

    #[test]
    fn unlock_block_needs_fresh_auth_and_ignores_external_locks() {
        let mut m = locked_with_unlock(true);
        m.step(Input::Sample {
            now_ms: 21_000,
            distance_m: 1.0,
            auth_fresh: false,
        });
        assert_eq!(m.unlock_block(25_000), Some(UnlockBlock::NeedsFreshAuth));

        let cfg = Config {
            unlock_enabled: true,
            ..Config::default()
        };
        let mut m = Machine::new(cfg, true);
        m.step(Input::SessionLocked); // someone else locked it
        assert_eq!(m.unlock_block(0), Some(UnlockBlock::NotOurLock));
    }

    #[test]
    fn unlock_block_agrees_with_what_the_machine_does() {
        // Invariant: after any step, a machine that is still Locked must report a reason;
        // if it reported none, `evaluate` would already have unlocked it.
        let mut m = locked_with_unlock(true);
        let mut unlocked = false;
        for t in (15_000..40_000).step_by(500) {
            // far for the first 6 s, then close, with a fresh signed sample each time
            let d = if t < 21_000 { 8.0 } else { 1.0 };
            let a = m.step(s(t, d));
            if a == Action::Unlock {
                unlocked = true;
                break;
            }
            if m.state() == State::Locked {
                assert!(m.unlock_block(t).is_some(), "locked with no reason at {t}");
            }
        }
        assert!(
            unlocked,
            "the machine should unlock once the device is back"
        );
    }
}
