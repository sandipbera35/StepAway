//! Calibration: derive the distance model from two measured RSSI levels.

use crate::distance::DistanceModel;

pub const NEAR_DISTANCE_M: f64 = 0.5;

pub fn median(samples: &[f64]) -> Option<f64> {
    if samples.is_empty() {
        return None;
    }
    let mut v = samples.to_vec();
    v.sort_by(|a, b| a.total_cmp(b));
    Some(v[v.len() / 2])
}

/// `near_rssi`: median RSSI with the phone ~0.5 m away; `far_rssi`: median RSSI at
/// `far_distance_m` (the distance where the user wants the lock to trigger).
/// Returns None for nonsensical input (far not weaker than near, bad distances).
pub fn calibrate(near_rssi: f64, far_rssi: f64, far_distance_m: f64) -> Option<DistanceModel> {
    if far_distance_m.is_nan() || far_distance_m <= NEAR_DISTANCE_M || far_rssi >= near_rssi {
        return None;
    }
    // rssi(d) = tx - 10 n log10(d); solve the two measurements for tx and n.
    let span = (far_distance_m / NEAR_DISTANCE_M).log10();
    let n = ((near_rssi - far_rssi) / (10.0 * span)).clamp(1.5, 4.5);
    let tx_power_1m = near_rssi - 10.0 * n * (1.0 / NEAR_DISTANCE_M).log10();
    Some(DistanceModel { tx_power_1m, n })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recovers_known_model() {
        let truth = DistanceModel {
            tx_power_1m: -60.0,
            n: 2.4,
        };
        let near = -60.0 - 10.0 * 2.4 * 0.5f64.log10();
        let far = -60.0 - 10.0 * 2.4 * 3.0f64.log10();
        let m = calibrate(near, far, 3.0).unwrap();
        assert!((m.n - truth.n).abs() < 1e-9 && (m.tx_power_1m - truth.tx_power_1m).abs() < 1e-9);
        assert!((m.distance_m(far) - 3.0).abs() < 1e-9);
    }

    #[test]
    fn rejects_bad_input() {
        assert!(calibrate(-70.0, -60.0, 3.0).is_none());
        assert!(calibrate(-50.0, -70.0, 0.4).is_none());
    }

    #[test]
    fn clamps_exponent() {
        assert_eq!(calibrate(-50.0, -51.0, 3.0).unwrap().n, 1.5);
    }

    #[test]
    fn median_works() {
        assert_eq!(median(&[3.0, 1.0, 2.0]), Some(2.0));
        assert_eq!(median(&[]), None);
    }
}
