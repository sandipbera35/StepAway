# StepAway Protocol Specification — v1 (draft)

Shared by the Rust daemon, the Flutter/Kotlin companions and the Wear OS app. Test vectors: `test-vectors.json` (every implementation MUST pass them). Any change here requires updating the vectors and tests in every language.

Key words MUST / SHOULD follow RFC 2119. All multi-byte integers are **big-endian**.

## 1. Advertisement

The companion broadcasts a **non-connectable** BLE legacy advertisement containing one AD structure, *Service Data – 128-bit UUID* (type `0x21`):

```
 AD length (1B) = 0x1E (30 bytes follow: type + UUID + payload)
 AD type   (1B) = 0x21
 UUID      (16B, little-endian on air) = c0de57e9-a4a7-4b1d-9c3e-5a11a0ca7e01
 payload   (13B)
```

### 1.1 Byte budget (legacy advertising = 31 bytes of AD data)

| Item | Bytes |
|---|---|
| AD length + AD type | 2 |
| 128-bit service UUID | 16 |
| Payload | 13 |
| **Total** | **31** |

There is no room for a Flags AD structure. Android omits Flags for non-connectable advertisements; this MUST be verified on real hardware (Phase 1). If a stack adds Flags (3 bytes), the fallback is to move the payload to the scan response (requires active scanning on the desktop). A 16-bit UUID is NOT used because those are assigned by the Bluetooth SIG.

### 1.2 Payload (13 bytes)

| Offset | Size | Field |
|---|---|---|
| 0 | 1 | `ver_flags`: high nibble = protocol version (`2` current, `1` legacy), low nibble = flags (bit0: phone-unlocked, others MUST be 0) |
| 1 | 2 | `device_id` (assigned by the desktop at pairing) |
| 3 | 2 | `counter_lo`: low 16 bits of `counter` |
| 5 | 8 | `mac`: first 8 bytes of HMAC-SHA256 |

`counter = floor(unix_time_seconds / window)` (u64). **Version 2 (current):** `window = 10 s`, so a returning phone is authenticated with a fresh token within at most 10 s. **Version 1 (legacy):** `window = 30 s`. Companion apps MUST emit version 2; daemons SHOULD keep accepting version 1 so that phones running an older app still pair and work (the version nibble is part of the MAC input, so one version cannot be relabelled as the other).

`mac = HMAC-SHA256(key = secret, msg)[0..8]` where
`msg = "StepAway-adv-v1" (ASCII, 15B) | ver_flags (1B) | device_id (2B) | counter (8B)`.

The full 64-bit counter is authenticated even though only 16 bits are transmitted (wraps every ~7.6 days).

## 2. Verification (daemon)

Given a received payload and the paired `(secret, device_id, last_accepted_counter)`:

1. Reject unless the UUID matches, payload length is 13 and the version nibble is `1` or `2`; reject if reserved flag bits are set.
2. Reject if `device_id` differs from a paired device's ID.
3. Take `(window, skew)` from the version: v2 = (10 s, 3), v1 = (30 s, 1). For each candidate `c` in `{now-skew .. now+skew}` (now = `floor(local_unix_time/window)`, i.e. +/-30 s of clock skew in both versions) with `c & 0xFFFF == counter_lo`: recompute `mac` and compare in **constant time**.
4. No candidate matches → reject.
5. Reject if `c <= last_accepted_counter` (replay). Otherwise accept and persist `c` as the new `last_accepted_counter`.

Caveat: step 5 means repeated advertisements within the same 10 s window carry the same counter. The daemon therefore treats a payload equal to the *most recently accepted* one as a valid **keep-alive for RSSI purposes** (fresh RSSI sample) but not as a new authentication event. Only counters strictly greater than the last accepted one can drive **unlock**. Lock-only behaviour needs only the keep-alive path.

Any parse or verification failure means "no trusted device seen" (safe failure: never unlock).

## 3. Pairing

1. Desktop generates a 256-bit secret from the OS CSPRNG and a random 16-bit `device_id` (not already in use).
2. Desktop shows a QR code with this URI:
   `stepaway://pair?v=1&id=<device_id as 4 hex>&s=<secret, base64url, no padding>&n=<url-encoded desktop name>`
3. Desktop also shows a 6-digit **verification code**:
   `code = u32_be(HMAC-SHA256(secret, "StepAway-verify-v1")[0..4]) mod 1_000_000`, zero-padded. The phone shows the same code so the user can confirm both sides agree.
4. Phone stores the secret in Android Keystore-backed encrypted storage and starts advertising.
5. Pairing completes when the daemon verifies a valid token for the new `device_id`.

The QR contains the secret: it MUST only be shown on the desktop screen during pairing, expire after 5 minutes, and never be logged. Secrets MUST NOT appear in logs, the TOML config or IPC notifications. Wear OS pairing (no camera) is specified separately in a later revision (direct BLE GATT, no Google Play Services).

### 3.1 Pairing by code (devices without a camera, e.g. smartwatches)

A watch cannot scan the computer's QR code, so it shows a code instead and sends its secret over Bluetooth, encrypted with a key that only the code can produce.

1. **Code.** The device draws 10 random bytes and shows them as 16 Crockford-base32 characters, `XXXX-XXXX-XXXX-XXXX` (alphabet `0-9 A-Z` without `I L O U`; when typing, case, dashes and spaces are ignored and `O`/`I`/`L` are read as `0`/`1`/`1`). That is **80 bits**.
2. **The user types the code on the computer** (`startCodePairing`). The computer now listens for offers.
3. **Key.** `K = HKDF-SHA256(salt = "StepAway-pair-v1", ikm = code (10 bytes), info = "key", L = 32)`.
4. **Offer.** The device generates its secret `S` (32 bytes) and a device id (16 bits), then builds
   `blob = nonce (12 random bytes) | AES-256-GCM(K, nonce, aad = "StepAway-offer-v1", plaintext = S | device_id (2B BE) | kind (1B))`
   where `kind` is `0` phone, `1` tablet, `2` watch, `3` other. The blob is 63 bytes (12 + 35 + 16 tag).
5. **Broadcast.** The blob is cut into 6 chunks of 11 bytes (the last is zero padded) and each is advertised as service data under the offer UUID `c0de57e9-a4a7-4b1d-9c3e-5a11a0ca7e03`:
   `[index << 4 | 6][session][11 data bytes]` (13 bytes). `session` is one random byte per offer, so chunks of different offers are never mixed. The device cycles through the chunks until it is paired or the user cancels (the computer gives up after 5 minutes).
6. **Computer.** It collects the chunks in any order, decrypts the blob with `K` and stores the device (secret, id, kind). A wrong code, a damaged chunk or a forged offer fails the GCM check; after 3 failed offers the attempt is abandoned (`pairingFailed`). An id that is already in use is refused.
7. **Confirmation.** From then on the computer's beacon (see §1, UUID `...7e02`) carries a token made with `S`; a device that sees a beacon its new secret verifies knows the pairing worked.

Why this is safe: the code never goes over the air, so someone recording the offer must guess 80 bits to read the secret; nobody can forge an offer without the code; and an offer that has been captured is useless for any other pairing attempt because it only opens with its own code.

Test vectors: the `offer` section of `test-vectors.json` (code, key, nonce, blob and the six chunks) is checked by both the Rust and the Kotlin implementation.

## 4. IPC (JSON-RPC 2.0)

Transport: Unix socket `$XDG_RUNTIME_DIR/stepaway.sock` (mode `0600`) on Linux; named pipe `\\.\pipe\stepaway-<user>` (ACL: current user only) on Windows. One JSON object per line (newline-delimited). The server MUST reject peers whose UID/SID differs from the daemon's user.

Methods:

| Method | Params | Result |
|---|---|---|
| `status` | – | `{protocol: 1, state, paused, scanning, unlock_enabled, devices_present: [device_id], capabilities: {media, services}}` |
| `listDevices` | – | `[{device_id, name, kind, paired_at, last_seen, presence_only, address, calibrated}]` (never the secret) |
| `startPairing` | `{name?, kind?}` (`kind`: `phone`, `tablet`, `watch`, `other`; default `phone`) | `{qr_uri, verification_code, expires_at}` |
| `confirmPairing` | `{device_id}` | `{ok}` |
| `removeDevice` | `{device_id}` | `{ok}` |
| `getConfig` / `setConfig` | `{}` / partial config | config object |
| `startCalibration` | `{step: "near"\|"far", device_id?}` (with `device_id` only that device is measured and gets its own distance model) | `{ok}` |
| `startCodePairing` | `{code, name?}` | `{expires_at}`; errors with `-32602` if the code is not 16 valid characters. Success arrives as `devicePaired`, failure as `pairingFailed {reason}` |
| `listNearby` | – | `[{address, name, rssi}]` Bluetooth devices heard in the last 20 s that are not on the device list (for lock-only tracking) |
| `addPresenceDevice` | `{address, name?, kind?}` | `{device_id}`; the device can lock the computer but can **never** unlock it (it cannot prove who it is) |
| `updateDevice` | `{device_id, name?, kind?}` | `{ok}` |
| `pause` / `resume` | – | `{ok}` |
| `listServices` | – | `["name.service", ...]` running user services that can be put on the lock list (empty where unsupported) |

Notifications (server → client): `rssiUpdate {device_id, rssi, filtered_rssi, distance_m, t}`, `stateChanged {from, to, reason}`, `log {level, message}`.

### 4.0 Several devices

Any number of devices can be paired: phones, tablets, watches (anything that holds a secret and broadcasts the token of §1) plus lock-only plain Bluetooth devices. The config key `presence_rule` decides how they combine:

- `"any"` (default): you count as near while **at least one** device is near; the computer locks when all are away.
- `"all"`: you count as near only while **every** device is near; a device that is not heard for `lost_timeout_s` counts as away.

Only authenticated devices (secret + token) can ever unlock. A lock-only device is identified by its Bluetooth address, which can be spoofed or may rotate (phones and some watches randomise it), so it is weaker and meant for devices with a stable address such as fitness bands and earbuds.

### 4.1 Lock actions (config keys)

Besides locking, the daemon can run actions when **it** locks the computer (never for a lock the user made):

| Key | Type | Meaning |
|---|---|---|
| `lock_pause_media` | bool | Pause every playing media player (MPRIS on Linux, system media transport controls on Windows). |
| `unlock_resume_media` | bool | After unlock, resume only the players StepAway paused and that are still paused. |
| `lock_stop_services` | string[] (max 32) | systemd *user* units (`*.service`) to stop on lock. Names must match `[A-Za-z0-9._:@\-]+\.service`, must not start with `-`, and must not be session-critical (`dbus*`, `systemd*`, `gnome-shell*`, `plasma*`, `pipewire*`, `xdg-desktop-portal*`, `stepawayd*`, ...). The daemon passes the name after `--` and never through a shell. |
| `unlock_start_services` | bool | After unlock, start again only the units StepAway stopped. |

Everything StepAway changes is remembered in memory so that only its own actions are undone; failures are logged and never block locking.

State names: `UNKNOWN`, `NEAR`, `LEAVING`, `AWAY`, `LOCKED`.

Errors use JSON-RPC codes; application codes: `-32001` pairing expired, `-32002` unknown device, `-32003` paused.

## 5. Test vectors

`test-vectors.json` contains:
- `vectors[]`: `secret_hex`, `device_id`, `unix_time` → `counter`, `hmac_input_hex`, `mac_hex`, `payload_hex`, `verification_code`.
- `pairing[]`: `secret_hex`, `device_id`, `desktop_name` → `uri` (id is 4 lowercase hex digits, secret base64url without padding, name percent-encoded with only `A-Za-z0-9-._~` unescaped).
- `verify[]`: a payload, the verifier's clock, the last accepted counter and the expected `accept`/`reject`.

Vectors were generated with a Python reference script and independently cross-checked with `openssl dgst -sha256 -mac HMAC`.
