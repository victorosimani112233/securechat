package com.securechat.signaling

import com.securechat.signaling.db.Database
import java.sql.Connection

/**
 * Private-directory OPRF degerlendirmeleri icin kalici gunluk kota.
 *
 * Redis sliding window'u tek basina yeterli degildi: bu dagitimda Redis
 * kasten kalicisizdir (RDB kapali). Restart, failover ya da bellek baskisi
 * tum sayaclari sifirliyor ve bir hesap gunluk aday sinirini istedigi kadar
 * tekrarlayabiliyordu — yani rehber enumeration'ina karsi kotanin kendisi
 * yeniden denenebilir bir engeldi.
 *
 * Sayac PostgreSQL'de, hesabin blind index'i altinda tutulur. Ham user_id
 * yazilmaz; yalniz gun kovasi ve o gun harcanan aday sayisi durur, dolayisiyla
 * bir davranis zaman cizelgesi olusmaz. Satirlar retention worker tarafindan
 * iki gun sonra silinir.
 *
 * Kontrol tek bir atomik ifadedir: es zamanli iki istek de "sinir altinda"
 * okuyup ikisi de gecemez.
 */
object DirectoryQuota {

    /** Gun basina en fazla aday. Batch 256 oldugu icin 32 batch/gun demektir. */
    const val DAILY_CANDIDATE_LIMIT = 8_192

    /** Kayitlar bu kadar gun sonra anlamsizdir ve silinir. */
    const val RETENTION_DAYS = 2

    private const val CONSUME_SQL = """
        INSERT INTO directory_quota AS q (account_index, day_bucket, used, updated_at)
        VALUES (?, ?, ?, NOW())
        ON CONFLICT (account_index) DO UPDATE
           SET used = CASE
                          WHEN q.day_bucket = EXCLUDED.day_bucket
                          THEN q.used + EXCLUDED.used
                          ELSE EXCLUDED.used
                      END,
               day_bucket = EXCLUDED.day_bucket,
               updated_at = NOW()
         WHERE q.day_bucket <> EXCLUDED.day_bucket
            OR q.used + EXCLUDED.used <= ?
        RETURNING used
    """

    /**
     * Kotadan [cost] aday duser.
     *
     * Sinir asilirsa hicbir sey yazilmaz ve `false` doner: reddedilen istek
     * kotayi tuketmemelidir, aksi halde sinira dayanan bir hesap kendini
     * kalici olarak kilitleyebilirdi.
     */
    fun tryConsume(
        userId: String,
        cost: Int,
        nowMillis: Long = System.currentTimeMillis(),
        limit: Int = DAILY_CANDIDATE_LIMIT,
    ): Boolean {
        require(cost in 1..limit) { "Invalid directory quota cost" }
        return Database.getConnection().use { connection ->
            consume(connection, userId, cost, nowMillis, limit)
        }
    }

    internal fun consume(
        connection: Connection,
        userId: String,
        cost: Int,
        nowMillis: Long,
        limit: Int,
    ): Boolean = connection.prepareStatement(CONSUME_SQL).use { statement ->
        statement.setString(1, ServerPrivacy.blindIndex("directory-quota", userId))
        statement.setInt(2, dayBucket(nowMillis))
        statement.setInt(3, cost)
        statement.setInt(4, limit)
        statement.executeQuery().use { rows -> rows.next() }
    }

    /** Gun kovasi UTC'dir; yerel saat dilimi kullanicinin konumunu ima ederdi. */
    internal fun dayBucket(nowMillis: Long): Int = (nowMillis / 86_400_000L).toInt()

    /** Retention: eski gun kovalari silinir. */
    fun purgeExpired(connection: Connection, nowMillis: Long = System.currentTimeMillis()): Int =
        connection.prepareStatement("DELETE FROM directory_quota WHERE day_bucket < ?")
            .use { statement ->
                statement.setInt(1, dayBucket(nowMillis) - RETENTION_DAYS)
                statement.executeUpdate()
            }
}
