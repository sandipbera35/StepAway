package io.github.sandipbera35.stepaway.wear

import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid

/** Broadcasts the pairing offer chunk by chunk, over and over, until stopped. */
class OfferAdvertiser(private val context: Context) {
    private val handler = Handler(Looper.getMainLooper())
    private var chunks: List<ByteArray> = emptyList()
    private var index = 0
    private var current: AdvertiseCallback? = null
    private var running = false

    var error: String? = null
        private set

    private val next = object : Runnable {
        override fun run() {
            if (!running) return
            advertise(chunks[index])
            index = (index + 1) % chunks.size
            handler.postDelayed(this, DWELL_MS)
        }
    }

    private fun advertiser() =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
            ?.takeIf { it.isEnabled }?.bluetoothLeAdvertiser

    private fun advertise(chunk: ByteArray) {
        val adv = advertiser() ?: run {
            error = "Bluetooth is off"
            return
        }
        stopCurrent(adv)
        val cb = object : AdvertiseCallback() {
            override fun onStartFailure(errorCode: Int) {
                error = "Advertising failed ($errorCode)"
            }
        }
        current = cb
        try {
            adv.startAdvertising(
                AdvertiseSettings.Builder()
                    .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                    .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                    .setConnectable(false)
                    .setTimeout(0)
                    .build(),
                AdvertiseData.Builder().setIncludeDeviceName(false).setIncludeTxPowerLevel(false)
                    .addServiceData(ParcelUuid(Offer.OFFER_UUID), chunk).build(),
                cb
            )
        } catch (e: SecurityException) {
            error = "Bluetooth permission missing"
        }
    }

    private fun stopCurrent(adv: android.bluetooth.le.BluetoothLeAdvertiser?) {
        val cb = current ?: return
        current = null
        try {
            adv?.stopAdvertising(cb)
        } catch (e: SecurityException) {
            // nothing left to stop
        }
    }

    fun start(chunks: List<ByteArray>) {
        stop()
        require(chunks.isNotEmpty())
        this.chunks = chunks
        index = 0
        error = null
        running = true
        handler.post(next)
    }

    fun stop() {
        running = false
        handler.removeCallbacks(next)
        stopCurrent(advertiser())
    }

    companion object {
        /** How long each chunk is on the air: a few advertising intervals at low-latency mode. */
        const val DWELL_MS = 350L
    }
}
