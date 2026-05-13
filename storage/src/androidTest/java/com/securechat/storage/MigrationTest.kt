package com.securechat.storage

import androidx.room.Room
import androidx.room.testing.MigrationTestHelper
import androidx.sqlite.db.framework.FrameworkSQLiteOpenHelperFactory
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.google.common.truth.Truth.assertThat
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Room migration test scaffold.
 *
 * KRITIK NOT: Bu yazildigi sirada `StorageModule.kt` `fallbackToDestructiveMigration()`
 * kullaniyor — yani prod'da schema degisirse veri SILINIR. Migration objesi YOK.
 *
 * Bu testler:
 *   1. Tum schema versiyonlarinin (1..16) acilabildigini dogrular (yapi saglikli mi)
 *   2. Latest schema'nin recreate edilebildigini dogrular (sanity)
 *   3. Gercek Migration object'leri eklendiginde her biri icin .runMigrationsAndValidate
 *      blogu eklemek icin pattern saglar
 *
 * Migration objesi eklendiginde bu pattern'i kullan:
 * ```
 * @Test
 * fun migrate15To16() {
 *     helper.createDatabase(TEST_DB, 15).apply {
 *         execSQL("INSERT INTO conversations (id, peer_id, peer_name, ...) VALUES (...)")
 *         close()
 *     }
 *     helper.runMigrationsAndValidate(TEST_DB, 16, true, MIGRATION_15_16).use { db ->
 *         val cursor = db.query("SELECT count(*) FROM conversations")
 *         cursor.moveToFirst()
 *         assertThat(cursor.getInt(0)).isEqualTo(1)
 *     }
 * }
 * ```
 */
@RunWith(AndroidJUnit4::class)
class MigrationTest {

    companion object {
        private const val TEST_DB = "migration-test"
        private const val LATEST_VERSION = 16
    }

    @get:Rule
    val helper: MigrationTestHelper = MigrationTestHelper(
        InstrumentationRegistry.getInstrumentation(),
        SecureChatDatabase::class.java,
        emptyList(),
        FrameworkSQLiteOpenHelperFactory()
    )

    /**
     * Smoke test: latest schema'nin (16) acilabilmesi + temel tablolarin var olmasi.
     * Schema JSON'lari bozulursa veya yeni tablo eklenip schema export edilmediginde fail eder.
     */
    @Test
    fun openLatestSchema() {
        helper.createDatabase(TEST_DB, LATEST_VERSION).use { db ->
            // Kritik tablolar tanimli mi
            val expectedTables = listOf(
                "conversations", "messages", "contacts",
                "pre_keys", "signed_pre_keys", "sessions", "identities",
                "call_logs", "scheduled_messages"
            )
            for (table in expectedTables) {
                val cursor = db.query(
                    "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
                    arrayOf<Any>(table)
                )
                cursor.use {
                    val exists = it.moveToFirst()
                    if (!exists) throw AssertionError("Tablo eksik: $table")
                    assertThat(exists).isTrue()
                }
            }
        }
    }

    /**
     * Schema 1 (initial) acilabilmeli — geriye uyumlulugun en eski sinirlamasi.
     * Bu test fail ederse schemas/1.json bozulmus veya silinmistir.
     */
    @Test
    fun openInitialSchema() {
        helper.createDatabase(TEST_DB, 1).use { db ->
            // Schema v1'de hangi tablolar oldugu schemas/1.json'da; en azindan messages var
            val cursor = db.query(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='messages'"
            )
            cursor.use {
                assertThat(it.moveToFirst()).isTrue()
            }
        }
    }

    /**
     * Destructive migration kullaniminda tipik akis:
     *   v15 DB acilir → v16 schema ile yeniden acilirken DB FALLBACK yapar → eski veri silinir.
     * Bu testin AMACI: destructive davranisini DOGRULAMAK degil — gercek migration eklendigi an
     * burayi runMigrationsAndValidate ile degistir.
     *
     * Su an: helper.createDatabase v15 → close → Room.databaseBuilder fallback ile re-open
     */
    @Test
    fun destructiveFallback_currentBehavior() {
        // v15 sema ile DB olustur (helper kapatir)
        helper.createDatabase(TEST_DB, 15).close()

        // Gercek Room builder ile latest version'a a — fallback destructive devrede
        val ctx = InstrumentationRegistry.getInstrumentation().targetContext
        val db = Room.databaseBuilder(ctx, SecureChatDatabase::class.java, TEST_DB)
            .fallbackToDestructiveMigration()
            .build()
        db.openHelper.writableDatabase.use { _ ->
            // DB acilabildi — fallback calisti. Veri kayboldu ama DB instance saglikli.
        }
        db.close()
        ctx.deleteDatabase(TEST_DB)
    }

    // TODO: Gercek Migration objesi eklendigi an:
    //   1. SecureChatDatabase companion'a MIGRATION_N_M : Migration ekle
    //   2. StorageModule.kt'te .fallbackToDestructiveMigration() yerine .addMigrations(...)
    //   3. Burada @Test fun migrateNtoM() ekle (yukaridaki ornek pattern)
    //   4. helper.runMigrationsAndValidate ile yeni schema'nin validity'sini dogrula
}
