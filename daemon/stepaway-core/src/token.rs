//! Rotating advertisement token (protocol/SPEC.md §1-2). Pure logic, time is injected.

use hmac::{Hmac, Mac};
use sha2::Sha256;
use subtle::ConstantTimeEq;
use thiserror::Error;

/// 128-bit service UUID carried in the advertisement, in canonical (big-endian) order.
pub const SERVICE_UUID: [u8; 16] = [
    0xc0, 0xde, 0x57, 0xe9, 0xa4, 0xa7, 0x4b, 0x1d, 0x9c, 0x3e, 0x5a, 0x11, 0xa0, 0xca, 0x7e, 0x01,
];
pub const PAYLOAD_LEN: usize = 13;
/// The token changes every window; a returning phone is authenticated within one window.
pub const WINDOW_SECS: u64 = 10;
/// Accepted clock skew between phone and computer, in windows (+/- 30 s).
pub const SKEW_WINDOWS: u64 = 3;

/// `(window seconds, accepted skew in windows)` for a protocol version.
fn params(version: u8) -> Option<(u64, u64)> {
    match version {
        VERSION => Some((WINDOW_SECS, SKEW_WINDOWS)),
        LEGACY_VERSION => Some((30, 1)),
        _ => None,
    }
}
/// Current protocol version (10 s token window).
pub const VERSION: u8 = 2;
/// Legacy version (30 s window): still accepted so phones running an older app keep working.
pub const LEGACY_VERSION: u8 = 1;
/// Flag bit 0: companion device was unlocked when the token was made.
pub const FLAG_PHONE_UNLOCKED: u8 = 0x01;
const MAC_PREFIX: &[u8] = b"StepAway-adv-v1";
const VERIFY_PREFIX: &[u8] = b"StepAway-verify-v1";

type HmacSha256 = Hmac<Sha256>;

/// Pairing secret. `Debug` is redacted so it can never leak through logging.
#[derive(Clone)]
pub struct Secret([u8; 32]);

impl Secret {
    pub fn new(bytes: [u8; 32]) -> Self {
        Self(bytes)
    }

    pub fn as_bytes(&self) -> &[u8; 32] {
        &self.0
    }
}

impl std::fmt::Debug for Secret {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("Secret(<redacted>)")
    }
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum VerifyError {
    #[error("payload has wrong length")]
    BadLength,
    #[error("unsupported protocol version")]
    BadVersion,
    #[error("reserved flag bits set")]
    ReservedFlags,
    #[error("device id does not match")]
    WrongDevice,
    #[error("mac invalid or counter outside the accepted window")]
    BadMac,
    /// Same counter as the last accepted one: valid keep-alive, not a new authentication.
    #[error("counter equals last accepted counter")]
    Replay,
    #[error("counter older than last accepted counter")]
    Stale,
}

/// A successfully authenticated token.
#[derive(Debug, PartialEq, Eq)]
pub struct Accepted {
    pub counter: u64,
    pub flags: u8,
}

fn counter_for(unix_time: u64, window: u64) -> u64 {
    unix_time / window
}

fn mac_for(secret: &Secret, ver_flags: u8, device_id: u16, counter: u64) -> [u8; 8] {
    // HMAC accepts keys of any length, so new_from_slice cannot fail for a 32-byte key.
    let Ok(mut m) = HmacSha256::new_from_slice(&secret.0) else {
        return [0; 8];
    };
    m.update(MAC_PREFIX);
    m.update(&[ver_flags]);
    m.update(&device_id.to_be_bytes());
    m.update(&counter.to_be_bytes());
    let full = m.finalize().into_bytes();
    let mut out = [0u8; 8];
    out.copy_from_slice(&full[..8]);
    out
}

/// Build the 13-byte payload (current version) for `unix_time`. `flags` uses only the low nibble.
pub fn build_payload(
    secret: &Secret,
    device_id: u16,
    flags: u8,
    unix_time: u64,
) -> [u8; PAYLOAD_LEN] {
    build_payload_versioned(secret, VERSION, device_id, flags, unix_time)
}

/// Same, for a specific protocol version (used to test legacy phones). Unknown versions use the
/// current one.
pub fn build_payload_versioned(
    secret: &Secret,
    version: u8,
    device_id: u16,
    flags: u8,
    unix_time: u64,
) -> [u8; PAYLOAD_LEN] {
    let (version, (window, _)) = match params(version) {
        Some(p) => (version, p),
        None => (VERSION, (WINDOW_SECS, SKEW_WINDOWS)),
    };
    let ver_flags = (version << 4) | (flags & 0x0F);
    let counter = counter_for(unix_time, window);
    let mut p = [0u8; PAYLOAD_LEN];
    p[0] = ver_flags;
    p[1..3].copy_from_slice(&device_id.to_be_bytes());
    p[3..5].copy_from_slice(&((counter & 0xFFFF) as u16).to_be_bytes());
    p[5..].copy_from_slice(&mac_for(secret, ver_flags, device_id, counter));
    p
}

/// Verify a payload. Any error means "no trusted device seen" (never unlock).
pub fn verify(
    secret: &Secret,
    expected_device_id: u16,
    payload: &[u8],
    now_unix: u64,
    last_accepted: Option<u64>,
) -> Result<Accepted, VerifyError> {
    if payload.len() != PAYLOAD_LEN {
        return Err(VerifyError::BadLength);
    }
    let ver_flags = payload[0];
    let Some((window, skew)) = params(ver_flags >> 4) else {
        return Err(VerifyError::BadVersion);
    };
    if ver_flags & 0x0E != 0 {
        return Err(VerifyError::ReservedFlags);
    }
    let device_id = u16::from_be_bytes([payload[1], payload[2]]);
    if device_id != expected_device_id {
        return Err(VerifyError::WrongDevice);
    }
    let counter_lo = u16::from_be_bytes([payload[3], payload[4]]);
    let now = counter_for(now_unix, window);
    let mut matched = None;
    for c in now.saturating_sub(skew)..=now.saturating_add(skew) {
        if (c & 0xFFFF) as u16 != counter_lo {
            continue;
        }
        let expect = mac_for(secret, ver_flags, device_id, c);
        if bool::from(expect.ct_eq(&payload[5..])) {
            matched = Some(c);
        }
    }
    let counter = matched.ok_or(VerifyError::BadMac)?;
    match last_accepted {
        Some(last) if counter == last => Err(VerifyError::Replay),
        Some(last) if counter < last => Err(VerifyError::Stale),
        _ => Ok(Accepted {
            counter,
            flags: ver_flags & 0x0F,
        }),
    }
}

/// 6-digit code shown on both devices during pairing (SPEC §3).
pub fn verification_code(secret: &Secret) -> String {
    let Ok(mut m) = HmacSha256::new_from_slice(&secret.0) else {
        return String::from("000000");
    };
    m.update(VERIFY_PREFIX);
    let d = m.finalize().into_bytes();
    let n = u32::from_be_bytes([d[0], d[1], d[2], d[3]]) % 1_000_000;
    format!("{n:06}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::Deserialize;

    #[derive(Deserialize)]
    struct Vector {
        name: String,
        version: u8,
        secret_hex: String,
        device_id: u16,
        unix_time: u64,
        payload_hex: String,
        verification_code: String,
    }
    #[derive(Deserialize)]
    struct VerifyCase {
        name: String,
        secret_hex: String,
        device_id: u16,
        payload_hex: String,
        verifier_unix_time: u64,
        last_accepted_counter: Option<u64>,
        expect: String,
    }
    #[derive(Deserialize)]
    struct File {
        uuid: String,
        vectors: Vec<Vector>,
        verify: Vec<VerifyCase>,
    }

    fn secret(h: &str) -> Secret {
        let mut b = [0u8; 32];
        b.copy_from_slice(&hex::decode(h).unwrap());
        Secret::new(b)
    }
    fn file() -> File {
        let raw = include_str!("../../../protocol/test-vectors.json");
        serde_json::from_str(raw).unwrap()
    }

    #[test]
    fn uuid_matches_spec() {
        let u: String = hex::encode(SERVICE_UUID);
        let want = file().uuid.replace('-', "");
        assert_eq!(u, want);
    }

    #[test]
    fn payload_vectors() {
        for v in file().vectors {
            let p = build_payload_versioned(
                &secret(&v.secret_hex),
                v.version,
                v.device_id,
                0,
                v.unix_time,
            );
            assert_eq!(hex::encode(p), v.payload_hex, "{}", v.name);
            assert_eq!(
                verification_code(&secret(&v.secret_hex)),
                v.verification_code,
                "{}",
                v.name
            );
        }
    }

    #[test]
    fn verify_vectors() {
        for c in file().verify {
            let r = verify(
                &secret(&c.secret_hex),
                c.device_id,
                &hex::decode(&c.payload_hex).unwrap(),
                c.verifier_unix_time,
                c.last_accepted_counter,
            );
            assert_eq!(r.is_ok(), c.expect == "accept", "{}: {:?}", c.name, r);
        }
    }

    #[test]
    fn rejects_malformed() {
        let s = Secret::new([7; 32]);
        let good = build_payload(&s, 1, 0, 1000);
        assert_eq!(
            verify(&s, 1, &good[..12], 1000, None),
            Err(VerifyError::BadLength)
        );
        let mut v2 = good;
        v2[0] = 0x30;
        assert_eq!(verify(&s, 1, &v2, 1000, None), Err(VerifyError::BadVersion));
        let mut rf = good;
        rf[0] |= 0x02;
        assert_eq!(
            verify(&s, 1, &rf, 1000, None),
            Err(VerifyError::ReservedFlags)
        );
        assert_eq!(
            verify(&Secret::new([8; 32]), 1, &good, 1000, None),
            Err(VerifyError::BadMac)
        );
    }

    #[test]
    fn replay_vs_stale_and_flags() {
        let s = Secret::new([7; 32]);
        let p = build_payload(&s, 1, FLAG_PHONE_UNLOCKED, 3000);
        let c = 3000 / WINDOW_SECS; // the current version uses the 10 s window
        assert_eq!(verify(&s, 1, &p, 3000, Some(c)), Err(VerifyError::Replay));
        assert_eq!(
            verify(&s, 1, &p, 3000, Some(c + 1)),
            Err(VerifyError::Stale)
        );
        let ok = verify(&s, 1, &p, 3000, Some(c - 1)).unwrap();
        assert_eq!(
            ok,
            Accepted {
                counter: c,
                flags: FLAG_PHONE_UNLOCKED
            }
        );
    }

    #[test]
    fn secret_debug_is_redacted() {
        assert_eq!(format!("{:?}", Secret::new([1; 32])), "Secret(<redacted>)");
    }
}
