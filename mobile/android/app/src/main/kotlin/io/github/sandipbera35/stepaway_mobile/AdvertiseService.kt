package io.github.sandipbera35.stepaway_mobile

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.KeyguardManager
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.ParcelUuid
import androidx.core.content.ContextCompat

/**
 * Foreground service that broadcasts the rotating StepAway token (one advertisement per paired
 * computer, re-issued at every 30 s window boundary).
 */
class AdvertiseService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private val callbacks = mutableMapOf<Int, AdvertiseCallback>()
    private var useScanResponse = false
    private lateinit var store: PairingStore

    private val rotate = Runnable { rotateNow() }
    private val btReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) {
            when (i.getIntExtra(BluetoothAdapter.EXTRA_STATE, -1)) {
                BluetoothAdapter.STATE_ON -> rotateNow()
                BluetoothAdapter.STATE_OFF -> {
                    stopAll()
                    state.advertising = false
                }
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        store = PairingStore(this)
        registerReceiver(btReceiver, IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(
            NOTIF_ID, buildNotification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
        )
        if (!hasPermission(Manifest.permission.BLUETOOTH_ADVERTISE)) {
            state.error = "Bluetooth permission missing"
            stopSelf()
            return START_NOT_STICKY
        }
        rotateNow()
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(rotate)
        stopAll()
        runCatching { unregisterReceiver(btReceiver) }
        state.advertising = false
        super.onDestroy()
    }

    private fun hasPermission(p: String) =
        ContextCompat.checkSelfPermission(this, p) == PackageManager.PERMISSION_GRANTED

    private fun advertiser(): BluetoothLeAdvertiser? {
        val adapter = (getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
        return if (adapter != null && adapter.isEnabled) adapter.bluetoothLeAdvertiser else null
    }

    private fun stopAll() {
        val adv = advertiser()
        callbacks.values.forEach { cb -> runCatching { adv?.stopAdvertising(cb) } }
        callbacks.clear()
    }

    private fun rotateNow() {
        handler.removeCallbacks(rotate)
        stopAll()
        val adv = advertiser()
        val pairings = store.list().take(MAX_PAIRINGS)
        if (adv == null) {
            state.advertising = false
            state.error = "Bluetooth is off"
        } else if (pairings.isEmpty()) {
            state.advertising = false
            state.error = "Not paired with any computer"
        } else {
            val now = System.currentTimeMillis() / 1000
            val unlocked = !(getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager).isDeviceLocked
            val flags = if (unlocked) Token.FLAG_PHONE_UNLOCKED else 0
            pairings.forEach { p -> start(adv, p, Token.buildPayload(p.secret, p.deviceId, flags, now)) }
        }
        // next window boundary + 200 ms (every 10 s) so the new counter is already current
        val untilNext = (Token.WINDOW_SECS - System.currentTimeMillis() / 1000 % Token.WINDOW_SECS) * 1000 + 200
        handler.postDelayed(rotate, untilNext)
    }

    /** User choice (Settings → Speed vs battery); read at every rotation, so changes apply within 10 s. */
    private fun advertiseMode(): Int = when (store.getPref("advertise_mode")) {
        "low_latency" -> AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY
        "low_power" -> AdvertiseSettings.ADVERTISE_MODE_LOW_POWER
        else -> AdvertiseSettings.ADVERTISE_MODE_BALANCED
    }

    private fun start(adv: BluetoothLeAdvertiser, p: Pairing, payload: ByteArray) {
        val uuid = ParcelUuid(Token.SERVICE_UUID)
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(advertiseMode())
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(false)
            .setTimeout(0)
            .build()
        val builder = AdvertiseData.Builder().setIncludeDeviceName(false).setIncludeTxPowerLevel(false)
        val cb = object : AdvertiseCallback() {
            override fun onStartSuccess(s: AdvertiseSettings) {
                state.advertising = true
                state.error = null
            }

            override fun onStartFailure(code: Int) {
                if (code == ADVERTISE_FAILED_DATA_TOO_LARGE && !useScanResponse) {
                    // Some stacks add a Flags field: move the payload to the scan response.
                    useScanResponse = true
                    handler.post { rotateNow() }
                    return
                }
                state.advertising = false
                state.error = "Advertising failed (code $code)"
            }
        }
        callbacks[p.deviceId] = cb
        try {
            if (useScanResponse) {
                val main = builder.addServiceUuid(uuid).build()
                val scan = AdvertiseData.Builder().setIncludeDeviceName(false)
                    .addServiceData(uuid, payload).build()
                adv.startAdvertising(settings, main, scan, cb)
            } else {
                adv.startAdvertising(settings, builder.addServiceData(uuid, payload).build(), cb)
            }
        } catch (e: SecurityException) {
            state.error = "Bluetooth permission missing"
        }
    }

    private fun buildNotification(): Notification {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL, "StepAway protection", NotificationManager.IMPORTANCE_LOW)
        )
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE
        )
        return Notification.Builder(this, CHANNEL)
            .setContentTitle("StepAway is active")
            .setContentText("Your computer can detect that you are nearby")
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setContentIntent(open)
            .setOngoing(true)
            .build()
    }

    class State {
        @Volatile var advertising = false
        @Volatile var error: String? = null
    }

    companion object {
        private const val NOTIF_ID = 1
        private const val CHANNEL = "stepaway_service"
        private const val MAX_PAIRINGS = 3
        val state = State()

        fun start(ctx: Context) {
            ContextCompat.startForegroundService(ctx, Intent(ctx, AdvertiseService::class.java))
        }

        fun stop(ctx: Context) {
            ctx.stopService(Intent(ctx, AdvertiseService::class.java))
        }
    }
}
