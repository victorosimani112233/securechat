package com.securechat.signaling

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class ReviewDemoTest {
    private val now = Instant.parse("2026-10-07T12:00:00Z")

    @AfterEach
    fun reset() = ReviewDemo.resetForTest(null)

    private fun enable(until: String = "2026-10-20") =
        ReviewDemo.resetForTest(ReviewDemo.parse("Review@Example.com, second@example.com", "418273", until))

    @Test
    fun `disabled unless all inputs are present and valid`() {
        assertNull(ReviewDemo.parse(null, null, null))
        assertThrows(IllegalArgumentException::class.java) { ReviewDemo.parse("a@b.co", null, "2026-10-20") }
        assertThrows(IllegalArgumentException::class.java) { ReviewDemo.parse("a@b.co", "111111", "2026-10-20") }
        assertThrows(IllegalArgumentException::class.java) { ReviewDemo.parse("a@b.co", "12345", "2026-10-20") }
        assertThrows(IllegalArgumentException::class.java) {
            ReviewDemo.parse("a@b.co,b@b.co,c@b.co", "418273", "2026-10-20")
        }
        assertThrows(IllegalStateException::class.java) { ReviewDemo.parse("a@b.co", "418273", "soon") }
    }

    @Test
    fun `only listed addresses get the fixed code, case-insensitively`() {
        enable()
        assertEquals("418273", ReviewDemo.issueCode(" review@example.com ", now))
        assertEquals("418273", ReviewDemo.issueCode("SECOND@example.com", now))
        assertNull(ReviewDemo.issueCode("someone@example.com", now))
        assertFalse(ReviewDemo.isDemo("someone@example.com", now))
    }

    @Test
    fun `expires at the end of the until day`() {
        enable(until = "2026-10-07")
        assertTrue(ReviewDemo.isDemo("review@example.com", Instant.parse("2026-10-07T23:59:59Z")))
        assertNull(ReviewDemo.issueCode("review@example.com", Instant.parse("2026-10-08T00:00:00Z")))
    }

    @Test
    fun `issue quota bounds total guesses`() {
        enable()
        repeat(ReviewDemo.MAX_ISSUES) {
            assertEquals("418273", ReviewDemo.issueCode("review@example.com", now))
        }
        assertNull(ReviewDemo.issueCode("review@example.com", now))
    }

    @Test
    fun `production refuses an open-ended demo window`() {
        fun env(until: LocalDate) = mapOf(
            "REVIEW_DEMO_EMAILS" to "review@example.com",
            "REVIEW_DEMO_OTP" to "418273",
            "REVIEW_DEMO_UNTIL" to until.toString(),
        )
        val today = now.atZone(ZoneOffset.UTC).toLocalDate()

        ReviewDemo.requireBoundedForProduction(emptyMap(), now)
        ReviewDemo.requireBoundedForProduction(env(today.plusDays(ReviewDemo.MAX_PRODUCTION_DAYS)), now)
        assertThrows(IllegalArgumentException::class.java) {
            ReviewDemo.requireBoundedForProduction(env(today.plusDays(ReviewDemo.MAX_PRODUCTION_DAYS + 2)), now)
        }
    }
}
