#![allow(clippy::type_complexity)]
//! Prints the `offer` section of protocol/test-vectors.json. Run:
//! `cargo run -p stepaway-core --example gen_offer_vectors > /tmp/offer.json`
use stepaway_core::offer::*;
use stepaway_core::token::Secret;

fn main() {
    let cases: [(&str, [u8; CODE_LEN], [u8; 32], u16, u8, [u8; NONCE_LEN], u8); 2] = [
        (
            "watch_basic",
            [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
            core::array::from_fn(|i| i as u8),
            0x1234,
            2,
            core::array::from_fn(|i| 0xA0 + i as u8),
            0x5A,
        ),
        (
            "all_ff",
            [0xff; CODE_LEN],
            [0xff; 32],
            0xFFFF,
            0,
            [0; NONCE_LEN],
            0,
        ),
    ];
    let mut out = Vec::new();
    for (name, code, secret, id, kind, nonce, session) in cases {
        let key = derive_key(&code);
        let blob = seal(&key, &nonce, &Secret::new(secret), id, kind);
        let chunks = split_chunks(&blob, session);
        out.push(serde_json::json!({
            "name": name,
            "code_text": encode_code(&code),
            "code_hex": hex::encode(code),
            "key_hex": hex::encode(key),
            "nonce_hex": hex::encode(nonce),
            "secret_hex": hex::encode(secret),
            "device_id": id,
            "kind": kind,
            "session": session,
            "blob_hex": hex::encode(blob),
            "chunks_hex": chunks.iter().map(hex::encode).collect::<Vec<_>>(),
        }));
    }
    println!("{}", serde_json::to_string_pretty(&out).unwrap_or_default());
}
