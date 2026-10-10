//! Replays a recorded/synthetic RSSI trace through filter -> distance -> state machine.

use stepaway_core::distance::DistanceModel;
use stepaway_core::filter::RssiFilter;
use stepaway_core::state::{Action, Config, Input, Machine, State};

fn replay(csv: &str, cfg: Config) -> Vec<(u64, Action)> {
    let model = DistanceModel::default();
    let mut filter = RssiFilter::default();
    let mut m = Machine::new(cfg, true);
    let mut out = Vec::new();
    // A real phone's token changes every 10 s window; only a new window is a fresh authentication.
    let mut last_window = None;
    for line in csv.lines().skip(1) {
        let (t, r) = line.split_once(',').expect("csv row");
        let t: u64 = t.parse().expect("time");
        let rssi: f64 = r.parse().expect("rssi");
        let window = t / 10_000;
        let auth_fresh = last_window != Some(window);
        last_window = Some(window);
        let Some(f) = filter.push(rssi) else { continue };
        let a = m.step(Input::Sample {
            now_ms: t,
            distance_m: model.distance_m(f),
            auth_fresh,
        });
        if a != Action::None {
            out.push((t, a));
        }
    }
    out
}

const TRACE: &str = include_str!("traces/walk_away_and_back.csv");

#[test]
fn lock_only_locks_once_after_walking_away_and_never_unlocks() {
    let actions = replay(TRACE, Config::default());
    assert_eq!(actions.len(), 1, "{actions:?}");
    let (t, a) = actions[0];
    assert_eq!(a, Action::Lock);
    // Left at ~20 s, grace 10 s (+ filter lag): lock between 30 s and 36 s.
    assert!((30_000..=36_000).contains(&t), "locked at {t}");
}

#[test]
fn no_false_lock_while_sitting() {
    let sitting: String = TRACE.lines().take(41).collect::<Vec<_>>().join("\n");
    assert!(replay(&sitting, Config::default()).is_empty());
}

#[test]
fn unlock_enabled_unlocks_after_return() {
    let cfg = Config {
        unlock_enabled: true,
        ..Config::default()
    };
    let actions = replay(TRACE, cfg);
    assert_eq!(
        actions.iter().map(|a| a.1).collect::<Vec<_>>(),
        vec![Action::Lock, Action::Unlock]
    );
    assert!(actions[1].0 > 40_000);
}

#[test]
fn machine_starts_unknown() {
    assert_eq!(
        Machine::new(Config::default(), true).state(),
        State::Unknown
    );
}
