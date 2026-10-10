//! The computer's own beacon: a small BLE advertisement carrying a signed token for a paired
//! device, so that the device (phone, tablet, watch) can measure how far away the computer is.
//!
//! The payload is the same 13-byte token as in protocol/SPEC.md §1 but under a different service
//! UUID ([`BEACON_UUID`]) so the two directions can never be confused.

use std::future::Future;

use crate::OsError;

/// Service UUID of the computer's beacon (the paired device's is `c0de57e9-...-7e01`).
pub const BEACON_UUID: [u8; 16] = [
    0xc0, 0xde, 0x57, 0xe9, 0xa4, 0xa7, 0x4b, 0x1d, 0x9c, 0x3e, 0x5a, 0x11, 0xa0, 0xca, 0x7e, 0x02,
];
pub const BEACON_UUID_STR: &str = "c0de57e9-a4a7-4b1d-9c3e-5a11a0ca7e02";
pub const PAYLOAD_LEN: usize = 13;

/// Starts, changes and stops the beacon advertisement.
pub trait BeaconAdvertiser: Send + Sync {
    /// Advertise `payload`; `None` stops advertising. Calling again replaces the payload.
    fn set_payload(
        &self,
        payload: Option<[u8; PAYLOAD_LEN]>,
    ) -> impl Future<Output = Result<(), OsError>> + Send;
}

/// No beacon (unsupported platform or no Bluetooth).
#[derive(Debug, Default, Clone, Copy)]
pub struct NullBeacon;

impl BeaconAdvertiser for NullBeacon {
    async fn set_payload(&self, _payload: Option<[u8; PAYLOAD_LEN]>) -> Result<(), OsError> {
        Ok(())
    }
}

/// Records what was advertised, for tests.
#[derive(Debug, Default)]
pub struct MockBeacon {
    log: std::sync::Mutex<Vec<Option<[u8; PAYLOAD_LEN]>>>,
}

impl MockBeacon {
    pub fn log(&self) -> Vec<Option<[u8; PAYLOAD_LEN]>> {
        self.log.lock().unwrap_or_else(|e| e.into_inner()).clone()
    }
}

impl BeaconAdvertiser for MockBeacon {
    async fn set_payload(&self, payload: Option<[u8; PAYLOAD_LEN]>) -> Result<(), OsError> {
        self.log
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .push(payload);
        Ok(())
    }
}

#[cfg(target_os = "linux")]
pub use bluez::BlueZBeacon;

#[cfg(target_os = "linux")]
mod bluez {
    use std::collections::HashMap;
    use std::sync::{Arc, Mutex};

    use zbus::zvariant::{ObjectPath, Value};
    use zbus::{interface, Connection};

    use super::{BeaconAdvertiser, BEACON_UUID_STR, PAYLOAD_LEN};
    use crate::OsError;

    const ADV_PATH: &str = "/io/github/sandipbera35/stepaway/adv0";
    const MANAGER: &str = "org.bluez.LEAdvertisingManager1";

    /// The `org.bluez.LEAdvertisement1` object BlueZ reads our advertisement from.
    struct Advertisement {
        payload: Arc<Mutex<Vec<u8>>>,
    }

    #[interface(name = "org.bluez.LEAdvertisement1")]
    impl Advertisement {
        fn release(&self) {}

        #[zbus(property, name = "Type")]
        fn kind(&self) -> String {
            "broadcast".to_owned()
        }

        #[zbus(property, name = "ServiceData")]
        fn service_data(&self) -> HashMap<String, Value<'static>> {
            let bytes = self
                .payload
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .clone();
            HashMap::from([(BEACON_UUID_STR.to_owned(), Value::from(bytes))])
        }
    }

    pub struct BlueZBeacon {
        conn: Connection,
        adapter: String,
        payload: Arc<Mutex<Vec<u8>>>,
        state: tokio::sync::Mutex<bool>, // is an advertisement currently registered?
    }

    impl BlueZBeacon {
        /// Connects to the system bus and checks that the adapter can advertise.
        pub async fn connect() -> Result<Self, OsError> {
            let conn = Connection::system()
                .await
                .map_err(|e| OsError::Unavailable(e.to_string()))?;
            let payload = Arc::new(Mutex::new(Vec::new()));
            conn.object_server()
                .at(
                    ADV_PATH,
                    Advertisement {
                        payload: payload.clone(),
                    },
                )
                .await
                .map_err(|e| OsError::Unavailable(e.to_string()))?;
            let adapter = Self::find_adapter(&conn).await?;
            Ok(Self {
                conn,
                adapter,
                payload,
                state: tokio::sync::Mutex::new(false),
            })
        }

        async fn find_adapter(conn: &Connection) -> Result<String, OsError> {
            let reply = conn
                .call_method(
                    Some("org.bluez"),
                    "/",
                    Some("org.freedesktop.DBus.ObjectManager"),
                    "GetManagedObjects",
                    &(),
                )
                .await
                .map_err(|e| OsError::Unavailable(e.to_string()))?;
            let objects: HashMap<
                zbus::zvariant::OwnedObjectPath,
                HashMap<String, HashMap<String, zbus::zvariant::OwnedValue>>,
            > = reply
                .body()
                .deserialize()
                .map_err(|e| OsError::Unavailable(e.to_string()))?;
            let mut adapters: Vec<String> = objects
                .into_iter()
                .filter(|(_, ifaces)| ifaces.contains_key(MANAGER))
                .map(|(p, _)| p.to_string())
                .collect();
            adapters.sort();
            adapters
                .into_iter()
                .next()
                .ok_or_else(|| OsError::Unavailable("no Bluetooth adapter can advertise".into()))
        }

        async fn call(&self, method: &str) -> Result<(), OsError> {
            let path =
                ObjectPath::try_from(ADV_PATH).map_err(|e| OsError::Failed(e.to_string()))?;
            let opts: HashMap<&str, Value<'_>> = HashMap::new();
            self.conn
                .call_method(
                    Some("org.bluez"),
                    self.adapter.as_str(),
                    Some(MANAGER),
                    method,
                    &(path, opts),
                )
                .await
                .map(|_| ())
                .map_err(|e| OsError::Failed(e.to_string()))
        }

        async fn unregister(&self) {
            let Ok(path) = ObjectPath::try_from(ADV_PATH) else {
                return;
            };
            let _ = self
                .conn
                .call_method(
                    Some("org.bluez"),
                    self.adapter.as_str(),
                    Some(MANAGER),
                    "UnregisterAdvertisement",
                    &(path,),
                )
                .await;
        }
    }

    impl BeaconAdvertiser for BlueZBeacon {
        async fn set_payload(&self, payload: Option<[u8; PAYLOAD_LEN]>) -> Result<(), OsError> {
            let mut registered = self.state.lock().await;
            // BlueZ reads the advertisement when it is registered, so a new payload means
            // unregister + register again.
            if *registered {
                self.unregister().await;
                *registered = false;
            }
            let Some(p) = payload else { return Ok(()) };
            *self.payload.lock().unwrap_or_else(|e| e.into_inner()) = p.to_vec();
            self.call("RegisterAdvertisement").await?;
            *registered = true;
            Ok(())
        }
    }
}

#[cfg(windows)]
pub use winrt::WindowsBeacon;

#[cfg(windows)]
mod winrt {
    use windows::Devices::Bluetooth::Advertisement::{
        BluetoothLEAdvertisementDataSection, BluetoothLEAdvertisementPublisher,
    };
    use windows::Storage::Streams::DataWriter;
    use windows::Win32::System::WinRT::{RoInitialize, RO_INIT_MULTITHREADED};

    use super::{BeaconAdvertiser, BEACON_UUID, PAYLOAD_LEN};
    use crate::OsError;

    fn err(e: windows::core::Error) -> OsError {
        OsError::Failed(e.to_string())
    }

    #[derive(Default)]
    pub struct WindowsBeacon {
        publisher: std::sync::Mutex<Option<BluetoothLEAdvertisementPublisher>>,
    }

    // SAFETY: the WinRT publisher object is agile (free-threaded) and only touched under the mutex.
    unsafe impl Send for WindowsBeacon {}
    unsafe impl Sync for WindowsBeacon {}

    impl WindowsBeacon {
        pub fn new() -> Self {
            Self::default()
        }
    }

    impl BeaconAdvertiser for WindowsBeacon {
        async fn set_payload(&self, payload: Option<[u8; PAYLOAD_LEN]>) -> Result<(), OsError> {
            // SAFETY: plain COM initialisation; harmless if the thread is already initialised.
            let _ = unsafe { RoInitialize(RO_INIT_MULTITHREADED) };
            let mut slot = self.publisher.lock().unwrap_or_else(|e| e.into_inner());
            if let Some(old) = slot.take() {
                let _ = old.Stop();
            }
            let Some(p) = payload else { return Ok(()) };
            // AD type 0x21 = service data, 128-bit UUID (little-endian on the air) + the token
            let mut data = BEACON_UUID.to_vec();
            data.reverse();
            data.extend_from_slice(&p);
            let writer = DataWriter::new().map_err(err)?;
            writer.WriteBytes(&data).map_err(err)?;
            let section = BluetoothLEAdvertisementDataSection::Create(
                0x21,
                &writer.DetachBuffer().map_err(err)?,
            )
            .map_err(err)?;
            let publisher = BluetoothLEAdvertisementPublisher::new().map_err(err)?;
            publisher
                .Advertisement()
                .map_err(err)?
                .DataSections()
                .map_err(err)?
                .Append(&section)
                .map_err(err)?;
            publisher.Start().map_err(err)?;
            *slot = Some(publisher);
            Ok(())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn beacon_uuid_string_matches_the_bytes_and_differs_from_the_device_uuid() {
        let from_bytes = BEACON_UUID
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect::<String>();
        assert_eq!(from_bytes, BEACON_UUID_STR.replace('-', ""));
        assert!(BEACON_UUID_STR.ends_with("7e02"));
    }

    #[tokio::test]
    async fn mock_records_changes_and_stop() {
        let b = MockBeacon::default();
        b.set_payload(Some([1; PAYLOAD_LEN])).await.unwrap();
        b.set_payload(Some([2; PAYLOAD_LEN])).await.unwrap();
        b.set_payload(None).await.unwrap();
        assert_eq!(
            b.log(),
            vec![Some([1; PAYLOAD_LEN]), Some([2; PAYLOAD_LEN]), None]
        );
    }

    #[tokio::test]
    async fn null_beacon_accepts_everything() {
        NullBeacon
            .set_payload(Some([0; PAYLOAD_LEN]))
            .await
            .unwrap();
        NullBeacon.set_payload(None).await.unwrap();
    }
}
