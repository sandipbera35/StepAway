//! Needs a real logind session; run with `cargo test -p stepaway-os -- --ignored`.
//! Read-only: never locks or unlocks.
#![cfg(target_os = "linux")]

use stepaway_os::{logind::LogindBackend, LockBackend};

#[tokio::test]
#[ignore = "needs a live logind session"]
async fn reads_locked_hint() {
    let b = LogindBackend::connect().await.unwrap();
    assert!(!b.is_locked().await.unwrap(), "session unexpectedly locked");
}
