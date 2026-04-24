package com.securechat.app.util

import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.input.OffsetMapping
import androidx.compose.ui.text.input.TransformedText
import androidx.compose.ui.text.input.VisualTransformation

/**
 * Telefon numarasini 555 555 55 55 formatinda gosterir.
 * Sadece gorsel donusum yapar, gercek deger degismez.
 * Format: XXX XXX XX XX (maksimum 10 hane)
 */
class PhoneVisualTransformation(private val maxDigits: Int = 10) : VisualTransformation {
    override fun filter(text: AnnotatedString): TransformedText {
        val digits = text.text.filter { it.isDigit() }.take(maxDigits)
        val formatted = buildString {
            for (i in digits.indices) {
                if (i == 3 || i == 6 || i == 8) append(' ')
                append(digits[i])
            }
        }

        val offsetMapping = object : OffsetMapping {
            override fun originalToTransformed(offset: Int): Int {
                val digitOffset = offset.coerceAtMost(digits.length)
                var transformed = 0
                var digitCount = 0
                for (ch in formatted) {
                    if (digitCount >= digitOffset) break
                    transformed++
                    if (ch != ' ') digitCount++
                }
                return transformed
            }

            override fun transformedToOriginal(offset: Int): Int {
                val boundedOffset = offset.coerceAtMost(formatted.length)
                var original = 0
                for (i in 0 until boundedOffset) {
                    if (formatted[i] != ' ') original++
                }
                return original.coerceAtMost(digits.length)
            }
        }

        return TransformedText(AnnotatedString(formatted), offsetMapping)
    }
}
