package com.securechat.signaling

import org.jetbrains.kotlinx.lincheck.annotations.Operation
import org.jetbrains.kotlinx.lincheck.check
import org.jetbrains.kotlinx.lincheck.strategy.managed.modelchecking.ModelCheckingOptions
import org.jetbrains.kotlinx.lincheck.strategy.stress.StressOptions
import org.junit.jupiter.api.Test

/**
 * `GroupCallSessionStore`'un eszamanlilik dogrulugu — linearizability.
 *
 * Executor-tabanli testler "es zamanli iki istek yarisir" senaryosunun
 * yalniz birkac serpistirmesini dener. Lincheck yerine olasi TUM
 * serpistirmeleri model-checking ile kesif eder: her eszamanli calisma bir
 * ardisik siralamayla aciklanabilmeli (linearizable). Aciklanamayan bir
 * gecmis = lock disi bir yaris = veri kaybi/kapasite asimi.
 *
 * Hedef invaryant: `addParticipant` per-group `synchronized` blok altinda
 * kapasiteyi kontrol eder; es zamanli eklemeler tavani ASLA asmamalidir ve
 * katilimci kumesi kayip guncelleme yasamamalidir.
 *
 * `GroupCallSessionStore` global bir `object` oldugu icin her senaryo
 * benzersiz bir groupId ile calisir ve `init` o grubu sifir katilimciyla
 * kurar; senaryolar birbirinin durumunu gormez.
 */
class GroupCallSessionStoreLincheckTest {

    // Her test instance'i (senaryo) icin ayri grup — global object'te izolasyon.
    private val groupId = "lincheck-" + counter.getAndIncrement()

    init {
        GroupCallSessionStore.start(
            groupId = groupId,
            callId = "c",
            coordinatorId = "coord",
            callType = "VOICE",
            participants = emptyList(),
            mode = "MESH",
        )
    }

    @Operation
    fun add(userId: Int): GroupCallSessionStore.JoinResult =
        GroupCallSessionStore.addParticipant(
            groupId = groupId,
            userId = "u$userId",
            capacity = CAPACITY,
            mediaE2ee = false,
        )

    @Operation
    fun remove(userId: Int): Boolean =
        GroupCallSessionStore.removeParticipant(groupId, "u$userId")

    @Operation
    fun size(): Int = GroupCallSessionStore.get(groupId)?.participants?.size ?: -1

    /**
     * Model-checking: kucuk senaryolarda tum serpistirmeler kesfedilir.
     * Sonuclar linearizable degilse (ornegin iki ekleme kapasiteyi asarsa)
     * Lincheck karsi-ornek uretir.
     */
    @Test
    fun modelCheckingLinearizable() {
        ModelCheckingOptions()
            .iterations(60)
            .threads(3)
            .actorsPerThread(3)
            .actorsBefore(1)
            .check(this::class)
    }

    /** Stress: gercek thread'lerle yuksek-hacim yaris. */
    @Test
    fun stressLinearizable() {
        StressOptions()
            .iterations(30)
            .threads(3)
            .actorsPerThread(4)
            .check(this::class)
    }

    companion object {
        private const val CAPACITY = 3
        private val counter = java.util.concurrent.atomic.AtomicInteger(0)
    }
}
