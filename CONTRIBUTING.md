# Contributing

- No proprietary dependencies (no Firebase, Google Play Services, ML Kit, analytics). Every dependency needs an OSI-approved license; open an issue before adding one.
- No network access or telemetry in any component.
- Security-critical code (tokens, pairing, secret storage, unlock, IPC auth) needs unit tests. Never log secrets.
- Protocol changes must update `protocol/SPEC.md`, `protocol/test-vectors.json` and tests in every language.
- Rust: `cargo fmt --all`, `cargo clippy --all-targets -- -D warnings`, `cargo test --workspace`. Flutter: `flutter analyze`, `flutter test`.
- Use Conventional Commits (`feat:`, `fix:`, `docs:`, ...). Contributions are accepted under GPL-3.0-or-later.

## Sign-off (Developer Certificate of Origin)
Every commit must carry a `Signed-off-by: Your Name <email>` line (`git commit -s`). It states that
you wrote the change, or have the right to submit it, under GPL-3.0-or-later (see
https://developercertificate.org). The name and logo are not part of what you license: see
`TRADEMARK.md`. A fork must use its own name, icon and app identifier.
