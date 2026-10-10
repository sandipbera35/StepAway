//! BLE scanning: turns radio events into `Advertisement { rssi, payload }` for StepAway's UUID.

use std::future::Future;

use btleplug::api::{Central, CentralEvent, Manager as _, Peripheral as _, ScanFilter};
use btleplug::platform::{Adapter, Manager};
use futures::StreamExt;
use stepaway_core::offer;
use stepaway_core::token::{PAYLOAD_LEN, SERVICE_UUID};
use uuid::Uuid;

#[derive(Debug, thiserror::Error)]
pub enum BleError {
    #[error("no bluetooth adapter found")]
    NoAdapter,
    #[error("bluetooth error: {0}")]
    Backend(String),
}

impl From<btleplug::Error> for BleError {
    fn from(e: btleplug::Error) -> Self {
        BleError::Backend(e.to_string())
    }
}

/// One received StepAway advertisement (not yet authenticated).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Advertisement {
    pub rssi: i16,
    pub payload: [u8; PAYLOAD_LEN],
}

/// An advertisement from any other Bluetooth LE device (band, earbuds, ...).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OtherAdv {
    /// Stable identifier of the device (its Bluetooth address).
    pub id: String,
    pub name: Option<String>,
    pub rssi: i16,
}

/// What the scanner saw.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ScanEvent {
    /// A StepAway advertisement (authenticated later by the daemon).
    Stepaway(Advertisement),
    /// One chunk of a pairing offer from a device that is showing a pairing code.
    PairingChunk([u8; offer::CHUNK_LEN]),
    /// Any other device; used for the "nearby devices" list and lock-only tracking.
    Other(OtherAdv),
}

/// Source of advertisements; the daemon uses this trait so tests can inject traces.
pub trait AdvSource: Send {
    /// Next event, or `None` when the source has ended.
    fn next(&mut self) -> impl Future<Output = Option<ScanEvent>> + Send;
}

/// Extract a payload from service data if it carries our UUID and the right length.
pub fn extract_payload(
    service_data: &std::collections::HashMap<Uuid, Vec<u8>>,
) -> Option<[u8; PAYLOAD_LEN]> {
    let data = service_data.get(&Uuid::from_bytes(SERVICE_UUID))?;
    <[u8; PAYLOAD_LEN]>::try_from(data.as_slice()).ok()
}

/// Extract a pairing-offer chunk from service data, if it carries the offer UUID.
pub fn extract_chunk(
    service_data: &std::collections::HashMap<Uuid, Vec<u8>>,
) -> Option<[u8; offer::CHUNK_LEN]> {
    let data = service_data.get(&Uuid::from_bytes(offer::OFFER_UUID))?;
    <[u8; offer::CHUNK_LEN]>::try_from(data.as_slice()).ok()
}

/// Real scanner on top of btleplug (BlueZ on Linux, WinRT on Windows).
pub struct BtleplugSource {
    adapter: Adapter,
    events: std::pin::Pin<Box<dyn futures::Stream<Item = CentralEvent> + Send>>,
}

impl BtleplugSource {
    pub async fn start() -> Result<Self, BleError> {
        let manager = Manager::new().await?;
        let adapter = manager
            .adapters()
            .await?
            .into_iter()
            .next()
            .ok_or(BleError::NoAdapter)?;
        let events = adapter.events().await?;
        // No service filter: BlueZ does not match service-data UUIDs against the filter.
        adapter.start_scan(ScanFilter::default()).await?;
        Ok(Self { adapter, events })
    }
}

impl AdvSource for BtleplugSource {
    async fn next(&mut self) -> Option<ScanEvent> {
        while let Some(ev) = self.events.next().await {
            let id = match ev {
                CentralEvent::DeviceUpdated(id) => id,
                CentralEvent::ServiceDataAdvertisement { id, .. } => id,
                _ => continue,
            };
            let Ok(p) = self.adapter.peripheral(&id).await else {
                continue;
            };
            let Ok(Some(props)) = p.properties().await else {
                continue;
            };
            let Some(rssi) = props.rssi else { continue };
            if let Some(chunk) = extract_chunk(&props.service_data) {
                return Some(ScanEvent::PairingChunk(chunk));
            }
            if let Some(payload) = extract_payload(&props.service_data) {
                return Some(ScanEvent::Stepaway(Advertisement { rssi, payload }));
            }
            return Some(ScanEvent::Other(OtherAdv {
                id: props.address.to_string(),
                name: props.local_name.filter(|n| !n.trim().is_empty()),
                rssi,
            }));
        }
        None
    }
}

/// Replays a fixed list; used in tests.
pub struct ListSource(pub std::collections::VecDeque<ScanEvent>);

impl AdvSource for ListSource {
    async fn next(&mut self) -> Option<ScanEvent> {
        self.0.pop_front()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    #[test]
    fn extracts_matching_payload() {
        let mut m = HashMap::new();
        m.insert(Uuid::from_bytes(SERVICE_UUID), vec![1u8; PAYLOAD_LEN]);
        assert_eq!(extract_payload(&m), Some([1u8; PAYLOAD_LEN]));
    }

    #[test]
    fn extracts_offer_chunks_only_under_the_offer_uuid() {
        let mut m = HashMap::new();
        m.insert(
            Uuid::from_bytes(offer::OFFER_UUID),
            vec![7u8; offer::CHUNK_LEN],
        );
        assert_eq!(extract_chunk(&m), Some([7u8; offer::CHUNK_LEN]));
        assert_eq!(extract_payload(&m), None, "an offer is not a device token");
        let mut t = HashMap::new();
        t.insert(Uuid::from_bytes(SERVICE_UUID), vec![7u8; PAYLOAD_LEN]);
        assert_eq!(extract_chunk(&t), None);
    }

    #[test]
    fn ignores_wrong_uuid_or_length() {
        let mut m = HashMap::new();
        m.insert(Uuid::nil(), vec![1u8; PAYLOAD_LEN]);
        assert_eq!(extract_payload(&m), None);
        let mut m = HashMap::new();
        m.insert(Uuid::from_bytes(SERVICE_UUID), vec![1u8; PAYLOAD_LEN - 1]);
        assert_eq!(extract_payload(&m), None);
    }

    #[tokio::test]
    async fn list_source_drains() {
        let a = ScanEvent::Stepaway(Advertisement {
            rssi: -60,
            payload: [0; PAYLOAD_LEN],
        });
        let o = ScanEvent::Other(OtherAdv {
            id: "AA:BB:CC:DD:EE:FF".into(),
            name: Some("Band".into()),
            rssi: -70,
        });
        let mut s = ListSource([a.clone(), o.clone()].into());
        assert_eq!(s.next().await, Some(a));
        assert_eq!(s.next().await, Some(o));
        assert_eq!(s.next().await, None);
    }
}
