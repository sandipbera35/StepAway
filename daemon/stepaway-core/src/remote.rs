//! Remote commands (protocol/SPEC.md §6). Pure logic, time is injected, nothing here does I/O.
//!
//! A phone far away asks the computer to do something through a relay that is not trusted: the
//! relay only carries bytes. The computer acts only on a command whose MAC verifies under a key
//! derived from the pairing secret, that is fresh, and whose nonce it has not seen. Anything else
//! is dropped. The only command is `Lock`; there is deliberately no remote unlock.

use std::collections::VecDeque;

use hkdf::Hkdf;
use hmac::{Hmac, Mac};
use sha2::Sha256;
use subtle::ConstantTimeEq;
use thiserror::Error;

use crate::token::Secret;

const MAC_PREFIX: &[u8] = b"StepAway-remote-v1";
pub const NONCE_LEN: usize = 16;
pub const MAC_LEN: usize = 32;
/// A command is accepted for this many seconds around the computer's clock.
pub const MAX_SKEW_SECS: u64 = 60;

type HmacSha256 = Hmac<Sha256>;

/// What the phone may ask for. Wire codes are fixed; unknown codes are rejected.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Command {
    Lock,
}

impl Command {
    pub fn code(self) -> u8 {
        match self {
            Command::Lock => 1,
        }
    }

    pub fn from_code(code: u8) -> Option<Self> {
        match code {
            1 => Some(Command::Lock),
            _ => None,
        }
    }
}

/// A command as it travels through the relay.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RemoteCommand {
    pub device_id: u16,
    pub command: u8,
    pub ts: u64,
    pub nonce: [u8; NONCE_LEN],
    pub mac: [u8; MAC_LEN],
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum RemoteError {
    #[error("command is for another device")]
    WrongDevice,
    #[error("unknown command")]
    UnknownCommand,
    #[error("timestamp outside the accepted window")]
    Stale,
    #[error("mac invalid")]
    BadMac,
    #[error("nonce already used")]
    Replay,
}

fn key(secret: &Secret) -> [u8; 32] {
    let mut out = [0u8; 32];
    // Expanding 32 bytes from HKDF-SHA256 cannot fail.
    if Hkdf::<Sha256>::new(Some(MAC_PREFIX), secret.as_bytes())
        .expand(b"cmd-key", &mut out)
        .is_err()
    {
        out = [0u8; 32];
    }
    out
}

fn mac_input(device_id: u16, command: u8, ts: u64, nonce: &[u8; NONCE_LEN]) -> Vec<u8> {
    let mut v = Vec::with_capacity(MAC_PREFIX.len() + 1 + 2 + 1 + 8 + NONCE_LEN);
    v.extend_from_slice(MAC_PREFIX);
    v.push(0);
    v.extend_from_slice(&device_id.to_be_bytes());
    v.push(command);
    v.extend_from_slice(&ts.to_be_bytes());
    v.extend_from_slice(nonce);
    v
}

fn compute_mac(secret: &Secret, input: &[u8]) -> [u8; MAC_LEN] {
    // HMAC accepts keys of any length, so `new_from_slice` cannot fail for a 32-byte key.
    let Ok(mut m) = HmacSha256::new_from_slice(&key(secret)) else {
        return [0u8; MAC_LEN];
    };
    m.update(input);
    m.finalize().into_bytes().into()
}

/// Builds a signed command. The phone does this; the computer uses it in tests.
pub fn sign(
    secret: &Secret,
    device_id: u16,
    command: Command,
    ts: u64,
    nonce: [u8; NONCE_LEN],
) -> RemoteCommand {
    let code = command.code();
    RemoteCommand {
        device_id,
        command: code,
        ts,
        nonce,
        mac: compute_mac(secret, &mac_input(device_id, code, ts, &nonce)),
    }
}

/// Checks everything except replay. `now` is the computer's Unix time in seconds.
pub fn verify(
    secret: &Secret,
    expected_device: u16,
    cmd: &RemoteCommand,
    now: u64,
) -> Result<Command, RemoteError> {
    if cmd.device_id != expected_device {
        return Err(RemoteError::WrongDevice);
    }
    // MAC first: nothing about the command is trusted (or reported) before it checks out.
    let want = compute_mac(
        secret,
        &mac_input(cmd.device_id, cmd.command, cmd.ts, &cmd.nonce),
    );
    if !bool::from(want.ct_eq(&cmd.mac)) {
        return Err(RemoteError::BadMac);
    }
    if cmd.ts.abs_diff(now) > MAX_SKEW_SECS {
        return Err(RemoteError::Stale);
    }
    Command::from_code(cmd.command).ok_or(RemoteError::UnknownCommand)
}

/// Remembers recent nonces so a captured command cannot be played again.
///
/// Only commands that passed [`verify`] may be recorded. The cache is in memory: after a restart
/// a command could be replayed for up to [`MAX_SKEW_SECS`]. That is harmless for `Lock`; it MUST
/// be persisted before any command with a side effect other than locking is added.
#[derive(Debug, Default)]
pub struct NonceCache {
    seen: VecDeque<([u8; NONCE_LEN], u64)>,
}

const MAX_NONCES: usize = 256;

impl NonceCache {
    pub fn new() -> Self {
        Self::default()
    }

    /// Records `nonce` (from a command stamped `ts`). `Err(Replay)` if it was already used.
    pub fn check_and_insert(
        &mut self,
        nonce: [u8; NONCE_LEN],
        ts: u64,
        now: u64,
    ) -> Result<(), RemoteError> {
        // Entries older than the acceptance window can no longer pass `verify`, so drop them.
        while let Some(&(_, t)) = self.seen.front() {
            if now.saturating_sub(t) > 2 * MAX_SKEW_SECS {
                self.seen.pop_front();
            } else {
                break;
            }
        }
        if self.seen.iter().any(|(n, _)| n == &nonce) {
            return Err(RemoteError::Replay);
        }
        if self.seen.len() >= MAX_NONCES {
            self.seen.pop_front();
        }
        self.seen.push_back((nonce, ts));
        Ok(())
    }
}

/// Verifies and de-duplicates in one step: the call a transport makes for every message.
pub fn accept(
    secret: &Secret,
    expected_device: u16,
    cmd: &RemoteCommand,
    now: u64,
    cache: &mut NonceCache,
) -> Result<Command, RemoteError> {
    let c = verify(secret, expected_device, cmd, now)?;
    cache.check_and_insert(cmd.nonce, cmd.ts, now)?;
    Ok(c)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::Deserialize;

    #[derive(Deserialize)]
    struct Vector {
        secret_hex: String,
        device_id: u16,
        cmd: u8,
        ts: u64,
        nonce_hex: String,
        key_hex: String,
        mac_input_hex: String,
        mac_hex: String,
    }

    #[derive(Deserialize)]
    struct File {
        remote: Vec<Vector>,
    }

    fn arr<const N: usize>(h: &str) -> [u8; N] {
        let mut a = [0u8; N];
        a.copy_from_slice(&hex::decode(h).unwrap());
        a
    }

    fn secret() -> Secret {
        Secret::new([7u8; 32])
    }

    fn cmd_at(ts: u64, n: u8) -> RemoteCommand {
        sign(&secret(), 9, Command::Lock, ts, [n; NONCE_LEN])
    }

    #[test]
    fn matches_the_shared_test_vectors() {
        let f: File =
            serde_json::from_str(include_str!("../../../protocol/test-vectors.json")).unwrap();
        assert!(!f.remote.is_empty());
        for v in f.remote {
            let s = Secret::new(arr(&v.secret_hex));
            assert_eq!(hex::encode(key(&s)), v.key_hex);
            let nonce: [u8; NONCE_LEN] = arr(&v.nonce_hex);
            assert_eq!(
                hex::encode(mac_input(v.device_id, v.cmd, v.ts, &nonce)),
                v.mac_input_hex
            );
            let c = sign(
                &s,
                v.device_id,
                Command::from_code(v.cmd).unwrap(),
                v.ts,
                nonce,
            );
            assert_eq!(hex::encode(c.mac), v.mac_hex);
            assert_eq!(verify(&s, v.device_id, &c, v.ts), Ok(Command::Lock));
        }
    }

    #[test]
    fn a_fresh_signed_lock_is_accepted() {
        let c = cmd_at(1000, 1);
        assert_eq!(verify(&secret(), 9, &c, 1000), Ok(Command::Lock));
        assert_eq!(verify(&secret(), 9, &c, 1060), Ok(Command::Lock));
        assert_eq!(verify(&secret(), 9, &c, 940), Ok(Command::Lock));
    }

    #[test]
    fn old_or_future_commands_are_refused() {
        let c = cmd_at(1000, 1);
        assert_eq!(verify(&secret(), 9, &c, 1061), Err(RemoteError::Stale));
        assert_eq!(verify(&secret(), 9, &c, 939), Err(RemoteError::Stale));
    }

    #[test]
    fn a_wrong_secret_device_or_tampered_field_fails() {
        let c = cmd_at(1000, 1);
        assert_eq!(
            verify(&Secret::new([8u8; 32]), 9, &c, 1000),
            Err(RemoteError::BadMac)
        );
        assert_eq!(
            verify(&secret(), 10, &c, 1000),
            Err(RemoteError::WrongDevice)
        );
        for tamper in 0..4 {
            let mut t = c.clone();
            match tamper {
                0 => t.ts += 1,
                1 => t.nonce[0] ^= 1,
                2 => t.mac[31] ^= 1,
                _ => t.command = 2,
            }
            assert_eq!(verify(&secret(), 9, &t, 1000), Err(RemoteError::BadMac));
        }
    }

    #[test]
    fn an_unknown_command_with_a_valid_mac_is_refused() {
        // A newer phone app asks for something this version does not know: do nothing.
        let nonce = [3u8; NONCE_LEN];
        let mut c = cmd_at(1000, 3);
        c.command = 99;
        c.mac = compute_mac(&secret(), &mac_input(9, 99, 1000, &nonce));
        assert_eq!(
            verify(&secret(), 9, &c, 1000),
            Err(RemoteError::UnknownCommand)
        );
    }

    #[test]
    fn the_beacon_key_and_the_command_key_differ() {
        // The remote key must never equal the secret used for the Bluetooth token.
        assert_ne!(&key(&secret()), secret().as_bytes());
    }

    #[test]
    fn a_replayed_command_is_refused_once_and_then_forgotten() {
        let mut cache = NonceCache::new();
        let c = cmd_at(1000, 1);
        assert_eq!(
            accept(&secret(), 9, &c, 1000, &mut cache),
            Ok(Command::Lock)
        );
        assert_eq!(
            accept(&secret(), 9, &c, 1001, &mut cache),
            Err(RemoteError::Replay)
        );
        // A different nonce is a different command.
        let d = cmd_at(1001, 2);
        assert_eq!(
            accept(&secret(), 9, &d, 1001, &mut cache),
            Ok(Command::Lock)
        );
    }

    #[test]
    fn a_failed_verification_does_not_burn_the_nonce() {
        let mut cache = NonceCache::new();
        let mut bad = cmd_at(1000, 1);
        bad.mac[0] ^= 1;
        assert_eq!(
            accept(&secret(), 9, &bad, 1000, &mut cache),
            Err(RemoteError::BadMac)
        );
        let good = cmd_at(1000, 1);
        assert_eq!(
            accept(&secret(), 9, &good, 1000, &mut cache),
            Ok(Command::Lock)
        );
    }

    #[test]
    fn the_cache_is_bounded_and_drops_old_entries() {
        let mut cache = NonceCache::new();
        for i in 0..300u32 {
            let mut n = [0u8; NONCE_LEN];
            n[..4].copy_from_slice(&i.to_be_bytes());
            cache.check_and_insert(n, 1000, 1000).unwrap();
        }
        assert!(cache.seen.len() <= MAX_NONCES);
        // Far in the future everything has expired.
        cache
            .check_and_insert([9u8; NONCE_LEN], 5000, 5000)
            .unwrap();
        assert_eq!(cache.seen.len(), 1);
    }
}
