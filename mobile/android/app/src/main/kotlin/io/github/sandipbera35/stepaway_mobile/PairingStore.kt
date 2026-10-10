package io.github.sandipbera35.stepaway_mobile

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class Pairing(val deviceId: Int, val desktopName: String, val secret: ByteArray)

/**
 * Pairing secrets, encrypted with an AES-256-GCM key that lives in the Android Keystore
 * (the key never leaves the secure hardware/keystore; only ciphertext is on disk).
 */
class PairingStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("stepaway", Context.MODE_PRIVATE)

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return gen.generateKey()
    }

    private fun encrypt(plain: ByteArray): String {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, key())
        return Base64.encodeToString(c.iv + c.doFinal(plain), Base64.NO_WRAP)
    }

    private fun decrypt(text: String): ByteArray {
        val raw = Base64.decode(text, Base64.NO_WRAP)
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, raw, 0, 12))
        return c.doFinal(raw, 12, raw.size - 12)
    }

    @Synchronized
    fun list(): List<Pairing> {
        val blob = prefs.getString(PREF_BLOB, null) ?: return emptyList()
        return try {
            val arr = JSONArray(String(decrypt(blob), Charsets.UTF_8))
            (0 until arr.length()).map {
                val o = arr.getJSONObject(it)
                Pairing(o.getInt("id"), o.getString("name"), Base64.decode(o.getString("secret"), Base64.NO_WRAP))
            }
        } catch (e: Exception) {
            emptyList() // unreadable store: behave as unpaired (safe failure)
        }
    }

    @Synchronized
    private fun save(items: List<Pairing>) {
        val arr = JSONArray()
        items.forEach {
            arr.put(
                JSONObject().put("id", it.deviceId).put("name", it.desktopName)
                    .put("secret", Base64.encodeToString(it.secret, Base64.NO_WRAP))
            )
        }
        prefs.edit().putString(PREF_BLOB, encrypt(arr.toString().toByteArray(Charsets.UTF_8))).apply()
    }

    @Synchronized
    fun add(p: Pairing) {
        save(list().filter { it.deviceId != p.deviceId } + p)
    }

    @Synchronized
    fun remove(deviceId: Int) {
        save(list().filter { it.deviceId != deviceId })
    }

    /** "system", "light" or "dark". */
    var themeMode: String
        get() = prefs.getString(PREF_THEME, "system") ?: "system"
        set(v) = prefs.edit().putString(PREF_THEME, v).apply()

    fun getPref(key: String): String? = prefs.getString("pref_$key", null)

    fun setPref(key: String, value: String) = prefs.edit().putString("pref_$key", value).apply()

    /** Whether the first-run introduction has been completed. */
    var onboarded: Boolean
        get() = prefs.getBoolean(PREF_ONBOARDED, false)
        set(v) = prefs.edit().putBoolean(PREF_ONBOARDED, v).apply()

    var protectionEnabled: Boolean
        get() = prefs.getBoolean(PREF_ENABLED, false)
        set(v) = prefs.edit().putBoolean(PREF_ENABLED, v).apply()

    companion object {
        private const val KEY_ALIAS = "stepaway_pairing_key"
        private const val PREF_BLOB = "pairings_v1"
        private const val PREF_ENABLED = "protection_enabled"
        private const val PREF_THEME = "theme_mode"
        private const val PREF_ONBOARDED = "onboarded"
    }
}
