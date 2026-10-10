package io.github.sandipbera35.stepaway.wear

import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Pairing offers for devices without a camera (smartwatches): protocol/SPEC.md §3.1.
 * The device shows a 16-character code, the user types it on the computer, and the device
 * broadcasts its secret encrypted with a key derived from that code.
 */
object Offer {
    /** Service UUID under which a device broadcasts its pairing offer. */
    val OFFER_UUID: java.util.UUID = java.util.UUID.fromString("c0de57e9-a4a7-4b1d-9c3e-5a11a0ca7e03")

    const val CODE_LEN = 10
    const val NONCE_LEN = 12
    private const val PLAIN_LEN = 32 + 2 + 1
    private const val TAG_LEN = 16
    const val BLOB_LEN = NONCE_LEN + PLAIN_LEN + TAG_LEN
    const val CHUNK_DATA = 11
    const val CHUNK_COUNT = 6
    const val CHUNK_LEN = 13

    private val SALT = "StepAway-pair-v1".toByteArray(Charsets.US_ASCII)
    private val AAD = "StepAway-offer-v1".toByteArray(Charsets.US_ASCII)
    private const val ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

    const val KIND_PHONE = 0
    const val KIND_TABLET = 1
    const val KIND_WATCH = 2
    const val KIND_OTHER = 3

    fun newCode(random: SecureRandom = SecureRandom()): ByteArray = ByteArray(CODE_LEN).also { random.nextBytes(it) }

    /** The code as shown to the user: `XXXX-XXXX-XXXX-XXXX`. */
    fun encodeCode(code: ByteArray): String {
        require(code.size == CODE_LEN)
        val sb = StringBuilder()
        var acc = 0
        var bits = 0
        var n = 0
        for (b in code) {
            acc = (acc shl 8) or (b.toInt() and 0xFF)
            bits += 8
            while (bits >= 5) {
                bits -= 5
                if (n > 0 && n % 4 == 0) sb.append('-')
                sb.append(ALPHABET[(acc shr bits) and 31])
                n++
            }
            acc = acc and ((1 shl bits) - 1)
        }
        return sb.toString()
    }

    private fun symbol(c: Char): Int {
        val u = when (val x = c.uppercaseChar()) {
            'O' -> '0'
            'I', 'L' -> '1'
            else -> x
        }
        return ALPHABET.indexOf(u)
    }

    /** Parse what the user typed (any case, dashes and spaces ignored); null if it is not a code. */
    fun parseCode(text: String): ByteArray? {
        val symbols = text.filter { it != '-' && it != ' ' && it != '\t' }.map { symbol(it) }
        if (symbols.size != 16 || symbols.any { it < 0 }) return null
        val out = ByteArray(CODE_LEN)
        var acc = 0
        var bits = 0
        var i = 0
        for (s in symbols) {
            acc = (acc shl 5) or s
            bits += 5
            if (bits >= 8) {
                bits -= 8
                out[i++] = ((acc shr bits) and 0xFF).toByte()
                acc = acc and ((1 shl bits) - 1)
            }
        }
        return out
    }

    private fun hmac(key: ByteArray, vararg parts: ByteArray): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        parts.forEach { mac.update(it) }
        return mac.doFinal()
    }

    /** HKDF-SHA256 (RFC 5869), one block of output: 32 bytes. */
    fun deriveKey(code: ByteArray): ByteArray {
        val prk = hmac(SALT, code)
        return hmac(prk, "key".toByteArray(Charsets.US_ASCII), byteArrayOf(1))
    }

    class Opened(val secret: ByteArray, val deviceId: Int, val kind: Int)

    fun seal(key: ByteArray, nonce: ByteArray, secret: ByteArray, deviceId: Int, kind: Int): ByteArray {
        require(key.size == 32 && nonce.size == NONCE_LEN && secret.size == 32)
        val plain = ByteArray(PLAIN_LEN)
        secret.copyInto(plain)
        plain[32] = (deviceId shr 8).toByte()
        plain[33] = deviceId.toByte()
        plain[34] = kind.toByte()
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_LEN * 8, nonce))
        c.updateAAD(AAD)
        return nonce + c.doFinal(plain)
    }

    fun open(key: ByteArray, blob: ByteArray): Opened? {
        if (blob.size != BLOB_LEN) return null
        return try {
            val c = Cipher.getInstance("AES/GCM/NoPadding")
            c.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_LEN * 8, blob.copyOfRange(0, NONCE_LEN)))
            c.updateAAD(AAD)
            val plain = c.doFinal(blob, NONCE_LEN, blob.size - NONCE_LEN)
            Opened(plain.copyOfRange(0, 32), ((plain[32].toInt() and 0xFF) shl 8) or (plain[33].toInt() and 0xFF), plain[34].toInt() and 0xFF)
        } catch (e: java.security.GeneralSecurityException) {
            null
        }
    }

    /** The advertisement payloads that carry a blob: `[index<<4|count][session][11 data bytes]`. */
    fun splitChunks(blob: ByteArray, session: Int): List<ByteArray> {
        require(blob.size == BLOB_LEN)
        return (0 until CHUNK_COUNT).map { i ->
            val chunk = ByteArray(CHUNK_LEN)
            chunk[0] = ((i shl 4) or CHUNK_COUNT).toByte()
            chunk[1] = session.toByte()
            val from = i * CHUNK_DATA
            val to = minOf(from + CHUNK_DATA, BLOB_LEN)
            blob.copyInto(chunk, 2, from, to)
            chunk
        }
    }
}
