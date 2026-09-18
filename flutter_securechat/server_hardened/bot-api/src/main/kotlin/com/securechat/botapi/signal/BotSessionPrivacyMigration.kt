package com.securechat.botapi.signal

import com.securechat.botapi.db.BotDatabase
/**
 * Fail-closed verification of the final V14 bot-session schema.
 *
 * Pre-V14 raw-recipient conversion belongs to the staged V13 deployment. V14
 * refuses to drop its compatibility column while any such row exists, so this
 * production binary never reads or writes a raw recipient UUID column.
 */
object BotSessionPrivacyMigration {
    fun migrateAndVerify() {
        BotDatabase.getConnection().use { conn ->
            try {
                conn.prepareStatement(
                    """SELECT recipient_index, session_record
                       FROM bot_signal_session"""
                ).use { verify ->
                    verify.executeQuery().use { rows ->
                        while (rows.next()) {
                            check(!rows.getString(1).isNullOrBlank()) {
                                "Bot session recipient index migration incomplete"
                            }
                            check(BotSessionRecordCipher.isSealed(rows.getBytes(2))) {
                                "Plaintext bot Signal session record rejected"
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                throw IllegalStateException("Bot session privacy verification failed", e)
            }
        }
    }
}
