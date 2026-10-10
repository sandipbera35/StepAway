//! Pairing offers: how a device without a camera (a smartwatch) hands its secret to the computer.
//!
//! The device shows a 16-character code. The user types it on the computer. The device
//! broadcasts its secret encrypted with a key derived from that code, in small Bluetooth chunks;
//! the computer collects the chunks, decrypts them and stores the device. The code itself never
//! goes over the air, and with 80 bits it cannot be guessed offline from the broadcast.
//! See protocol/SPEC.md §3.1.

use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use hkdf::Hkdf;
use sha2::Sha256;

use crate::token::Secret;

/// Service UUID under which a device broadcasts its pairing offer (`c0de57e9-...-7e03`).
pub const OFFER_UUID: [u8; 16] = [
    0xc0, 0xde, 0x57, 0xe9, 0xa4, 0xa7, 0x4b, 0x1d, 0x9c, 0x3e, 0x5a, 0x11, 0xa0, 0xca, 0x7e, 0x03,
];
pub const CODE_LEN: usize = 10;
pub const NONCE_LEN: usize = 12;
const PLAIN_LEN: usize = 32 + 2 + 1;
const TAG_LEN: usize = 16;
pub const BLOB_LEN: usize = NONCE_LEN + PLAIN_LEN + TAG_LEN;
pub const CHUNK_DATA: usize = 11;
pub const CHUNK_COUNT: usize = 6;
pub const CHUNK_LEN: usize = 13;

const SALT: &[u8] = b"StepAway-pair-v1";
const AAD: &[u8] = b"StepAway-offer-v1";
/// Crockford base32: no I, L, O or U, so a code read off a small screen is hard to mistype.
const ALPHABET: &[u8; 32] = b"0123456789ABCDEFGHJKMNPQRSTVWXYZ";

/// The code as shown to the user: `XXXX-XXXX-XXXX-XXXX`.
pub fn encode_code(code: &[u8; CODE_LEN]) -> String {
    let mut out = String::with_capacity(19);
    let (mut acc, mut bits, mut n) = (0u32, 0u32, 0);
    for &b in code {
        acc = (acc << 8) | u32::from(b);
        bits += 8;
        while bits >= 5 {
            bits -= 5;
            if n > 0 && n % 4 == 0 {
                out.push('-');
            }
            out.push(ALPHABET[((acc >> bits) & 31) as usize] as char);
            n += 1;
        }
    }
    out
}

fn symbol(c: char) -> Option<u32> {
    let c = match c.to_ascii_uppercase() {
        'O' => '0',
        'I' | 'L' => '1',
        other => other,
    };
    ALPHABET
        .iter()
        .position(|&a| a as char == c)
        .map(|p| p as u32)
}

/// Parse what the user typed: any case, dashes and spaces ignored, easily confused letters fixed.
pub fn parse_code(text: &str) -> Option<[u8; CODE_LEN]> {
    let symbols: Vec<u32> = text
        .chars()
        .filter(|c| !matches!(c, '-' | ' ' | '\t'))
        .map(symbol)
        .collect::<Option<_>>()?;
    if symbols.len() != 16 {
        return None;
    }
    let mut out = [0u8; CODE_LEN];
    let (mut acc, mut bits, mut i) = (0u32, 0u32, 0);
    for s in symbols {
        acc = (acc << 5) | s;
        bits += 5;
        if bits >= 8 {
            bits -= 8;
            out[i] = ((acc >> bits) & 0xFF) as u8;
            i += 1;
        }
    }
    Some(out)
}

/// The encryption key for a code.
pub fn derive_key(code: &[u8; CODE_LEN]) -> [u8; 32] {
    let mut key = [0u8; 32];
    // 32 bytes is far below HKDF-SHA256's output limit, so this cannot fail
    let _ = Hkdf::<Sha256>::new(Some(SALT), code).expand(b"key", &mut key);
    key
}

/// What a device offers: its secret, the id it will use, and what kind of device it is.
#[derive(Debug)]
pub struct Opened {
    pub secret: Secret,
    pub device_id: u16,
    /// 0 phone, 1 tablet, 2 watch, 3 other
    pub kind: u8,
}

/// Encrypt an offer. `nonce` must be random and never reused with the same key.
pub fn seal(
    key: &[u8; 32],
    nonce: &[u8; NONCE_LEN],
    secret: &Secret,
    device_id: u16,
    kind: u8,
) -> [u8; BLOB_LEN] {
    let mut plain = [0u8; PLAIN_LEN];
    plain[..32].copy_from_slice(secret.as_bytes());
    plain[32..34].copy_from_slice(&device_id.to_be_bytes());
    plain[34] = kind;
    let mut out = [0u8; BLOB_LEN];
    out[..NONCE_LEN].copy_from_slice(nonce);
    // a 32-byte key and a 12-byte nonce are always valid, so neither step can fail
    if let Ok(cipher) = Aes256Gcm::new_from_slice(key) {
        if let Ok(ct) = cipher.encrypt(
            Nonce::from_slice(nonce),
            Payload {
                msg: &plain,
                aad: AAD,
            },
        ) {
            out[NONCE_LEN..].copy_from_slice(&ct);
        }
    }
    out
}

/// Decrypt an offer; `None` if the code was wrong or the data was damaged or forged.
pub fn open(key: &[u8; 32], blob: &[u8]) -> Option<Opened> {
    if blob.len() != BLOB_LEN {
        return None;
    }
    let cipher = Aes256Gcm::new_from_slice(key).ok()?;
    let plain = cipher
        .decrypt(
            Nonce::from_slice(&blob[..NONCE_LEN]),
            Payload {
                msg: &blob[NONCE_LEN..],
                aad: AAD,
            },
        )
        .ok()?;
    if plain.len() != PLAIN_LEN {
        return None;
    }
    let mut s = [0u8; 32];
    s.copy_from_slice(&plain[..32]);
    Some(Opened {
        secret: Secret::new(s),
        device_id: u16::from_be_bytes([plain[32], plain[33]]),
        kind: plain[34],
    })
}

/// Split a blob into the advertisement payloads that carry it:
/// `[index << 4 | count][session][11 data bytes]`, zero padded.
pub fn split_chunks(blob: &[u8; BLOB_LEN], session: u8) -> [[u8; CHUNK_LEN]; CHUNK_COUNT] {
    let mut chunks = [[0u8; CHUNK_LEN]; CHUNK_COUNT];
    for (i, chunk) in chunks.iter_mut().enumerate() {
        chunk[0] = ((i as u8) << 4) | CHUNK_COUNT as u8;
        chunk[1] = session;
        let from = i * CHUNK_DATA;
        let to = (from + CHUNK_DATA).min(BLOB_LEN);
        chunk[2..2 + (to - from)].copy_from_slice(&blob[from..to]);
    }
    chunks
}

/// Collects chunks of one offer. Chunks may arrive in any order, repeated, and from another
/// session (a different offer): a new session simply starts over.
#[derive(Debug, Default)]
pub struct Reassembler {
    session: Option<u8>,
    parts: [Option<[u8; CHUNK_DATA]>; CHUNK_COUNT],
}

impl Reassembler {
    /// Feed one chunk; returns the blob when all of its chunks have been seen.
    pub fn push(&mut self, chunk: &[u8; CHUNK_LEN]) -> Option<[u8; BLOB_LEN]> {
        let (index, count) = ((chunk[0] >> 4) as usize, (chunk[0] & 0x0F) as usize);
        if count != CHUNK_COUNT || index >= CHUNK_COUNT {
            return None;
        }
        if self.session != Some(chunk[1]) {
            *self = Self {
                session: Some(chunk[1]),
                ..Self::default()
            };
        }
        let mut data = [0u8; CHUNK_DATA];
        data.copy_from_slice(&chunk[2..]);
        self.parts[index] = Some(data);
        if self.parts.iter().any(Option::is_none) {
            return None;
        }
        let mut blob = [0u8; BLOB_LEN];
        for (i, part) in self.parts.iter().enumerate() {
            let from = i * CHUNK_DATA;
            let to = (from + CHUNK_DATA).min(BLOB_LEN);
            if let Some(p) = part {
                blob[from..to].copy_from_slice(&p[..to - from]);
            }
        }
        *self = Self::default();
        Some(blob)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn secret(b: u8) -> Secret {
        Secret::new([b; 32])
    }

    #[test]
    fn codes_round_trip_and_look_like_four_groups() {
        let code = [0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc, 0xde, 0xf0, 0x01, 0xff];
        let text = encode_code(&code);
        assert_eq!(text.len(), 19);
        assert_eq!(text.matches('-').count(), 3);
        assert_eq!(parse_code(&text), Some(code));
        for c in 0..=255u8 {
            let code = [c, c.wrapping_mul(3), 7, 9, c ^ 0x5a, 1, 2, 3, c, 255 - c];
            assert_eq!(parse_code(&encode_code(&code)), Some(code));
        }
    }

    #[test]
    fn typed_codes_are_forgiving_but_not_sloppy() {
        let code = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
        let t = encode_code(&code);
        assert_eq!(parse_code(&t.to_lowercase()), Some(code));
        assert_eq!(parse_code(&t.replace('-', " ")), Some(code));
        assert_eq!(parse_code(&t.replace('-', "")), Some(code));
        assert_eq!(
            parse_code("O0O0-0000-0000-0000"),
            parse_code("0000-0000-0000-0000"),
            "O is read as 0"
        );
        assert_eq!(
            parse_code("ILIL-0000-0000-0000"),
            parse_code("1111-0000-0000-0000"),
            "I and L are read as 1"
        );
        assert!(parse_code("").is_none());
        assert!(parse_code(&t[..t.len() - 1]).is_none(), "too short");
        assert!(parse_code(&format!("{t}0")).is_none(), "too long");
        assert!(
            parse_code("UUUU-0000-0000-0000").is_none(),
            "U is not in the alphabet"
        );
        assert!(parse_code("0000-0000-0000-000$").is_none());
    }

    #[test]
    fn seal_and_open_round_trip() {
        let key = derive_key(&[7; CODE_LEN]);
        let blob = seal(&key, &[9; NONCE_LEN], &secret(0x42), 0xBEEF, 2);
        let o = open(&key, &blob).unwrap();
        assert_eq!(
            (o.secret.as_bytes(), o.device_id, o.kind),
            (&[0x42; 32], 0xBEEF, 2)
        );
    }

    #[test]
    fn the_wrong_code_a_changed_byte_or_a_short_blob_all_fail() {
        let key = derive_key(&[7; CODE_LEN]);
        let blob = seal(&key, &[9; NONCE_LEN], &secret(1), 5, 0);
        assert!(
            open(&derive_key(&[8; CODE_LEN]), &blob).is_none(),
            "wrong code"
        );
        for i in 0..BLOB_LEN {
            let mut b = blob;
            b[i] ^= 1;
            assert!(
                open(&key, &b).is_none(),
                "tampering with byte {i} must be detected"
            );
        }
        assert!(open(&key, &blob[..BLOB_LEN - 1]).is_none());
    }

    #[test]
    fn chunks_reassemble_in_any_order_with_repeats() {
        let blob = seal(
            &derive_key(&[3; CODE_LEN]),
            &[1; NONCE_LEN],
            &secret(9),
            77,
            2,
        );
        let chunks = split_chunks(&blob, 0xAB);
        let mut r = Reassembler::default();
        for i in [3, 0, 3, 5, 1, 1, 4] {
            assert!(r.push(&chunks[i]).is_none());
        }
        assert_eq!(r.push(&chunks[2]), Some(blob));
        assert!(
            r.push(&chunks[0]).is_none(),
            "starts over after a complete offer"
        );
    }

    #[test]
    fn a_new_session_discards_half_received_chunks() {
        let a = seal(
            &derive_key(&[1; CODE_LEN]),
            &[1; NONCE_LEN],
            &secret(1),
            1,
            0,
        );
        let b = seal(
            &derive_key(&[1; CODE_LEN]),
            &[2; NONCE_LEN],
            &secret(2),
            2,
            0,
        );
        let (ca, cb) = (split_chunks(&a, 1), split_chunks(&b, 2));
        let mut r = Reassembler::default();
        for c in &ca[..3] {
            assert!(r.push(c).is_none());
        }
        for c in &cb[..5] {
            assert!(r.push(c).is_none());
        }
        assert_eq!(
            r.push(&cb[5]),
            Some(b),
            "chunks of the old session are not mixed in"
        );
    }

    #[derive(serde::Deserialize)]
    struct Vector {
        name: String,
        code_text: String,
        code_hex: String,
        key_hex: String,
        nonce_hex: String,
        secret_hex: String,
        device_id: u16,
        kind: u8,
        session: u8,
        blob_hex: String,
        chunks_hex: Vec<String>,
    }

    #[derive(serde::Deserialize)]
    struct File {
        offer_uuid: String,
        offer: Vec<Vector>,
    }

    fn arr<const N: usize>(h: &str) -> [u8; N] {
        let mut a = [0u8; N];
        a.copy_from_slice(&hex::decode(h).unwrap());
        a
    }

    #[test]
    fn matches_the_shared_test_vectors() {
        let f: File =
            serde_json::from_str(include_str!("../../../protocol/test-vectors.json")).unwrap();
        assert!(!f.offer.is_empty());
        assert_eq!(hex::encode(OFFER_UUID), f.offer_uuid.replace('-', ""));
        for v in f.offer {
            let code: [u8; CODE_LEN] = arr(&v.code_hex);
            assert_eq!(encode_code(&code), v.code_text, "{}", v.name);
            assert_eq!(parse_code(&v.code_text), Some(code), "{}", v.name);
            let key = derive_key(&code);
            assert_eq!(hex::encode(key), v.key_hex, "{}", v.name);
            let secret = Secret::new(arr(&v.secret_hex));
            let blob = seal(&key, &arr(&v.nonce_hex), &secret, v.device_id, v.kind);
            assert_eq!(hex::encode(blob), v.blob_hex, "{}", v.name);
            let chunks = split_chunks(&blob, v.session);
            let got: Vec<String> = chunks.iter().map(hex::encode).collect();
            assert_eq!(got, v.chunks_hex, "{}", v.name);
            let o = open(&key, &blob).unwrap();
            assert_eq!(
                (o.secret.as_bytes().to_vec(), o.device_id, o.kind),
                (hex::decode(&v.secret_hex).unwrap(), v.device_id, v.kind)
            );
        }
    }

    #[test]
    fn malformed_chunks_are_ignored() {
        let mut r = Reassembler::default();
        let mut bad = [0u8; CHUNK_LEN];
        bad[0] = (7 << 4) | CHUNK_COUNT as u8; // index out of range
        assert!(r.push(&bad).is_none());
        bad[0] = 3; // wrong count
        assert!(r.push(&bad).is_none());
    }
}
