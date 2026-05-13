package com.securechat.app.scheduler

import com.google.common.truth.Truth.assertThat
import com.securechat.app.ui.viewmodel.RepeatType
import com.securechat.app.ui.viewmodel.ScheduledMessageViewModel
import org.junit.Test
import java.util.Calendar

/**
 * `ScheduledMessageViewModel.calculateNextTrigger` icin pure logic testleri.
 *
 * Bu fonksiyon planli mesajlarin tekrarlama mantiginin kalbi. Dakikasi dakikasina
 * dogru calismasi kritik — yanlis hesap kullanicinin mesaji yanlis gunde gonderir.
 *
 * PATTERN: pure logic + deterministic, hicbir mock gerektirmez. Yeni feature testlerinde
 * boyle baslamak en iyisi.
 */
class CalculateNextTriggerTest {

    @Test
    fun `ONCE - bugun gec saat secildi - yarinin ayni saatine kayar`() {
        val now = Calendar.getInstance()
        val pastHour = (now.get(Calendar.HOUR_OF_DAY) - 2).coerceAtLeast(0)
        val pastMinute = now.get(Calendar.MINUTE)

        val nextTrigger = ScheduledMessageViewModel.calculateNextTrigger(
            hour = pastHour,
            minute = pastMinute,
            repeatType = RepeatType.ONCE,
            days = emptySet()
        )

        val target = Calendar.getInstance().apply { timeInMillis = nextTrigger }
        // Yarin secilen saate kaymali
        assertThat(target.get(Calendar.HOUR_OF_DAY)).isEqualTo(pastHour)
        assertThat(target.get(Calendar.MINUTE)).isEqualTo(pastMinute)
        assertThat(target.timeInMillis).isGreaterThan(System.currentTimeMillis())
    }

    @Test
    fun `ONCE - bugun ileri saat secildi - bugune kalir`() {
        val now = Calendar.getInstance()
        val futureHour = (now.get(Calendar.HOUR_OF_DAY) + 2).coerceAtMost(23)
        // 23+ kapsayan edge case'i atla — gec gece test calismasinda yanlis sonuc
        if (futureHour <= now.get(Calendar.HOUR_OF_DAY)) return

        val nextTrigger = ScheduledMessageViewModel.calculateNextTrigger(
            hour = futureHour,
            minute = 0,
            repeatType = RepeatType.ONCE,
            days = emptySet()
        )

        val target = Calendar.getInstance().apply { timeInMillis = nextTrigger }
        assertThat(target.get(Calendar.DAY_OF_YEAR)).isEqualTo(now.get(Calendar.DAY_OF_YEAR))
        assertThat(target.get(Calendar.HOUR_OF_DAY)).isEqualTo(futureHour)
    }

    @Test
    fun `DAILY - past saat - yarinin saatine kayar`() {
        val now = Calendar.getInstance()
        val pastHour = (now.get(Calendar.HOUR_OF_DAY) - 1).coerceAtLeast(0)

        val nextTrigger = ScheduledMessageViewModel.calculateNextTrigger(
            hour = pastHour,
            minute = 30,
            repeatType = RepeatType.DAILY,
            days = emptySet()
        )

        assertThat(nextTrigger).isGreaterThan(System.currentTimeMillis())
        val target = Calendar.getInstance().apply { timeInMillis = nextTrigger }
        assertThat(target.get(Calendar.MINUTE)).isEqualTo(30)
    }

    @Test
    fun `CUSTOM - gun listesi bos - DAILY gibi davranir`() {
        val nextTrigger = ScheduledMessageViewModel.calculateNextTrigger(
            hour = 9,
            minute = 0,
            repeatType = RepeatType.CUSTOM,
            days = emptySet()
        )
        assertThat(nextTrigger).isGreaterThan(System.currentTimeMillis())
    }

    @Test
    fun `CUSTOM - sadece secili gunlere kayar`() {
        // Pazartesi (1) + Carsamba (3) sec; hangi gun olursak olalim sonraki Pzt veya Car'a kaymali
        val nextTrigger = ScheduledMessageViewModel.calculateNextTrigger(
            hour = 10,
            minute = 0,
            repeatType = RepeatType.CUSTOM,
            days = setOf(1, 3) // Pzt + Car
        )

        val target = Calendar.getInstance().apply { timeInMillis = nextTrigger }
        val dayOfWeek = target.get(Calendar.DAY_OF_WEEK)
        // Calendar: Mon=2, Wed=4
        assertThat(dayOfWeek).isAnyOf(Calendar.MONDAY, Calendar.WEDNESDAY)
        assertThat(target.get(Calendar.HOUR_OF_DAY)).isEqualTo(10)
    }

    @Test
    fun `CUSTOM - bugun secili VE saat gelmedi - bugune kalir`() {
        val now = Calendar.getInstance()
        val futureHour = (now.get(Calendar.HOUR_OF_DAY) + 2)
        if (futureHour > 23) return // gec gece testini atla

        // Bugunun Calendar.DAY_OF_WEEK'ini bizim format'a cevir (Pzt=1...Paz=7)
        val todayOur = when (now.get(Calendar.DAY_OF_WEEK)) {
            Calendar.MONDAY -> 1; Calendar.TUESDAY -> 2
            Calendar.WEDNESDAY -> 3; Calendar.THURSDAY -> 4
            Calendar.FRIDAY -> 5; Calendar.SATURDAY -> 6
            Calendar.SUNDAY -> 7; else -> 1
        }

        val nextTrigger = ScheduledMessageViewModel.calculateNextTrigger(
            hour = futureHour,
            minute = 0,
            repeatType = RepeatType.CUSTOM,
            days = setOf(todayOur)
        )

        val target = Calendar.getInstance().apply { timeInMillis = nextTrigger }
        // Bugune kalmali — saat geleceğe ayarli
        assertThat(target.get(Calendar.DAY_OF_YEAR)).isEqualTo(now.get(Calendar.DAY_OF_YEAR))
    }
}
