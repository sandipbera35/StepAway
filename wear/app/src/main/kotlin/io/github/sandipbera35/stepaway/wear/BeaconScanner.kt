package io.github.sandipbera35.stepaway.wear

import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.ParcelUuid

/**
 * Listens for the computer's beacon and reports it when it verifies against one of the secrets
 * given to [start]. Used to confirm a pairing and (later) to show distance.
 */
class BeaconScanner(private val context: Context) {
    private var callback: ScanCallback? = null

    fun start(pairings: List<Pairing>, onVerified: (deviceId: Int, rssi: Int, payload: ByteArray) -> Unit): Boolean {
        stop()
        val adapter = (context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
        val scanner = adapter?.takeIf { it.isEnabled }?.bluetoothLeScanner ?: return false
        val uuid = ParcelUuid(Token.BEACON_UUID)
        val cb = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val data = result.scanRecord?.getServiceData(uuid) ?: return
                if (data.size != Token.PAYLOAD_LEN) return
                val now = System.currentTimeMillis() / 1000
                pairings.firstOrNull { Token.verify(it.secret, it.deviceId, data, now) }
                    ?.let { onVerified(it.deviceId, result.rssi, data) }
            }
        }
        return try {
            scanner.startScan(null, ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(), cb)
            callback = cb
            true
        } catch (e: SecurityException) {
            false
        }
    }

    fun stop() {
        val cb = callback ?: return
        callback = null
        try {
            (context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter?.bluetoothLeScanner?.stopScan(cb)
        } catch (e: SecurityException) {
            // permission revoked while scanning
        }
    }
}
