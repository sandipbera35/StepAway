//! Needs a desktop session bus; run with `cargo test -p stepaway-os -- --ignored --nocapture`.
//! Read-only: lists media players, never pauses or plays anything.
#![cfg(target_os = "linux")]

use stepaway_os::media::MprisMedia;

#[tokio::test]
#[ignore = "needs a live session bus"]
async fn lists_players() {
    let m = MprisMedia::connect().await.unwrap();
    let players = m.list_players().await.unwrap();
    println!("media players on the session bus: {players:?}");
}
