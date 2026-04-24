package com.securechat.app.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.securechat.app.ui.theme.LocalDarkTheme
import com.securechat.app.ui.theme.glass

/**
 * Ulke kodu secici. Varsayilan +90 (Turkiye).
 * Kullanici tiklayinca acilir menudan baska ulke kodu secebilir.
 */
data class CountryCode(
    val code: String,
    val flag: String,
    val name: String
)

val COUNTRY_CODES = listOf(
    CountryCode("+90", "\uD83C\uDDF9\uD83C\uDDF7", "Türkiye"),
    CountryCode("+1", "\uD83C\uDDFA\uD83C\uDDF8", "ABD / Kanada"),
    CountryCode("+44", "\uD83C\uDDEC\uD83C\uDDE7", "Birleşik Krallık"),
    CountryCode("+49", "\uD83C\uDDE9\uD83C\uDDEA", "Almanya"),
    CountryCode("+33", "\uD83C\uDDEB\uD83C\uDDF7", "Fransa"),
    CountryCode("+31", "\uD83C\uDDF3\uD83C\uDDF1", "Hollanda"),
    CountryCode("+39", "\uD83C\uDDEE\uD83C\uDDF9", "İtalya"),
    CountryCode("+34", "\uD83C\uDDEA\uD83C\uDDF8", "İspanya"),
    CountryCode("+7", "\uD83C\uDDF7\uD83C\uDDFA", "Rusya"),
    CountryCode("+994", "\uD83C\uDDE6\uD83C\uDDFF", "Azerbaycan"),
    CountryCode("+993", "\uD83C\uDDF9\uD83C\uDDF2", "Türkmenistan"),
    CountryCode("+998", "\uD83C\uDDFA\uD83C\uDDFF", "Özbekistan"),
    CountryCode("+996", "\uD83C\uDDF0\uD83C\uDDEC", "Kırgızistan"),
    CountryCode("+7", "\uD83C\uDDF0\uD83C\uDDFF", "Kazakistan"),
    CountryCode("+966", "\uD83C\uDDF8\uD83C\uDDE6", "Suudi Arabistan"),
    CountryCode("+971", "\uD83C\uDDE6\uD83C\uDDEA", "BAE"),
    CountryCode("+91", "\uD83C\uDDEE\uD83C\uDDF3", "Hindistan"),
    CountryCode("+86", "\uD83C\uDDE8\uD83C\uDDF3", "Çin"),
    CountryCode("+81", "\uD83C\uDDEF\uD83C\uDDF5", "Japonya"),
    CountryCode("+82", "\uD83C\uDDF0\uD83C\uDDF7", "Güney Kore"),
    CountryCode("+55", "\uD83C\uDDE7\uD83C\uDDF7", "Brezilya"),
    CountryCode("+61", "\uD83C\uDDE6\uD83C\uDDFA", "Avustralya"),
)

@Composable
fun CountryCodePicker(
    selectedCode: CountryCode,
    onCodeSelected: (CountryCode) -> Unit,
    modifier: Modifier = Modifier
) {
    val dark = LocalDarkTheme.current
    var expanded by remember { mutableStateOf(false) }

    Box(modifier = modifier) {
        Row(
            modifier = Modifier
                .glass(dark = dark, shape = RoundedCornerShape(12.dp))
                .clickable { expanded = true }
                .padding(horizontal = 12.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = selectedCode.flag,
                style = MaterialTheme.typography.bodyLarge
            )
            Spacer(modifier = Modifier.width(4.dp))
            Text(
                text = selectedCode.code,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface
            )
            Icon(
                Icons.Default.ArrowDropDown,
                contentDescription = "Ülke kodu seç",
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false }
        ) {
            COUNTRY_CODES.forEach { country ->
                DropdownMenuItem(
                    text = {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(country.flag)
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(
                                "${country.code}  ${country.name}",
                                style = MaterialTheme.typography.bodyMedium
                            )
                        }
                    },
                    onClick = {
                        onCodeSelected(country)
                        expanded = false
                    }
                )
            }
        }
    }
}
