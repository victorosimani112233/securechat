package com.securechat.app

import android.content.Context
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import net.zetetic.database.sqlcipher.SQLiteDatabase
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

@RunWith(AndroidJUnit4::class)
class LegacyRoomExporterInstrumentedTest {
    private lateinit var context: Context

    @Before
    fun setUp() {
        context = InstrumentationRegistry.getInstrumentation().targetContext
        context.deleteDatabase("securechat.db")
        context.getSharedPreferences("flutter_room_migration", Context.MODE_PRIVATE)
            .edit().clear().commit()
        context.getSharedPreferences("crypto_prefs", Context.MODE_PRIVATE)
            .edit().clear()
            .putInt("local_registration_id", 7711)
            .putString(
                "local_identity_key_pair_v2",
                Base64.encodeToString(encryptWithAndroidKeyStore(byteArrayOf(4, 5, 6)), Base64.NO_WRAP)
            )
            .commit()
        File(context.cacheDir, "legacy_room_export_v22.aesgcm").delete()
        File(context.filesDir, "legacy_room_archive").deleteRecursively()
        createV22Fixture()
    }

    @After
    fun tearDown() {
        context.deleteDatabase("securechat.db")
        context.getSharedPreferences("flutter_room_migration", Context.MODE_PRIVATE)
            .edit().clear().commit()
        context.getSharedPreferences("crypto_prefs", Context.MODE_PRIVATE)
            .edit().clear().commit()
        context.getSharedPreferences("securechat_keystore_meta", Context.MODE_PRIVATE)
            .edit().clear().commit()
        KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            .deleteEntry("securechat_master_key")
        File(context.cacheDir, "legacy_room_export_v22.aesgcm").delete()
        File(context.filesDir, "legacy_room_archive").deleteRecursively()
    }

    @Test
    fun readsExactSqlCipherFixtureAndArchivesOnlyAfterConfirmation() {
        val exporter = LegacyRoomExporter(context)
        val result = exporter.export()
        assertEquals("ready", result["status"])
        assertEquals(22, result["sourceSchema"])

        val path = result["path"] as String
        val transportKey = Base64.decode(result["transportKey"] as String, Base64.NO_WRAP)
        val root = JSONObject(String(decrypt(File(path).readBytes(), transportKey)))
        val tables = root.getJSONObject("tables")
        assertEquals("legacy body", tables.getJSONArray("messages").getJSONObject(0).getString("content"))
        val record = tables.getJSONArray("sessions").getJSONObject(0)
            .getJSONObject("record").getString("base64")
        assertArrayEquals(byteArrayOf(9, 8, 7), Base64.decode(record, Base64.NO_WRAP))
        assertEquals(
            "7711",
            root.getJSONObject("cryptoState").getString("local_registration_id")
        )
        assertArrayEquals(
            byteArrayOf(4, 5, 6),
            Base64.decode(
                root.getJSONObject("cryptoState").getString("local_identity_key_pair_v1"),
                Base64.NO_WRAP
            )
        )
        assertTrue(context.getDatabasePath("securechat.db").isFile)

        val archived = exporter.archiveAfterImport()
        assertEquals("archived", archived["status"])
        assertFalse(context.getDatabasePath("securechat.db").exists())
        assertTrue(File(context.filesDir, "legacy_room_archive").listFiles()!!.isNotEmpty())
        assertEquals("completed", exporter.export()["status"])
    }

    @Test
    fun fallsBackToTheKeystoreEncryptedRandomPassphraseFromOlderApks() {
        context.deleteDatabase("securechat.db")
        val legacyPassphrase = ByteArray(32) { (it + 31).toByte() }
        context.getSharedPreferences("securechat_keystore_meta", Context.MODE_PRIVATE)
            .edit()
            .putString(
                "db_passphrase_v1",
                Base64.encodeToString(encryptWithAndroidKeyStore(legacyPassphrase), Base64.NO_WRAP)
            )
            .commit()
        createV22Fixture(legacyPassphrase)

        val result = LegacyRoomExporter(context).export()

        assertEquals("ready", result["status"])
        assertEquals(22, result["sourceSchema"])
        assertTrue(context.getDatabasePath("securechat.db").exists())
    }

    private fun createV22Fixture(providedPassphrase: ByteArray? = null) {
        System.loadLibrary("sqlcipher")
        val passphrase = providedPassphrase ?: derivePassphrase()
        SQLiteDatabase.openDatabase(
            context.getDatabasePath("securechat.db").path,
            passphrase,
            null,
            SQLiteDatabase.CREATE_IF_NECESSARY,
            null
        ).use { database ->
            database.execSQL(
                "CREATE TABLE conversations (id TEXT PRIMARY KEY NOT NULL, peer_id TEXT NOT NULL, " +
                    "peer_name TEXT NOT NULL, peer_phone TEXT NOT NULL, last_message TEXT, " +
                    "last_message_timestamp INTEGER, unread_count INTEGER NOT NULL, is_muted INTEGER NOT NULL, " +
                    "is_pinned INTEGER NOT NULL, is_group INTEGER NOT NULL, group_members TEXT, contact_note TEXT, " +
                    "custom_notification_uri TEXT, is_archived INTEGER NOT NULL, disappearing_duration INTEGER NOT NULL, " +
                    "group_admins TEXT, is_favorite INTEGER NOT NULL, is_locked INTEGER NOT NULL, " +
                    "is_export_enabled INTEGER NOT NULL, manually_unread INTEGER NOT NULL, is_read_only INTEGER NOT NULL)"
            )
            database.execSQL(
                "CREATE TABLE messages (id TEXT PRIMARY KEY NOT NULL, conversation_id TEXT NOT NULL, " +
                    "sender_id TEXT NOT NULL, content TEXT NOT NULL, content_type TEXT NOT NULL, timestamp INTEGER NOT NULL, " +
                    "status TEXT NOT NULL, reply_to_id TEXT, is_outgoing INTEGER NOT NULL, is_starred INTEGER NOT NULL, " +
                    "expires_at INTEGER, edited_at INTEGER, edit_history TEXT, reactions TEXT, caption TEXT, " +
                    "is_view_once INTEGER NOT NULL, is_viewed INTEGER NOT NULL, is_pinned INTEGER NOT NULL, pinned_at INTEGER)"
            )
            database.execSQL("CREATE TABLE sessions (id TEXT PRIMARY KEY NOT NULL, record BLOB NOT NULL)")
            database.execSQL(
                "INSERT INTO conversations VALUES " +
                    "('chat','alice','Alice','',NULL,NULL,0,0,0,0,NULL,NULL,NULL,0,0,NULL,0,0,0,0,0)"
            )
            database.execSQL(
                "INSERT INTO messages VALUES " +
                    "('message','chat','alice','legacy body','TEXT',100,'READ',NULL,0,0,NULL,NULL,NULL,NULL,NULL,0,0,0,NULL)"
            )
            database.execSQL("INSERT INTO sessions(id, record) VALUES (?, ?)", arrayOf("alice:1", byteArrayOf(9, 8, 7)))
            database.version = 22
        }
        if (providedPassphrase == null) passphrase.fill(0)
    }

    private fun derivePassphrase(): ByteArray {
        val androidId = Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
            ?: "fallback_no_android_id"
        return Mac.getInstance("HmacSHA256").run {
            init(SecretKeySpec("elcim_securechat_db_passphrase_v1_salt_2026".toByteArray(), "HmacSHA256"))
            doFinal(androidId.toByteArray())
        }
    }

    private fun decrypt(envelope: ByteArray, key: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, envelope.copyOfRange(0, 12)))
        return cipher.doFinal(envelope.copyOfRange(12, envelope.size))
    }

    private fun encryptWithAndroidKeyStore(plaintext: ByteArray): ByteArray {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val key = if (keyStore.containsAlias("securechat_master_key")) {
            keyStore.getKey("securechat_master_key", null)
        } else {
            KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
                init(
                    KeyGenParameterSpec.Builder(
                        "securechat_master_key",
                        KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
                    )
                        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                        .setKeySize(256)
                        .build()
                )
                generateKey()
            }
        }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key)
        return cipher.iv + cipher.doFinal(plaintext)
    }
}
