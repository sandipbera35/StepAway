package io.github.sandipbera35.stepaway.wear

import java.security.SecureRandom

/**
 * One "pair with a code" attempt: everything the watch needs to show and broadcast.
 * Pure Kotlin so the whole thing can be unit tested; the radio work lives in [OfferAdvertiser].
 */
class PairingSession(
    random: SecureRandom = SecureRandom(),
    val code: ByteArray = Offer.newCode(random),
    val secret: ByteArray = ByteArray(32).also { random.nextBytes(it) },
    val deviceId: Int = 1 + random.nextInt(0xFFFF),
    nonce: ByteArray = ByteArray(Offer.NONCE_LEN).also { random.nextBytes(it) },
    val session: Int = random.nextInt(256),
    val kind: Int = Offer.KIND_WATCH,
) {
    init {
        require(deviceId in 1..0xFFFF) { "device id out of range" }
    }

    /** What the user types on the computer: `XXXX-XXXX-XXXX-XXXX`. */
    val codeText: String = Offer.encodeCode(code)

    /** Two lines that fit a round screen: `XXXX-XXXX` over `XXXX-XXXX`. */
    val codeLines: List<String> = codeText.split('-').chunked(2).map { it.joinToString("-") }

    /** The encrypted offer (63 bytes) and the advertisement payloads that carry it. */
    val blob: ByteArray = Offer.seal(Offer.deriveKey(code), nonce, secret, deviceId, kind)
    val chunks: List<ByteArray> = Offer.splitChunks(blob, session)

    /** The pairing to keep once the computer has confirmed it. */
    fun toPairing(computerName: String) = Pairing(deviceId, computerName, secret)

    /** True if [payload] is a beacon from the computer that has accepted this offer. */
    fun confirmedBy(payload: ByteArray, nowUnix: Long): Boolean = Token.verify(secret, deviceId, payload, nowUnix)
}
