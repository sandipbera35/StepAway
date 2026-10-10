package io.github.sandipbera35.stepaway.wear

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/** Everything the screens show, and the actions they can take. */
class WearState(context: Context) {
    private val app = context.applicationContext
    private val store = PairingStore(app)
    private val offer = OfferAdvertiser(app)
    private val scanner = BeaconScanner(app)

    var pairings by mutableStateOf(store.list())
        private set
    var protection by mutableStateOf(store.protectionEnabled)
        private set
    var advertising by mutableStateOf(false)
        private set
    var problem by mutableStateOf<String?>(null)
        private set

    /** Non-null while a "pair with a code" attempt is running. */
    var session by mutableStateOf<PairingSession?>(null)
        private set
    var paired by mutableStateOf(false)
        private set

    fun refresh() {
        pairings = store.list()
        protection = store.protectionEnabled
        advertising = AdvertiseService.state.advertising
        problem = AdvertiseService.state.error ?: offer.error
    }

    fun toggleProtection(on: Boolean) {
        store.protectionEnabled = on
        if (on && store.list().isNotEmpty()) AdvertiseService.start(app) else AdvertiseService.stop(app)
        refresh()
    }

    /** Show a code, broadcast the offer, and watch for the computer's beacon to confirm. */
    fun startPairing() {
        cancelPairing()
        val s = PairingSession()
        session = s
        paired = false
        offer.start(s.chunks)
        scanner.start(listOf(s.toPairing(DEFAULT_COMPUTER))) { _, _, _ -> finishPairing() }
    }

    fun cancelPairing() {
        offer.stop()
        scanner.stop()
        session = null
        paired = false
    }

    /** The computer proved it knows the secret: keep the pairing and start broadcasting. */
    private fun finishPairing() {
        val s = session ?: return
        if (paired) return
        offer.stop()
        scanner.stop()
        store.add(s.toPairing(DEFAULT_COMPUTER))
        store.protectionEnabled = true
        paired = true
        AdvertiseService.start(app)
        refresh()
    }

    /** Leave the "paired" confirmation screen. */
    fun closePairing() {
        session = null
        paired = false
        refresh()
    }

    fun remove(deviceId: Int) {
        store.remove(deviceId)
        if (store.list().isEmpty()) {
            store.protectionEnabled = false
            AdvertiseService.stop(app)
        } else if (store.protectionEnabled) {
            AdvertiseService.start(app)
        }
        refresh()
    }

    companion object {
        const val DEFAULT_COMPUTER = "Computer"
    }
}
