package com.securechat.app

import android.content.Context
import android.database.Cursor
import android.provider.Settings
import android.util.Base64
import net.zetetic.database.sqlcipher.SQLiteDatabase
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/** Read-only bridge for a Kotlin Room/SQLCipher database left by an APK upgrade. */
class LegacyRoomExporter(private val context: Context) {
    companion object {
        private const val DATABASE_NAME = "securechat.db"
        private const val HMAC_SALT = "elcim_securechat_db_passphrase_v1_salt_2026"
        private const val PREFS = "flutter_room_migration"
        private const val COMPLETED = "room_v22_import_completed"
        private const val CRYPTO_PREFS = "crypto_prefs"
        private const val REGISTRATION_ID = "local_registration_id"
        private const val IDENTITY_PAIR_LEGACY = "local_identity_key_pair"
        private const val IDENTITY_PAIR_ENCRYPTED = "local_identity_key_pair_v2"
        private const val MASTER_KEY_ALIAS = "securechat_master_key"
        private const val KEYSTORE_META_PREFS = "securechat_keystore_meta"
        private const val LEGACY_DB_PASSPHRASE = "db_passphrase_v1"
        private val TABLES = listOf(
            "conversations", "messages", "contacts", "call_log",
            "scheduled_messages", "pending_timer_updates", "export_log",
            "identities", "prekeys", "signed_prekeys", "sessions", "sender_keys"
        )
        private val BLOB_COLUMNS = setOf("identity_key", "record")
    }

    fun export(): Map<String, Any?> {
        if (context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getBoolean(COMPLETED, false)) {
            return mapOf("status" to "completed")
        }
        val source = context.getDatabasePath(DATABASE_NAME)
        if (!source.isFile) return mapOf("status" to "absent")

        System.loadLibrary("sqlcipher")
        var passphrase = derivePassphrase()
        val output = File(context.cacheDir, "legacy_room_export_v22.aesgcm")
        val temporary = File(output.path + ".tmp")
        var transportKey: ByteArray? = null
        try {
            val root = JSONObject()
            val counts = JSONObject()
            val database = try {
                openReadOnly(source, passphrase)
            } catch (deterministicFailure: Exception) {
                passphrase.fill(0)
                passphrase = readLegacyDbPassphrase() ?: throw deterministicFailure
                openReadOnly(source, passphrase)
            }
            database.use {
                val version = database.version
                require(version in 1..22) { "Unsupported Room schema version: $version" }
                root.put("sourceSchema", version)
                root.put("sourcePath", source.path)
                val tables = JSONObject()
                for (table in TABLES) {
                    if (!tableExists(database, table)) continue
                    val rows = readTable(database, table)
                    tables.put(table, rows)
                    counts.put(table, rows.length())
                }
                root.put("tables", tables)
                root.put("rowCounts", counts)
            }
            root.put("cryptoState", readLocalCryptoState())
            transportKey = ByteArray(32).also { SecureRandom().nextBytes(it) }
            temporary.writeBytes(encryptTransport(root.toString().toByteArray(), transportKey))
            if (output.exists() && !output.delete()) {
                error("Cannot replace stale Room export")
            }
            if (!temporary.renameTo(output)) error("Cannot commit Room export")
            return mapOf(
                "status" to "ready",
                "path" to output.path,
                "transportKey" to Base64.encodeToString(transportKey, Base64.NO_WRAP),
                "sourceSchema" to root.getInt("sourceSchema"),
                "rowCounts" to jsonObjectMap(counts)
            )
        } finally {
            passphrase.fill(0)
            transportKey?.fill(0)
            if (temporary.exists()) temporary.delete()
        }
    }

    fun archiveAfterImport(): Map<String, Any?> {
        val source = context.getDatabasePath(DATABASE_NAME)
        if (!source.exists()) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().putBoolean(COMPLETED, true).commit()
            return mapOf("status" to "already_absent")
        }
        val archive = File(context.filesDir, "legacy_room_archive")
        if (!archive.exists() && !archive.mkdirs()) error("Cannot create Room archive")
        val stamp = System.currentTimeMillis()
        val copied = mutableListOf<Pair<File, File>>()
        for (suffix in listOf("-wal", "-shm", "")) {
            val file = File(source.path + suffix)
            if (!file.exists()) continue
            val destination = File(archive, "$DATABASE_NAME.$stamp$suffix")
            file.copyTo(destination, overwrite = false)
            check(destination.length() == file.length()) { "Incomplete archive for ${file.name}" }
            copied += file to destination
        }
        val committed = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(COMPLETED, true).commit()
        check(committed) { "Cannot persist Room migration marker" }
        copied.forEach { (sourceFile, _) -> sourceFile.delete() }
        context.getSharedPreferences(CRYPTO_PREFS, Context.MODE_PRIVATE).edit()
            .remove(REGISTRATION_ID)
            .remove(IDENTITY_PAIR_LEGACY)
            .remove(IDENTITY_PAIR_ENCRYPTED)
            .commit()
        context.getSharedPreferences(KEYSTORE_META_PREFS, Context.MODE_PRIVATE).edit()
            .remove(LEGACY_DB_PASSPHRASE)
            .commit()
        File(context.cacheDir, "legacy_room_export_v22.aesgcm").delete()
        return mapOf("status" to "archived", "files" to copied.map { it.second.path })
    }

    private fun derivePassphrase(): ByteArray {
        val androidId = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ANDROID_ID
        ) ?: "fallback_no_android_id"
        return Mac.getInstance("HmacSHA256").run {
            init(SecretKeySpec(HMAC_SALT.toByteArray(Charsets.UTF_8), "HmacSHA256"))
            doFinal(androidId.toByteArray(Charsets.UTF_8))
        }
    }

    private fun openReadOnly(source: File, passphrase: ByteArray): SQLiteDatabase =
        SQLiteDatabase.openDatabase(
            source.path,
            passphrase,
            null,
            SQLiteDatabase.OPEN_READONLY,
            null
        )

    private fun readLegacyDbPassphrase(): ByteArray? {
        val encoded = context.getSharedPreferences(KEYSTORE_META_PREFS, Context.MODE_PRIVATE)
            .getString(LEGACY_DB_PASSPHRASE, null) ?: return null
        return decryptWithAndroidKeyStore(Base64.decode(encoded, Base64.NO_WRAP))
    }

    private fun tableExists(database: SQLiteDatabase, table: String): Boolean =
        database.rawQuery(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
            arrayOf(table)
        ).use { it.moveToFirst() }

    private fun readTable(database: SQLiteDatabase, table: String): JSONArray {
        val rows = JSONArray()
        database.rawQuery("SELECT * FROM `$table`", emptyArray<String>()).use { cursor ->
            while (cursor.moveToNext()) {
                val row = JSONObject()
                for (index in 0 until cursor.columnCount) {
                    val name = cursor.getColumnName(index)
                    val value: Any = when (cursor.getType(index)) {
                        Cursor.FIELD_TYPE_NULL -> JSONObject.NULL
                        Cursor.FIELD_TYPE_INTEGER -> cursor.getLong(index)
                        Cursor.FIELD_TYPE_FLOAT -> cursor.getDouble(index)
                        Cursor.FIELD_TYPE_BLOB -> JSONObject().put(
                            "base64",
                            Base64.encodeToString(cursor.getBlob(index), Base64.NO_WRAP)
                        )
                        else -> cursor.getString(index)
                    }
                    if (name in BLOB_COLUMNS && value !is JSONObject && value !== JSONObject.NULL) {
                        error("Expected BLOB in $table.$name")
                    }
                    row.put(name, value)
                }
                rows.put(row)
            }
        }
        return rows
    }

    private fun jsonObjectMap(value: JSONObject): Map<String, Int> =
        value.keys().asSequence().associateWith { value.getInt(it) }

    private fun readLocalCryptoState(): JSONObject {
        val prefs = context.getSharedPreferences(CRYPTO_PREFS, Context.MODE_PRIVATE)
        val result = JSONObject()
        if (prefs.contains(REGISTRATION_ID)) {
            result.put("local_registration_id", prefs.getInt(REGISTRATION_ID, -1).toString())
        }
        val encrypted = prefs.getString(IDENTITY_PAIR_ENCRYPTED, null)
        val legacy = prefs.getString(IDENTITY_PAIR_LEGACY, null)
        val pair = when {
            encrypted != null -> decryptWithAndroidKeyStore(Base64.decode(encrypted, Base64.NO_WRAP))
            legacy != null -> Base64.decode(legacy, Base64.NO_WRAP)
            else -> null
        }
        if (pair != null) {
            result.put("local_identity_key_pair_v1", Base64.encodeToString(pair, Base64.NO_WRAP))
            pair.fill(0)
        }
        return result
    }

    private fun decryptWithAndroidKeyStore(envelope: ByteArray): ByteArray {
        require(envelope.size > 28) { "Invalid encrypted identity pair" }
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val key = keyStore.getKey(MASTER_KEY_ALIAS, null) as? SecretKey
            ?: error("Legacy Android Keystore identity key is unavailable")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, envelope.copyOfRange(0, 12)))
        return cipher.doFinal(envelope.copyOfRange(12, envelope.size))
    }

    /** File format: 12-byte nonce + ciphertext + 16-byte GCM tag. */
    private fun encryptTransport(plaintext: ByteArray, key: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"))
        return cipher.iv + cipher.doFinal(plaintext)
    }
}
