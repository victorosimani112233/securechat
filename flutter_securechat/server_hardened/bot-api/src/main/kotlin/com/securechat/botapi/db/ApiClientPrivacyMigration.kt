package com.securechat.botapi.db

import org.slf4j.LoggerFactory

private val apiClientMigrationLog = LoggerFactory.getLogger("ApiClientPrivacyMigration")

/** Fail-closed in-place encryption of legacy API-client private fields. */
object ApiClientPrivacyMigration {
    fun migrateAndVerify() {
        BotDatabase.getConnection().use { conn ->
            conn.autoCommit = false
            try {
                var migrated = 0
                conn.prepareStatement(
                    "SELECT kid, name, allow_list FROM api_client FOR UPDATE"
                ).use { select ->
                    select.executeQuery().use { rows ->
                        while (rows.next()) {
                            val kid = rows.getString("kid")
                            val storedName = rows.getString("name")
                            val storedAllowList =
                                (rows.getArray("allow_list").array as Array<*>)
                                    .map { it.toString() }

                            val sealedName = if (ApiClientPrivateFields.isSealed(storedName)) {
                                ApiClientPrivateFields.openName(kid, storedName)
                                storedName
                            } else {
                                ApiClientPrivateFields.sealName(kid, storedName)
                            }
                            val sealedAllowList = if (
                                storedAllowList.size == 1 &&
                                ApiClientPrivateFields.isSealed(storedAllowList.single())
                            ) {
                                ApiClientPrivateFields.openAllowList(kid, storedAllowList.single())
                                storedAllowList.single()
                            } else {
                                ApiClientPrivateFields.sealAllowList(kid, storedAllowList)
                            }

                            if (sealedName != storedName ||
                                storedAllowList != listOf(sealedAllowList)
                            ) {
                                conn.prepareStatement(
                                    "UPDATE api_client SET name = ?, allow_list = ?, updated_at = NOW() WHERE kid = ?"
                                ).use { update ->
                                    update.setString(1, sealedName)
                                    update.setArray(
                                        2,
                                        conn.createArrayOf("TEXT", arrayOf(sealedAllowList))
                                    )
                                    update.setString(3, kid)
                                    check(update.executeUpdate() == 1) {
                                        "API client privacy migration lost its source row"
                                    }
                                }
                                migrated++
                            }
                        }
                    }
                }
                conn.commit()
                if (migrated > 0) {
                    apiClientMigrationLog.info(
                        "[Privacy] {} API client kaydi sifrelendi",
                        migrated
                    )
                }
            } catch (e: Exception) {
                conn.rollback()
                throw IllegalStateException("API client privacy migration failed", e)
            } finally {
                conn.autoCommit = true
            }
        }
    }
}
