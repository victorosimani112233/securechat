package com.securechat.app.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.securechat.app.R

val InterFamily = FontFamily(
    Font(R.font.inter_regular, FontWeight.Normal),
    Font(R.font.inter_medium, FontWeight.Medium),
    Font(R.font.inter_semibold, FontWeight.SemiBold),
    Font(R.font.inter_bold, FontWeight.Bold),
)

val DisplayFamily = FontFamily(
    Font(R.font.space_grotesk_semibold, FontWeight.SemiBold),
    Font(R.font.space_grotesk_bold, FontWeight.Bold),
)

val MonoFamily = FontFamily(
    Font(R.font.jetbrains_mono_regular, FontWeight.Normal),
    Font(R.font.jetbrains_mono_medium, FontWeight.Medium),
)

val AzureTypography = Typography(
    displayLarge = TextStyle(
        fontFamily = DisplayFamily,
        fontWeight = FontWeight.Bold,
        fontSize = 40.sp,
        letterSpacing = (-1.0).sp,
        lineHeight = 44.sp,
    ),
    headlineMedium = TextStyle(
        fontFamily = DisplayFamily,
        fontWeight = FontWeight.SemiBold,
        fontSize = 24.sp,
        letterSpacing = (-0.6).sp,
        lineHeight = 28.sp,
    ),
    titleLarge = TextStyle(
        fontFamily = InterFamily,
        fontWeight = FontWeight.SemiBold,
        fontSize = 17.sp,
        letterSpacing = (-0.2).sp,
    ),
    titleMedium = TextStyle(
        fontFamily = InterFamily,
        fontWeight = FontWeight.SemiBold,
        fontSize = 15.sp,
    ),
    bodyLarge = TextStyle(
        fontFamily = InterFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 15.sp,
        lineHeight = 22.sp,
    ),
    bodyMedium = TextStyle(
        fontFamily = InterFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 14.sp,
        lineHeight = 20.sp,
    ),
    bodySmall = TextStyle(
        fontFamily = InterFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 12.sp,
    ),
    labelMedium = TextStyle(
        fontFamily = MonoFamily,
        fontWeight = FontWeight.Medium,
        fontSize = 11.sp,
        letterSpacing = 0.5.sp,
    ),
)
