package io.github.sandipbera35.stepaway.wear

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Restarts advertising after a reboot if the user had protection switched on. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED && PairingStore(context).protectionEnabled) {
            runCatching { AdvertiseService.start(context) }
        }
    }
}
