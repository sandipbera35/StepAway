package io.github.sandipbera35.stepaway_mobile

import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.ParcelUuid

/**
 * Listens for the computer's beacon (a signed token under [Token.BEACON_UUID]) and reports the
 * signal strength of the ones that belong to this phone's pairings. Only runs while the app is
 * showing the distance dashboard.
 */
class BeaconScanner(private val context: Context, private val store: PairingStore) {
    private var callback: ScanCallback? = null

    /** `onSample(pairingDeviceId, rssi)` is called for every verified beacon. */
    fun start(onSample: (Int, Int) -> Unit): Boolean {
        stop()
        val adapter = (context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
        val scanner = if (adapter != null && adapter.isEnabled) adapter.bluetoothLeScanner else null
        if (scanner == null) return false
        val pairings = store.list()
        val uuid = ParcelUuid(Token.BEACON_UUID)
        val cb = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val data = result.scanRecord?.getServiceData(uuid) ?: return
                if (data.size != Token.PAYLOAD_LEN) return
                val now = System.currentTimeMillis() / 1000
                for (p in pairings) {
                    if (Token.verify(p.secret, p.deviceId, data, now)) {
                        onSample(p.deviceId, result.rssi)
                        return
                    }
                }
            }
        }
        return try {
            // no filter: service-data filters are unreliable across phones, and we only scan while visible
            scanner.startScan(null, ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_BALANCED).build(), cb)
            callback = cb
            true
        } catch (e: SecurityException) {
            false
        }
    }

    fun stop() {
        val cb = callback ?: return
        callback = null
        val adapter = (context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
        try {
            adapter?.bluetoothLeScanner?.stopScan(cb)
        } catch (e: SecurityException) {
            // permission revoked while scanning: nothing to stop
        }
    }
}
