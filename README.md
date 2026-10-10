# StepAway

Automatically lock your Linux or Windows computer when your paired Android phone or Wear OS watch moves away, and (optionally) unlock it when you return. Distance is estimated from Bluetooth LE signal strength. Everything is local: no accounts, no network, no telemetry.

## Status

| Part | State |
| --- | --- |
| Linux daemon + desktop app | Working; tested on Fedora 44 |
| Android app (paid, closed source, separate repository) | Working; tested on Android 14 |
| Windows | Compiles, **not tested** |
| Wear OS, tray icon, Flatpak/MSIX/F-Droid packaging | Not started |

## Features
- Locks when your phone is out of range (default 3 m) or switched off, Bluetooth is off or the app is closed.
- Optional unlock when the phone returns. Off by default; it only unlocks a lock StepAway made itself and never right after boot.
- Pairing by QR code with a verification code; signed, rotating tokens (no fixed ID to spoof).
- Calibration wizard, live signal graph, pause media and close chosen apps on lock.
- Android "Speed vs battery" setting (in the paid Android app) (Saver / Balanced / Fast).
- Built-in uninstaller (Settings → Uninstall): warns first, then removes the app, background service, startup entry, shortcuts and (optionally) your data, on Linux and Windows.

## Install
Download from the [Releases](../../releases) page:
- **Debian / Ubuntu:** `sudo apt install ./stepaway_<version>_amd64.deb` (or `arm64`).
- **Fedora / RHEL / openSUSE:** `sudo dnf install ./stepaway-<version>-1.x86_64.rpm` (or `aarch64`).
- **Any Linux:** `stepaway-linux-x64.tar.gz` or `stepaway-linux-arm64.tar.gz`, extract and run `./install.sh` (no root needed).
- **Android app:** a paid app, sold through app stores (not in these releases). The desktop app and service are free; the phone app is what they pair with.

Verify downloads with the `.sha256` files.

## Build from source
```bash
cd daemon && cargo test --workspace      # Rust daemon
cd desktop && flutter run -d linux       # desktop app
packaging/linux/build-release.sh         # Linux release archive
```
Publishing a release: push a tag such as `v0.1.0`; the *Release* workflow builds the Linux packages (x86-64 and arm64) and attaches them (the Android app is built from a private repository).

## Limits
Bluetooth signal strength is only a rough distance estimate; calibrate once. StepAway cannot tell if someone else holds your phone. See `SECURITY.md`.

## Layout
`daemon/` Rust daemon · `desktop/` Flutter UI · `ui/` shared widgets · `wear/` Wear OS · `windows-credprov/` Windows unlock (later) · `protocol/` spec + test vectors · `packaging/` packaging.

## Privacy and legal
StepAway collects nothing and never connects to the internet. Read the [privacy policy](PRIVACY.md) (also in both apps under About). Third-party licenses are in [THIRD_PARTY_LICENSES.txt](THIRD_PARTY_LICENSES.txt) and in the apps under About → Open-source licenses. Maintainers: `tools/version.sh set X.Y.Z` keeps every component's version in step; `tools/gen-privacy-md.py` and `tools/gen-rust-licenses.py` regenerate the generated documents.

## License
Everything in this repository is GPL-3.0-or-later. The Android app is proprietary and lives in a separate private repository; its history up to the tag `mobile-last-gpl` here is GPL and stays available. The name **StepAway**, its logo and the app identifier are not covered by the GPL: modified versions must use their own name and logo (see [TRADEMARK.md](TRADEMARK.md)). The source is open for anyone to read and audit; forks and copies must remain GPL-licensed. See `LICENSE`.
