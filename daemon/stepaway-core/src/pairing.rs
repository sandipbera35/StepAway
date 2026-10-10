//! Pairing URI (protocol/SPEC.md §3): `stepaway://pair?v=1&id=<4 hex>&s=<b64url secret>&n=<name>`.

use crate::token::Secret;

const B64: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

fn b64url_encode(data: &[u8]) -> String {
    let mut out = String::new();
    for chunk in data.chunks(3) {
        let b = [
            chunk[0],
            *chunk.get(1).unwrap_or(&0),
            *chunk.get(2).unwrap_or(&0),
        ];
        let n = (u32::from(b[0]) << 16) | (u32::from(b[1]) << 8) | u32::from(b[2]);
        for i in 0..=chunk.len() {
            out.push(B64[((n >> (18 - 6 * i)) & 63) as usize] as char);
        }
    }
    out
}

fn b64url_decode(s: &str) -> Option<Vec<u8>> {
    let mut out = Vec::new();
    let (mut acc, mut bits) = (0u32, 0u32);
    for c in s.bytes() {
        let v = B64.iter().position(|&x| x == c)? as u32;
        acc = (acc << 6) | v;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push(((acc >> bits) & 0xFF) as u8);
        }
    }
    Some(out)
}

fn pct_encode(s: &str) -> String {
    let mut out = String::new();
    for b in s.bytes() {
        if b.is_ascii_alphanumeric() || matches!(b, b'-' | b'.' | b'_' | b'~') {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

fn pct_decode(s: &str) -> Option<String> {
    let b = s.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'%' {
            let h = std::str::from_utf8(b.get(i + 1..i + 3)?).ok()?;
            out.push(u8::from_str_radix(h, 16).ok()?);
            i += 3;
        } else {
            out.push(b[i]);
            i += 1;
        }
    }
    String::from_utf8(out).ok()
}

/// Build the URI shown as a QR code. Contains the secret: never log it.
pub fn pairing_uri(device_id: u16, secret: &Secret, desktop_name: &str) -> String {
    format!(
        "stepaway://pair?v=1&id={device_id:04x}&s={}&n={}",
        b64url_encode(secret.as_bytes()),
        pct_encode(desktop_name)
    )
}

#[derive(Debug)]
pub struct Pairing {
    pub device_id: u16,
    pub secret: Secret,
    pub desktop_name: String,
}

pub fn parse_pairing_uri(uri: &str) -> Option<Pairing> {
    let q = uri.strip_prefix("stepaway://pair?")?;
    let (mut v, mut id, mut s, mut n) = (None, None, None, None);
    for kv in q.split('&') {
        let (k, val) = kv.split_once('=')?;
        match k {
            "v" => v = Some(val),
            "id" => id = Some(val),
            "s" => s = Some(val),
            "n" => n = Some(val),
            _ => {}
        }
    }
    if v? != "1" {
        return None;
    }
    let id = id?;
    if id.len() != 4 {
        return None;
    }
    let bytes = b64url_decode(s?)?;
    Some(Pairing {
        device_id: u16::from_str_radix(id, 16).ok()?,
        secret: Secret::new(<[u8; 32]>::try_from(bytes.as_slice()).ok()?),
        desktop_name: pct_decode(n.unwrap_or(""))?,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::Deserialize;

    #[derive(Deserialize)]
    struct Case {
        name: String,
        secret_hex: String,
        device_id: u16,
        desktop_name: String,
        uri: String,
    }
    #[derive(Deserialize)]
    struct File {
        pairing: Vec<Case>,
    }

    #[test]
    fn matches_shared_vectors_both_ways() {
        let f: File =
            serde_json::from_str(include_str!("../../../protocol/test-vectors.json")).unwrap();
        for c in f.pairing {
            let raw = hex::decode(&c.secret_hex).unwrap();
            let secret = Secret::new(<[u8; 32]>::try_from(raw.as_slice()).unwrap());
            assert_eq!(
                pairing_uri(c.device_id, &secret, &c.desktop_name),
                c.uri,
                "{}",
                c.name
            );
            let p = parse_pairing_uri(&c.uri).unwrap();
            assert_eq!(p.device_id, c.device_id);
            assert_eq!(p.secret.as_bytes(), secret.as_bytes());
            assert_eq!(p.desktop_name, c.desktop_name);
        }
    }

    #[test]
    fn rejects_garbage() {
        assert!(parse_pairing_uri("https://example.com").is_none());
        assert!(parse_pairing_uri("stepaway://pair?v=2&id=0001&s=AAAA").is_none());
        assert!(parse_pairing_uri("stepaway://pair?v=1&id=0001&s=AAAA").is_none());
        assert!(parse_pairing_uri("stepaway://pair?v=1&id=01&s=AAAA").is_none());
    }
}
