//! Log-distance path-loss model: `d = 10 ^ ((tx_power_1m - rssi) / (10 n))`.

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct DistanceModel {
    /// Expected RSSI at 1 m (from calibration).
    pub tx_power_1m: f64,
    /// Path-loss exponent, typically 2.0-3.0.
    pub n: f64,
}

impl Default for DistanceModel {
    fn default() -> Self {
        Self {
            tx_power_1m: -59.0,
            n: 2.0,
        }
    }
}

impl DistanceModel {
    pub fn distance_m(&self, rssi: f64) -> f64 {
        10f64.powf((self.tx_power_1m - rssi) / (10.0 * self.n))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn one_metre_at_tx_power() {
        let m = DistanceModel::default();
        assert!((m.distance_m(-59.0) - 1.0).abs() < 1e-9);
    }

    #[test]
    fn twenty_db_weaker_is_ten_times_farther_for_n2() {
        let m = DistanceModel::default();
        assert!((m.distance_m(-79.0) - 10.0).abs() < 1e-9);
    }

    #[test]
    fn monotonic() {
        let m = DistanceModel {
            tx_power_1m: -60.0,
            n: 2.5,
        };
        assert!(m.distance_m(-80.0) > m.distance_m(-70.0));
    }
}
