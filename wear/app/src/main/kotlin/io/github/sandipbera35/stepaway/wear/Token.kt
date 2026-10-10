package io.github.sandipbera35.stepaway.wear

import java.net.URLDecoder
import java.nio.ByteBuffer
import java.util.Base64
import java.util.UUID
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/** Advertisement token and pairing URI, implementing protocol/SPEC.md v1. */
object Token {
    val SERVICE_UUID: UUID = UUID.fromString("c0de57e9-a4a7-4b1d-9c3e-5a11a0ca7e01")
    /** Service UUID of the computer's beacon (the phone's own advertisement uses [SERVICE_UUID]). */
    val BEACON_UUID: UUID = UUID.fromString("c0de57e9-a4a7-4b1d-9c3e-5a11a0ca7e02")
    const val PAYLOAD_LEN = 13
    const val WINDOW_SECS = 10L
    /** Current protocol version (10 s token window). Version 1 (30 s) is legacy. */
    const val VERSION = 2
    const val FLAG_PHONE_UNLOCKED = 0x01

    private val MAC_PREFIX = "StepAway-adv-v1".toByteArray(Charsets.US_ASCII)
    private val VERIFY_PREFIX = "StepAway-verify-v1".toByteArray(Charsets.US_ASCII)

    private fun hmac(secret: ByteArray, vararg parts: ByteArray): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(secret, "HmacSHA256"))
        parts.forEach { mac.update(it) }
        return mac.doFinal()
    }

    fun buildPayload(secret: ByteArray, deviceId: Int, flags: Int, unixTime: Long, version: Int = VERSION): ByteArray {
        require(secret.size == 32) { "secret must be 32 bytes" }
        require(deviceId in 0..0xFFFF) { "device id out of range" }
        require(version == 1 || version == 2) { "unknown protocol version" }
        val window = if (version == 1) 30L else WINDOW_SECS
        val verFlags = (version shl 4) or (flags and 0x0F)
        val counter = unixTime / window
        val id = ByteBuffer.allocate(2).putShort(deviceId.toShort()).array()
        val ctr = ByteBuffer.allocate(8).putLong(counter).array()
        val mac = hmac(secret, MAC_PREFIX, byteArrayOf(verFlags.toByte()), id, ctr).copyOf(8)
        return ByteBuffer.allocate(PAYLOAD_LEN)
            .put(verFlags.toByte())
            .put(id)
            .putShort((counter and 0xFFFF).toShort())
            .put(mac)
            .array()
    }

    /** (window seconds, accepted skew in windows) for a protocol version, or null if unknown. */
    private fun params(version: Int): Pair<Long, Long>? = when (version) {
        1 -> 30L to 1L
        2 -> WINDOW_SECS to 3L
        else -> null
    }

    /**
     * Checks a token (a phone's own advertisement or the computer's beacon) against a secret.
     * Replay protection is not applied: a replayed beacon can at worst fake the distance display.
     */
    fun verify(secret: ByteArray, expectedDeviceId: Int, payload: ByteArray, nowUnix: Long): Boolean {
        if (secret.size != 32 || payload.size != PAYLOAD_LEN) return false
        val verFlags = payload[0].toInt() and 0xFF
        val (window, skew) = params(verFlags shr 4) ?: return false
        if (verFlags and 0x0E != 0) return false
        val deviceId = ((payload[1].toInt() and 0xFF) shl 8) or (payload[2].toInt() and 0xFF)
        if (deviceId != expectedDeviceId) return false
        val counterLo = ((payload[3].toInt() and 0xFF) shl 8) or (payload[4].toInt() and 0xFF)
        val now = nowUnix / window
        val id = ByteBuffer.allocate(2).putShort(deviceId.toShort()).array()
        val mac = payload.copyOfRange(5, PAYLOAD_LEN)
        var ok = false
        for (c in (now - skew)..(now + skew)) {
            if (c < 0 || (c and 0xFFFF).toInt() != counterLo) continue
            val ctr = ByteBuffer.allocate(8).putLong(c).array()
            val expect = hmac(secret, MAC_PREFIX, byteArrayOf(verFlags.toByte()), id, ctr).copyOf(8)
            if (java.security.MessageDigest.isEqual(expect, mac)) ok = true // constant time
        }
        return ok
    }

    /** 6-digit code shown on both devices during pairing. */
    fun verificationCode(secret: ByteArray): String {
        val d = hmac(secret, VERIFY_PREFIX)
        val n = ByteBuffer.wrap(d, 0, 4).int.toLong() and 0xFFFFFFFFL
        return "%06d".format(n % 1_000_000)
    }

    class PairingLink(val deviceId: Int, val secret: ByteArray, val desktopName: String)

    fun parsePairingUri(uri: String): PairingLink? {
        val prefix = "stepaway://pair?"
        if (!uri.startsWith(prefix)) return null
        val q = uri.removePrefix(prefix).split('&').mapNotNull {
            val i = it.indexOf('=')
            if (i < 0) null else it.substring(0, i) to it.substring(i + 1)
        }.toMap()
        if (q["v"] != "1") return null
        val id = q["id"]?.takeIf { it.length == 4 }?.toIntOrNull(16) ?: return null
        val secret = try {
            Base64.getUrlDecoder().decode(q["s"] ?: return null)
        } catch (e: IllegalArgumentException) {
            return null
        }
        if (secret.size != 32) return null
        val name = try {
            URLDecoder.decode((q["n"] ?: "").replace("+", "%2B"), "UTF-8")
        } catch (e: IllegalArgumentException) {
            return null
        }
        return PairingLink(id, secret, name)
    }
}
