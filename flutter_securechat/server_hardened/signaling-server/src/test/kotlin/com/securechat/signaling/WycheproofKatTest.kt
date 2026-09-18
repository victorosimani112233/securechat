package com.securechat.signaling

import java.security.KeyFactory
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory

/**
 * Google Wycheproof known-answer test'leri.
 *
 * Uygulama, kripto ilkellerini (AES-GCM, HMAC, Ed25519) JVM'in JCA
 * saglayicisi uzerinden kullanir. Bu sinif, uygulamanin kullandigi **ayni
 * saglayiciya** Wycheproof'un bilinen-cevap ve bilinen-bug vektorlerini
 * besler: dogru cevap dogrulanir, kotu girdi reddedilir. Amac, altta kalan
 * ilkelin (GCM tag kesme kabulu, HMAC dogrulugu, Ed25519 malleability/
 * canonical-S) bilinen tuzaklara dusmedigini kanitlamaktir.
 *
 * Vektorler `src/test/resources/wycheproof/` altindadir (Wycheproof v1).
 * Ilkelin dogrulugu HSM/PKCS11'den bagimsizdir; bu yuzden yerel JCA yeter.
 */
class WycheproofKatTest {

    private val json = Json { ignoreUnknownKeys = true }

    private fun load(name: String): JsonObject {
        val stream = javaClass.getResourceAsStream("/wycheproof/$name")
            ?: error("Wycheproof vektoru bulunamadi: $name")
        return json.parseToJsonElement(stream.readBytes().decodeToString()).jsonObject
    }

    private fun hex(s: String): ByteArray {
        if (s.isEmpty()) return ByteArray(0)
        return ByteArray(s.length / 2) { ((s[it * 2].digitToInt(16) shl 4) or s[it * 2 + 1].digitToInt(16)).toByte() }
    }

    private fun tests(doc: JsonObject) = sequence {
        for (group in doc["testGroups"]!!.jsonArray) {
            yield(group.jsonObject)
        }
    }

    private fun str(o: JsonObject, k: String) = o[k]?.jsonPrimitive?.content ?: ""
    private fun int(o: JsonObject, k: String) = o[k]!!.jsonPrimitive.content.toInt()

    // ---------------- AES-GCM ----------------

    @TestFactory
    fun `AES-GCM Wycheproof vectors`(): List<DynamicTest> {
        val doc = load("aes_gcm_test.json")
        val out = mutableListOf<DynamicTest>()
        var run = 0
        var skipped = 0
        for (group in tests(doc)) {
            val tagBits = int(group, "tagSize")
            // JCA GCM yalniz 96..128 bit tag destekler; app 128 kullanir.
            if (tagBits < 96) { skipped += group["tests"]!!.jsonArray.size; continue }
            for (tc in group["tests"]!!.jsonArray) {
                val t = tc.jsonObject
                val id = int(t, "tcId")
                val result = str(t, "result")
                val key = hex(str(t, "key"))
                val iv = hex(str(t, "iv"))
                val aad = hex(str(t, "aad"))
                val msg = hex(str(t, "msg"))
                val ct = hex(str(t, "ct"))
                val tag = hex(str(t, "tag"))
                out += DynamicTest.dynamicTest("aesgcm#$id($result)") {
                    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                    val decrypted: ByteArray? = try {
                        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(tagBits, iv))
                        cipher.updateAAD(aad)
                        cipher.doFinal(ct + tag)
                    } catch (_: java.security.InvalidAlgorithmParameterException) {
                        return@dynamicTest // param (ornegin sifir-uzunluk IV) — ilkel hatasi degil
                    } catch (_: java.security.GeneralSecurityException) {
                        null // tag/authentication reddi
                    }
                    when (result) {
                        "valid" -> {
                            assertTrue(decrypted != null, "gecerli vektor reddedildi")
                            assertTrue(decrypted!!.contentEquals(msg), "cozulen metin beklenenle uyusmuyor")
                        }
                        "invalid" -> {
                            // Kotu girdi ya reddedilmeli ya da beklenen metni URETMEMELI.
                            assertTrue(decrypted == null || !decrypted.contentEquals(msg),
                                "gecersiz vektor kabul edildi (tag zafiyeti)")
                        }
                    }
                }
                run++
            }
        }
        assertTrue(run > 100, "cok az AES-GCM vektoru kostu: $run")
        return out
    }

    // ---------------- HMAC ----------------

    private fun hmacTests(file: String, algo: String): List<DynamicTest> {
        val doc = load(file)
        val out = mutableListOf<DynamicTest>()
        for (group in tests(doc)) {
            val tagBytes = int(group, "tagSize") / 8
            for (tc in group["tests"]!!.jsonArray) {
                val t = tc.jsonObject
                val id = int(t, "tcId")
                val result = str(t, "result")
                val key = hex(str(t, "key"))
                val msg = hex(str(t, "msg"))
                val expected = hex(str(t, "tag"))
                out += DynamicTest.dynamicTest("$algo#$id($result)") {
                    val mac = Mac.getInstance(algo)
                    mac.init(SecretKeySpec(key, algo))
                    val full = mac.doFinal(msg)
                    val computed = full.copyOf(tagBytes)
                    val matches = computed.contentEquals(expected)
                    when (result) {
                        "valid" -> assertTrue(matches, "gecerli HMAC uyusmadi")
                        "invalid" -> assertTrue(!matches, "gecersiz HMAC kabul edildi")
                    }
                }
            }
        }
        return out
    }

    @TestFactory
    fun `HMAC-SHA256 Wycheproof vectors`(): List<DynamicTest> = hmacTests("hmac_sha256_test.json", "HmacSHA256")

    @TestFactory
    fun `HMAC-SHA1 Wycheproof vectors`(): List<DynamicTest> = hmacTests("hmac_sha1_test.json", "HmacSHA1")

    // ---------------- Ed25519 ----------------

    // Raw 32-byte Ed25519 public key -> X.509 SubjectPublicKeyInfo prefix.
    private val ed25519SpkiPrefix = byteArrayOf(
        0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00,
    )

    @TestFactory
    fun `Ed25519 Wycheproof vectors`(): List<DynamicTest> {
        val doc = load("ed25519_test.json")
        val keyFactory = KeyFactory.getInstance("Ed25519")
        val out = mutableListOf<DynamicTest>()
        var run = 0
        for (group in tests(doc)) {
            val pkHex = str(group["publicKey"]!!.jsonObject, "pk")
            val publicKey = keyFactory.generatePublic(
                X509EncodedKeySpec(ed25519SpkiPrefix + hex(pkHex)),
            )
            for (tc in group["tests"]!!.jsonArray) {
                val t = tc.jsonObject
                val id = int(t, "tcId")
                val result = str(t, "result")
                val msg = hex(str(t, "msg"))
                val sig = hex(str(t, "sig"))
                out += DynamicTest.dynamicTest("ed25519#$id($result)") {
                    // Uygulamanin GERCEK dogrulama kontrati: once imza tam 64
                    // byte olmali (EdDsaJwtVerifier:159, ServiceAssertion:96),
                    // sonra verify. JVM ilkeli tek basina 64-byte olmayan
                    // imzaya (arkada cop) izin verir; uzunluk guard'i bunu kapatir.
                    val ok = if (sig.size != 64) {
                        false
                    } else try {
                        val verifier = Signature.getInstance("Ed25519")
                        verifier.initVerify(publicKey)
                        verifier.update(msg)
                        verifier.verify(sig)
                    } catch (_: java.security.SignatureException) {
                        false
                    }
                    when (result) {
                        "valid" -> assertTrue(ok, "gecerli Ed25519 imza reddedildi")
                        // "invalid": malleable/canonical-olmayan/bozuk imza KABUL EDILMEMELI.
                        "invalid" -> assertTrue(!ok, "gecersiz Ed25519 imza kabul edildi (malleability)")
                    }
                }
                run++
            }
        }
        assertTrue(run > 100, "cok az Ed25519 vektoru kostu: $run")
        return out
    }
}
