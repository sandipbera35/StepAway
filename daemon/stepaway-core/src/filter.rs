//! RSSI smoothing: median-based outlier rejection followed by an exponential moving average.

use std::collections::VecDeque;

#[derive(Debug, Clone)]
pub struct RssiFilter {
    window: VecDeque<f64>,
    window_len: usize,
    max_dev_db: f64,
    alpha: f64,
    ema: Option<f64>,
    consecutive_rejects: u32,
}

impl Default for RssiFilter {
    fn default() -> Self {
        Self::new(7, 15.0, 0.3)
    }
}

impl RssiFilter {
    /// `max_dev_db`: samples farther than this from the window median are dropped
    /// (unless several arrive in a row, which means the signal really changed).
    pub fn new(window_len: usize, max_dev_db: f64, alpha: f64) -> Self {
        Self {
            window: VecDeque::new(),
            window_len: window_len.max(1),
            max_dev_db,
            alpha: alpha.clamp(0.01, 1.0),
            ema: None,
            consecutive_rejects: 0,
        }
    }

    fn median(&self) -> Option<f64> {
        if self.window.is_empty() {
            return None;
        }
        let mut v: Vec<f64> = self.window.iter().copied().collect();
        v.sort_by(|a, b| a.total_cmp(b));
        Some(v[v.len() / 2])
    }

    /// Feed a raw sample; returns the filtered RSSI. Non-finite samples are ignored.
    pub fn push(&mut self, rssi: f64) -> Option<f64> {
        if !rssi.is_finite() {
            return self.ema;
        }
        if let Some(med) = self.median() {
            if (rssi - med).abs() > self.max_dev_db && self.consecutive_rejects < 3 {
                self.consecutive_rejects += 1;
                return self.ema;
            }
        }
        if self.consecutive_rejects >= 3 {
            // The signal level really changed: restart the median window at the new level.
            self.window.clear();
        }
        self.consecutive_rejects = 0;
        if self.window.len() == self.window_len {
            self.window.pop_front();
        }
        self.window.push_back(rssi);
        let next = match self.ema {
            Some(prev) => prev + self.alpha * (rssi - prev),
            None => rssi,
        };
        self.ema = Some(next);
        self.ema
    }

    pub fn reset(&mut self) {
        *self = Self::new(self.window_len, self.max_dev_db, self.alpha);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn first_sample_passes_through() {
        assert_eq!(RssiFilter::default().push(-60.0), Some(-60.0));
    }

    #[test]
    fn single_spike_is_rejected() {
        let mut f = RssiFilter::default();
        for _ in 0..5 {
            f.push(-60.0);
        }
        let out = f.push(-95.0).unwrap();
        assert!((out + 60.0).abs() < 1e-9);
    }

    #[test]
    fn sustained_change_is_followed() {
        let mut f = RssiFilter::default();
        for _ in 0..5 {
            f.push(-60.0);
        }
        let mut last = 0.0;
        for _ in 0..30 {
            last = f.push(-85.0).unwrap();
        }
        assert!(last < -80.0, "{last}");
    }

    #[test]
    fn level_shift_is_followed_quickly() {
        let mut f = RssiFilter::default();
        for _ in 0..7 {
            f.push(-55.0);
        }
        let outs: Vec<f64> = (0..12).filter_map(|_| f.push(-75.0)).collect();
        assert!(outs[11] < -70.0, "{outs:?}");
    }

    #[test]
    fn nan_ignored() {
        let mut f = RssiFilter::default();
        assert_eq!(f.push(f64::NAN), None);
        f.push(-60.0);
        assert_eq!(f.push(f64::INFINITY), Some(-60.0));
    }
}
