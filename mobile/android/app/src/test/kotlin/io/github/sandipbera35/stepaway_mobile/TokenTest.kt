package io.github.sandipbera35.stepaway_mobile

import com.google.gson.JsonParser
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.io.File
import java.util.Base64

/** Runs the shared protocol/test-vectors.json (same vectors as the Rust tests). */
class TokenTest {
    private val vectors = JsonParser.parseString(
        File("../../../protocol/test-vectors.json").readText()
    ).asJsonObject

    private fun hex(s: String) = s.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
    private fun toHex(b: ByteArray) = b.joinToString("") { "%02x".format(it) }

    @Test
    fun serviceUuidMatchesSpec() {
        assertEquals(vectors["uuid"].asString, Token.SERVICE_UUID.toString())
    }

    @Test
    fun payloadsAndVerificationCodesMatchVectors() {
        for (e in vectors["vectors"].asJsonArray) {
            val v = e.asJsonObject
            val secret = hex(v["secret_hex"].asString)
            val p = Token.buildPayload(secret, v["device_id"].asInt, 0, v["unix_time"].asLong, v["version"].asInt)
            assertEquals(v["name"].asString, v["payload_hex"].asString, toHex(p))
            assertEquals(v["verification_code"].asString, Token.verificationCode(secret))
        }
    }

    @Test
    fun verifyCasesMatchVectors() {
        for (e in vectors["verify"].asJsonArray) {
            val c = e.asJsonObject
            // replay protection lives on the computer; this phone-side check ignores counters
            if (!c["last_accepted_counter"].isJsonNull) continue
            val ok = Token.verify(
                hex(c["secret_hex"].asString), c["device_id"].asInt,
                hex(c["payload_hex"].asString), c["verifier_unix_time"].asLong
            )
            assertEquals(c["name"].asString, c["expect"].asString == "accept", ok)
        }
    }

    @Test
    fun beaconUuidIsDifferentFromTheDeviceUuid() {
        assertEquals("c0de57e9-a4a7-4b1d-9c3e-5a11a0ca7e02", Token.BEACON_UUID.toString())
        assert(Token.BEACON_UUID != Token.SERVICE_UUID)
    }

    @Test
    fun pairingUrisMatchVectors() {
        for (e in vectors["pairing"].asJsonArray) {
            val v = e.asJsonObject
            val p = Token.parsePairingUri(v["uri"].asString)!!
            assertEquals(v["device_id"].asInt, p.deviceId)
            assertArrayEquals(hex(v["secret_hex"].asString), p.secret)
            assertEquals(v["desktop_name"].asString, p.desktopName)
        }
    }

    @Test
    fun rejectsGarbageLinks() {
        assertNull(Token.parsePairingUri("https://example.com"))
        assertNull(Token.parsePairingUri("stepaway://pair?v=2&id=0001&s=AAAA"))
        val short = Base64.getUrlEncoder().withoutPadding().encodeToString(ByteArray(16))
        assertNull(Token.parsePairingUri("stepaway://pair?v=1&id=0001&s=$short"))
        assertNull(Token.parsePairingUri("stepaway://pair?v=1&id=01&s=$short"))
    }
}
