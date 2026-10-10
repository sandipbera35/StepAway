package io.github.sandipbera35.stepaway.wear

import com.google.gson.JsonParser
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.security.SecureRandom

class PairingSessionTest {
    private val vector = JsonParser.parseString(File("../../protocol/test-vectors.json").readText())
        .asJsonObject["offer"].asJsonArray[0].asJsonObject

    private fun hex(s: String) = s.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
    private fun toHex(b: ByteArray) = b.joinToString("") { "%02x".format(it) }

    private fun fixed() = PairingSession(
        code = hex(vector["code_hex"].asString),
        secret = hex(vector["secret_hex"].asString),
        deviceId = vector["device_id"].asInt,
        nonce = hex(vector["nonce_hex"].asString),
        session = vector["session"].asInt,
        kind = vector["kind"].asInt,
    )

    @Test
    fun theOfferTheWatchBroadcastsIsExactlyWhatTheComputerExpects() {
        val s = fixed()
        assertEquals(vector["code_text"].asString, s.codeText)
        assertEquals(vector["blob_hex"].asString, toHex(s.blob))
        assertEquals(vector["chunks_hex"].asJsonArray.map { it.asString }, s.chunks.map { toHex(it) })
        assertEquals(6, s.chunks.size)
        assertTrue(s.chunks.all { it.size == Offer.CHUNK_LEN })
    }

    @Test
    fun theCodeFitsARoundScreenAsTwoLines() {
        val s = fixed()
        assertEquals(2, s.codeLines.size)
        assertEquals(s.codeText, s.codeLines.joinToString("-"))
        assertTrue(s.codeLines.all { it.length == 9 })
    }

    @Test
    fun onlyTheComputerThatAcceptedTheOfferCanConfirmIt() {
        val s = fixed()
        val now = 1_700_000_000L
        assertTrue(s.confirmedBy(Token.buildPayload(s.secret, s.deviceId, 0, now), now))
        assertFalse("a beacon made with another secret", s.confirmedBy(Token.buildPayload(ByteArray(32) { 9 }, s.deviceId, 0, now), now))
        assertFalse("a beacon for another device id", s.confirmedBy(Token.buildPayload(s.secret, s.deviceId xor 1, 0, now), now))
        assertFalse("an old beacon", s.confirmedBy(Token.buildPayload(s.secret, s.deviceId, 0, now - 3600), now))
    }

    @Test
    fun theKeptPairingCarriesTheSecretAndId() {
        val s = fixed()
        val p = s.toPairing("fedora")
        assertEquals("fedora", p.desktopName)
        assertEquals(s.deviceId, p.deviceId)
        assertArrayEquals(s.secret, p.secret)
    }

    @Test
    fun everyFreshSessionIsDifferentAndUsable() {
        val random = SecureRandom()
        val seen = HashSet<String>()
        repeat(50) {
            val s = PairingSession(random)
            assertTrue(s.deviceId in 1..0xFFFF)
            assertNotNull(Offer.parseCode(s.codeText))
            // the computer can open what this watch broadcast
            val opened = Offer.open(Offer.deriveKey(s.code), s.blob)
            assertNotNull(opened)
            assertArrayEquals(s.secret, opened!!.secret)
            assertEquals(s.deviceId, opened.deviceId)
            assertEquals(Offer.KIND_WATCH, opened.kind)
            seen += s.codeText
        }
        assertEquals("codes are not repeated", 50, seen.size)
    }
}
