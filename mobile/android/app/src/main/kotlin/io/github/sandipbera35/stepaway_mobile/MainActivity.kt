package io.github.sandipbera35.stepaway_mobile

import android.Manifest
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private lateinit var store: PairingStore
    private lateinit var channel: MethodChannel
    private var pendingLink: String? = null
    private var pendingScan: MethodChannel.Result? = null
    private var pendingPerm: MethodChannel.Result? = null
    private var scanner: BeaconScanner? = null

    private val scanLauncher = registerForActivityResult(ScanContract()) { r ->
        pendingScan?.success(r.contents)
        pendingScan = null
    }
    private val permLauncher = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        pendingPerm?.success(permissions())
        pendingPerm = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        store = PairingStore(this)
        pendingLink = linkFrom(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "stepaway/native")
        channel.setMethodCallHandler { call, result -> handle(call, result) }
        scanner = BeaconScanner(this, store)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "stepaway/beacon").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                    val ok = scanner?.start { id, rssi -> runOnUiThread { sink.success(mapOf("id" to id, "rssi" to rssi)) } } ?: false
                    if (!ok) sink.error("scan_unavailable", "Bluetooth scanning is not available", null)
                }

                override fun onCancel(args: Any?) {
                    scanner?.stop()
                }
            }
        )
    }

    override fun onDestroy() {
        scanner?.stop()
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        linkFrom(intent)?.let { channel.invokeMethod("deepLink", it) }
    }

    private fun linkFrom(i: Intent?): String? =
        i?.data?.takeIf { it.scheme == "stepaway" }?.toString()

    private fun has(p: String) = ContextCompat.checkSelfPermission(this, p) == PackageManager.PERMISSION_GRANTED

    private fun permissions() = mapOf(
        "advertise" to has(Manifest.permission.BLUETOOTH_ADVERTISE),
        "connect" to has(Manifest.permission.BLUETOOTH_CONNECT),
        "notifications" to (Build.VERSION.SDK_INT < 33 || has(Manifest.permission.POST_NOTIFICATIONS)),
        "camera" to has(Manifest.permission.CAMERA),
        "scan" to scanPermissionGranted(),
    )

    /** Android 12+ needs BLUETOOTH_SCAN; older versions need location to scan. */
    private fun scanPermissionGranted() =
        if (Build.VERSION.SDK_INT >= 31) has(Manifest.permission.BLUETOOTH_SCAN)
        else has(Manifest.permission.ACCESS_FINE_LOCATION)

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> {
                val bt = (getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
                result.success(
                    mapOf(
                        "protection" to store.protectionEnabled,
                        "advertising" to AdvertiseService.state.advertising,
                        "error" to AdvertiseService.state.error,
                        "bluetoothOn" to (bt?.isEnabled == true),
                        "permissions" to permissions(),
                        "batteryUnrestricted" to
                            (getSystemService(Context.POWER_SERVICE) as PowerManager)
                                .isIgnoringBatteryOptimizations(packageName),
                        "pairings" to store.list().map { mapOf("id" to it.deviceId, "name" to it.desktopName) },
                    )
                )
            }
            "getPref" -> result.success(store.getPref(call.arguments as String))
            "setPref" -> {
                val a = call.arguments as List<*>
                store.setPref(a[0] as String, a[1] as String)
                result.success(true)
            }
            "getOnboarded" -> result.success(store.onboarded || store.list().isNotEmpty())
            "setOnboarded" -> {
                store.onboarded = call.arguments as? Boolean ?: true
                result.success(true)
            }
            "getTheme" -> result.success(store.themeMode)
            "setTheme" -> {
                val v = call.arguments as? String
                if (v == "system" || v == "light" || v == "dark") store.themeMode = v
                result.success(true)
            }
            "initialLink" -> {
                result.success(pendingLink)
                pendingLink = null
            }
            "previewPairing" -> {
                val p = Token.parsePairingUri(call.arguments as? String ?: "")
                if (p == null) result.error("bad_link", "Not a valid StepAway pairing code", null)
                else result.success(
                    mapOf("id" to p.deviceId, "name" to p.desktopName, "code" to Token.verificationCode(p.secret))
                )
            }
            "savePairing" -> {
                val p = Token.parsePairingUri(call.arguments as? String ?: "")
                if (p == null) result.error("bad_link", "Not a valid StepAway pairing code", null)
                else {
                    store.add(Pairing(p.deviceId, p.desktopName.ifBlank { "Computer" }, p.secret))
                    store.protectionEnabled = true
                    if (has(Manifest.permission.BLUETOOTH_ADVERTISE)) AdvertiseService.start(this)
                    result.success(true)
                }
            }
            "removePairing" -> {
                store.remove((call.arguments as Number).toInt())
                if (store.list().isEmpty()) {
                    store.protectionEnabled = false
                    AdvertiseService.stop(this)
                } else if (store.protectionEnabled) AdvertiseService.start(this)
                result.success(true)
            }
            "setProtection" -> {
                val on = call.arguments as Boolean
                store.protectionEnabled = on
                if (on) AdvertiseService.start(this) else AdvertiseService.stop(this)
                result.success(true)
            }
            "requestScanPermission" -> {
                pendingPerm = result
                val p = if (Build.VERSION.SDK_INT >= 31) Manifest.permission.BLUETOOTH_SCAN else Manifest.permission.ACCESS_FINE_LOCATION
                permLauncher.launch(arrayOf(p))
            }
            "requestPermissions" -> {
                val wanted = mutableListOf(Manifest.permission.BLUETOOTH_ADVERTISE, Manifest.permission.BLUETOOTH_CONNECT)
                if (Build.VERSION.SDK_INT >= 33) wanted += Manifest.permission.POST_NOTIFICATIONS
                pendingPerm = result
                permLauncher.launch(wanted.toTypedArray())
            }
            "scanQr" -> {
                if (!has(Manifest.permission.CAMERA)) {
                    pendingPerm = object : MethodChannel.Result {
                        override fun success(r: Any?) {
                            if (has(Manifest.permission.CAMERA)) startScan(result)
                            else result.error("no_camera", "Camera permission denied", null)
                        }
                        override fun error(c: String, m: String?, d: Any?) = result.error(c, m, d)
                        override fun notImplemented() = result.notImplemented()
                    }
                    permLauncher.launch(arrayOf(Manifest.permission.CAMERA))
                } else startScan(result)
            }
            "batterySettings" -> {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                result.success(true)
            }
            "openUrl" -> {
                val url = call.arguments as? String
                val ok = url != null && url.startsWith("https://") && try {
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                    true
                } catch (e: android.content.ActivityNotFoundException) {
                    false
                }
                result.success(ok)
            }
            "openAppSettings" -> {
                startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun startScan(result: MethodChannel.Result) {
        pendingScan = result
        scanLauncher.launch(
            ScanOptions().setDesiredBarcodeFormats(ScanOptions.QR_CODE).setBeepEnabled(false)
                .setOrientationLocked(false).setPrompt("Scan the StepAway code on your computer")
        )
    }
}
