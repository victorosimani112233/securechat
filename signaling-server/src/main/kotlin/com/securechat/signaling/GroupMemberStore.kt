package com.securechat.signaling

import com.securechat.signaling.db.Database
import com.securechat.signaling.db.RedisManager
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("GroupMemberStore")

/**
 * Grup uyelik bilgilerini yoneten store.
 * PostgreSQL'de kalici, Redis'te cache (TTL 5 dk).
 *
 * GroupNotification mesajlarindan otomatik guncellenir.
 * GROUP_MESSAGE_FANOUT ve typing indicator fanout icin kullanilir.
 */
object GroupMemberStore {

    private const val CACHE_TTL = 300L // 5 dakika

    /**
     * Gruptaki tum uyeleri doner. Oncelikle Redis cache kontrol edilir.
     */
    fun getMembers(groupId: String): Set<String> {
        // Redis cache kontrol
        try {
            val cached = RedisManager.use { jedis ->
                jedis.smembers("group_members:$groupId")
            }
            if (!cached.isNullOrEmpty()) return cached
        } catch (_: Exception) { }

        // DB'den oku
        val members = mutableSetOf<String>()
        try {
            Database.getConnection().use { conn ->
                conn.prepareStatement("SELECT user_id FROM group_members WHERE group_id = ?").use { stmt ->
                    stmt.setString(1, groupId)
                    val rs = stmt.executeQuery()
                    while (rs.next()) {
                        members.add(rs.getString("user_id"))
                    }
                }
            }
            // Redis'e cache'le
            if (members.isNotEmpty()) {
                try {
                    RedisManager.use { jedis ->
                        val key = "group_members:$groupId"
                        jedis.del(key)
                        jedis.sadd(key, *members.toTypedArray())
                        jedis.expire(key, CACHE_TTL)
                    }
                } catch (_: Exception) { }
            }
        } catch (e: Exception) {
            log.warn("[!] GroupMemberStore DB okuma hatasi: ${e.message}")
        }
        return members
    }

    /**
     * Grup uye listesini toplu gunceller (tam liste).
     * Mevcut uyelik silinir, yeni liste eklenir.
     */
    fun setMembers(groupId: String, members: Collection<String>) {
        try {
            Database.getConnection().use { conn ->
                conn.autoCommit = false
                try {
                    // Mevcut uyeleri sil
                    conn.prepareStatement("DELETE FROM group_members WHERE group_id = ?").use { stmt ->
                        stmt.setString(1, groupId)
                        stmt.executeUpdate()
                    }
                    // Yeni uyeleri ekle
                    conn.prepareStatement("INSERT INTO group_members (group_id, user_id) VALUES (?, ?::uuid) ON CONFLICT DO NOTHING").use { stmt ->
                        for (userId in members) {
                            stmt.setString(1, groupId)
                            stmt.setString(2, userId)
                            stmt.addBatch()
                        }
                        stmt.executeBatch()
                    }
                    conn.commit()
                } catch (e: Exception) {
                    conn.rollback()
                    throw e
                } finally {
                    conn.autoCommit = true
                }
            }
            // Redis cache guncelle
            updateCache(groupId, members)
            log.info("[G] Grup uyeleri guncellendi: $groupId (${members.size} uye)")
        } catch (e: Exception) {
            log.warn("[!] GroupMemberStore setMembers hatasi: ${e.message}")
        }
    }

    /**
     * Gruba tek uye ekler.
     */
    fun addMember(groupId: String, userId: String) {
        try {
            Database.getConnection().use { conn ->
                conn.prepareStatement(
                    "INSERT INTO group_members (group_id, user_id) VALUES (?, ?::uuid) ON CONFLICT DO NOTHING"
                ).use { stmt ->
                    stmt.setString(1, groupId)
                    stmt.setString(2, userId)
                    stmt.executeUpdate()
                }
            }
            // Cache invalidate
            invalidateCache(groupId)
        } catch (e: Exception) {
            log.warn("[!] GroupMemberStore addMember hatasi: ${e.message}")
        }
    }

    /**
     * Gruptan tek uye cikarir.
     */
    fun removeMember(groupId: String, userId: String) {
        try {
            Database.getConnection().use { conn ->
                conn.prepareStatement(
                    "DELETE FROM group_members WHERE group_id = ? AND user_id = ?::uuid"
                ).use { stmt ->
                    stmt.setString(1, groupId)
                    stmt.setString(2, userId)
                    stmt.executeUpdate()
                }
            }
            invalidateCache(groupId)
        } catch (e: Exception) {
            log.warn("[!] GroupMemberStore removeMember hatasi: ${e.message}")
        }
    }

    private fun updateCache(groupId: String, members: Collection<String>) {
        try {
            RedisManager.use { jedis ->
                val key = "group_members:$groupId"
                jedis.del(key)
                if (members.isNotEmpty()) {
                    jedis.sadd(key, *members.toTypedArray())
                    jedis.expire(key, CACHE_TTL)
                }
            }
        } catch (_: Exception) { }
    }

    private fun invalidateCache(groupId: String) {
        try {
            RedisManager.use { jedis ->
                jedis.del("group_members:$groupId")
            }
        } catch (_: Exception) { }
    }
}
