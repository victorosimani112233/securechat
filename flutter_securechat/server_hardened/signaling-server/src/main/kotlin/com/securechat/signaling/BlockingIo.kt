package com.securechat.signaling

import java.util.concurrent.Executors
import java.util.concurrent.ThreadFactory
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.withContext

/**
 * PostgreSQL ve Redis cagrilarinin calistigi ayrilmis blocking havuzu.
 *
 * JDBC ve Jedis bloklayan kutuphanelerdir. Ktor/Netty'de route ve WebSocket
 * isleyicileri varsayilan olarak `callGroupSize` kadar — pratikte cekirdek
 * sayisi kadar — event-loop thread'inde calisir. Bu thread'lerde bloklamak
 * HikariCP'nin 20, Jedis'in 50 baglantisini anlamsiz kilar: 4 vCPU'lu bir
 * makinede es zamanli veritabani islemi dortte kalir ve ayni thread'ler
 * WebSocket I/O'sunu da tasidigi icin tek bir yavas sorgu butun sunucunun
 * gecikmesine yansir.
 *
 * Bloklayan is buraya alinir; event-loop yalniz ag olaylarini surer. Havuz
 * boyutu baglanti havuzlariyla ayni buyukluk mertebesinde tutulur, cunku
 * daha fazlasi yalniz havuz bekleme kuyrugunu thread'lere tasir.
 */
object BlockingIo {
    private const val MINIMUM_THREADS = 32
    private const val MAXIMUM_THREADS = 256

    val threadCount: Int = resolveThreadCount(System.getenv("BLOCKING_IO_THREADS"))

    internal fun resolveThreadCount(configured: String?): Int {
        val requested = configured?.trim()?.toIntOrNull()
            ?: (Runtime.getRuntime().availableProcessors() * 8)
        return requested.coerceIn(MINIMUM_THREADS, MAXIMUM_THREADS)
    }

    private val factory = object : ThreadFactory {
        private val counter = AtomicInteger(1)
        override fun newThread(runnable: Runnable): Thread =
            Thread(runnable, "securechat-blocking-${counter.getAndIncrement()}").apply {
                isDaemon = true
            }
    }

    val dispatcher: CoroutineDispatcher by lazy {
        Executors.newFixedThreadPool(threadCount, factory).asCoroutineDispatcher()
    }
}

/**
 * Bloklayan bir cagriyi ayrilmis havuza tasir.
 *
 * Zaten bu havuzdaysa `withContext` ek bir gecis yapmaz, bu yuzden ic ice
 * kullanim maliyetsizdir.
 */
suspend inline fun <T> blockingIo(crossinline block: () -> T): T =
    withContext(BlockingIo.dispatcher) { block() }
