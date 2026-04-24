package com.securechat.app.ui.theme

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.unit.dp

@Composable
fun AzureDoodleBackdrop(
    modifier: Modifier = Modifier,
    dark: Boolean = isSystemInDarkTheme(),
) {
    val tokens = LocalAzureTokens.current
    val useDoodle = LocalUseDoodleBackground.current
    val base = if (dark) tokens.night else tokens.paper
    val wash = Color(0xFF3E7BFA).copy(alpha = if (dark) 0.035f else 0.04f)

    if (!useDoodle) {
        // Düz renk arka plan
        Box(modifier.fillMaxSize()) {
            Canvas(Modifier.fillMaxSize()) {
                drawRect(base)
                drawRect(wash)
            }
        }
        return
    }

    val stroke = if (dark) Color.White.copy(alpha = 0.055f)
                 else Color(0xFF13161B).copy(alpha = 0.07f)
    val strokeStrong = if (dark) Color(0xFF5EA3FF).copy(alpha = 0.07f)
                       else Color(0xFF1E52D9).copy(alpha = 0.10f)

    Box(modifier.fillMaxSize()) {
        Canvas(Modifier.fillMaxSize()) {
            drawRect(base)
            drawRect(wash)
            val tileSize = 280.dp.toPx()
            var ty = 0f
            while (ty < size.height) {
                var tx = 0f
                while (tx < size.width) {
                    translate(left = tx, top = ty) {
                        drawDoodleTile(tileSize, stroke, strokeStrong)
                    }
                    tx += tileSize
                }
                ty += tileSize
            }
        }
    }
}

private fun DrawScope.drawDoodleTile(
    tileSize: Float,
    stroke: Color,
    strokeStrong: Color,
) {
    val u = tileSize / 280f
    val sw = 1.4f * u
    val swStrong = 1.6f * u
    val swThin = 1.2f * u
    val swLighter = 1.3f * u

    val strokeStyle = Stroke(sw, cap = StrokeCap.Round, join = StrokeJoin.Round)
    val dashEffect = PathEffect.dashPathEffect(floatArrayOf(2f * u, 3f * u), 0f)
    val longDashEffect = PathEffect.dashPathEffect(floatArrayOf(1f * u, 4f * u), 0f)

    // ── 1. Zarf (envelope) ──
    drawRoundRect(
        color = stroke,
        topLeft = Offset(22f * u, 30f * u),
        size = Size(34f * u, 22f * u),
        cornerRadius = CornerRadius(2f * u),
        style = strokeStyle,
    )
    drawPath(Path().apply {
        moveTo(22f * u, 32f * u)
        lineTo(39f * u, 44f * u)
        lineTo(56f * u, 32f * u)
    }, color = stroke, style = strokeStyle)

    // ── 2. Peer düğümleri (3 nokta + kesikli çizgi) ──
    drawCircle(stroke, 3.5f * u, Offset(110f * u, 36f * u), style = Stroke(sw))
    drawCircle(stroke, 3.5f * u, Offset(150f * u, 54f * u), style = Stroke(sw))
    drawCircle(stroke, 3.5f * u, Offset(128f * u, 72f * u), style = Stroke(sw))
    drawPath(Path().apply {
        moveTo(110f * u, 36f * u); lineTo(150f * u, 54f * u)
        moveTo(150f * u, 54f * u); lineTo(128f * u, 72f * u)
        moveTo(128f * u, 72f * u); lineTo(110f * u, 36f * u)
    }, color = stroke, style = Stroke(sw, pathEffect = dashEffect))

    // ── 3. Dalga ──
    drawPath(Path().apply {
        moveTo(180f * u, 48f * u)
        quadraticBezierTo(190f * u, 38f * u, 200f * u, 48f * u)
        quadraticBezierTo(210f * u, 58f * u, 220f * u, 48f * u)
        quadraticBezierTo(230f * u, 38f * u, 240f * u, 48f * u)
    }, color = strokeStrong, style = Stroke(swStrong, cap = StrokeCap.Round))

    // ── 4. Kilit ──
    drawRoundRect(
        color = stroke,
        topLeft = Offset(38f * u, 108f * u),
        size = Size(16f * u, 13f * u),
        cornerRadius = CornerRadius(2f * u),
        style = strokeStyle,
    )
    drawPath(Path().apply {
        moveTo(41f * u, 108f * u)
        lineTo(41f * u, 104f * u)
        quadraticBezierTo(41f * u, 97f * u, 46f * u, 97f * u)
        quadraticBezierTo(51f * u, 97f * u, 51f * u, 104f * u)
        lineTo(51f * u, 108f * u)
    }, color = stroke, style = strokeStyle)

    // ── 5. Konuşma balonu ──
    drawPath(Path().apply {
        moveTo(86f * u, 122f * u)
        lineTo(126f * u, 122f * u)
        quadraticBezierTo(130f * u, 122f * u, 130f * u, 126f * u)
        lineTo(130f * u, 140f * u)
        quadraticBezierTo(130f * u, 144f * u, 126f * u, 144f * u)
        lineTo(98f * u, 144f * u)
        lineTo(88f * u, 152f * u)
        lineTo(88f * u, 144f * u)
        lineTo(86f * u, 144f * u)
        quadraticBezierTo(82f * u, 144f * u, 82f * u, 140f * u)
        lineTo(82f * u, 126f * u)
        quadraticBezierTo(82f * u, 122f * u, 86f * u, 122f * u)
        close()
    }, color = strokeStrong, style = Stroke(1.5f * u, cap = StrokeCap.Round, join = StrokeJoin.Round))

    // ── 6. X mesh (çarpı + kesikli daire) ──
    drawLine(stroke, Offset(170f * u, 112f * u), Offset(180f * u, 122f * u), swThin)
    drawLine(stroke, Offset(180f * u, 112f * u), Offset(170f * u, 122f * u), swThin)
    drawCircle(stroke, 10f * u, Offset(175f * u, 117f * u), style = Stroke(swThin, pathEffect = dashEffect))

    // ── 7. @ işareti ──
    drawCircle(stroke, 10f * u, Offset(228f * u, 120f * u), style = strokeStyle)
    drawCircle(stroke, 4f * u, Offset(228f * u, 120f * u), style = strokeStyle)
    drawPath(Path().apply {
        moveTo(232f * u, 120f * u)
        lineTo(232f * u, 123f * u)
        quadraticBezierTo(234f * u, 127f * u, 239f * u, 121f * u)
    }, color = stroke, style = strokeStyle)

    // ── 8. Kesikli yol (dashed path) ──
    drawPath(Path().apply {
        moveTo(30f * u, 180f * u)
        cubicTo(70f * u, 160f * u, 120f * u, 200f * u, 170f * u, 180f * u)
        quadraticBezierTo(220f * u, 160f * u, 260f * u, 180f * u)
    }, color = strokeStrong, style = Stroke(
        sw, cap = StrokeCap.Round,
        pathEffect = PathEffect.dashPathEffect(floatArrayOf(1f * u, 4f * u), 0f),
    ))

    // ── 9. Sinyal düğümü (3 iç içe daire) ──
    drawCircle(stroke, 3f * u, Offset(60f * u, 220f * u), style = Stroke(swLighter))
    drawCircle(stroke, 10f * u, Offset(60f * u, 220f * u), style = Stroke(swLighter, pathEffect = dashEffect))
    drawCircle(stroke, 18f * u, Offset(60f * u, 220f * u), style = Stroke(swLighter, pathEffect = longDashEffect))

    // ── 10. Anahtar ──
    drawCircle(stroke, 5f * u, Offset(130f * u, 225f * u), style = strokeStyle)
    drawLine(stroke, Offset(135f * u, 225f * u), Offset(153f * u, 225f * u), sw, StrokeCap.Round)
    drawLine(stroke, Offset(148f * u, 225f * u), Offset(148f * u, 230f * u), sw, StrokeCap.Round)
    drawLine(stroke, Offset(153f * u, 225f * u), Offset(153f * u, 232f * u), sw, StrokeCap.Round)

    // ── 11. Zigzag ──
    drawPath(Path().apply {
        moveTo(180f * u, 228f * u)
        lineTo(186f * u, 222f * u); lineTo(192f * u, 228f * u)
        lineTo(198f * u, 222f * u); lineTo(204f * u, 228f * u)
        lineTo(210f * u, 222f * u); lineTo(216f * u, 228f * u)
    }, color = stroke, style = strokeStyle)

    // ── 12. Yıldızlar / artılar ──
    // Büyük yıldız (254, 44)
    drawLine(strokeStrong, Offset(254f * u, 44f * u), Offset(254f * u, 49f * u), swThin, StrokeCap.Round)
    drawLine(strokeStrong, Offset(251.5f * u, 46.5f * u), Offset(256.5f * u, 46.5f * u), swThin, StrokeCap.Round)
    drawLine(strokeStrong, Offset(252f * u, 43f * u), Offset(257f * u, 48f * u), swThin, StrokeCap.Round)
    drawLine(strokeStrong, Offset(257f * u, 43f * u), Offset(252f * u, 48f * u), swThin, StrokeCap.Round)
    // Artı (12, 92)
    drawLine(strokeStrong, Offset(12f * u, 92f * u), Offset(12f * u, 95f * u), swThin, StrokeCap.Round)
    drawLine(strokeStrong, Offset(10.5f * u, 93.5f * u), Offset(13.5f * u, 93.5f * u), swThin, StrokeCap.Round)
    // Artı (254, 264)
    drawLine(strokeStrong, Offset(254f * u, 264f * u), Offset(254f * u, 267f * u), swThin, StrokeCap.Round)
    drawLine(strokeStrong, Offset(252.5f * u, 265.5f * u), Offset(255.5f * u, 265.5f * u), swThin, StrokeCap.Round)
    // Artı (76, 260)
    drawLine(strokeStrong, Offset(76f * u, 260f * u), Offset(76f * u, 263f * u), swThin, StrokeCap.Round)
    drawLine(strokeStrong, Offset(74.5f * u, 261.5f * u), Offset(77.5f * u, 261.5f * u), swThin, StrokeCap.Round)

    // ── 13. Sinyal arkları ──
    drawPath(Path().apply {
        moveTo(216f * u, 222f * u)
        quadraticBezierTo(224f * u, 214f * u, 232f * u, 222f * u)
    }, color = stroke, style = strokeStyle)
    drawPath(Path().apply {
        moveTo(220f * u, 226f * u)
        quadraticBezierTo(224f * u, 222f * u, 228f * u, 226f * u)
    }, color = stroke, style = strokeStyle)
    drawCircle(stroke, 1.2f * u, Offset(224f * u, 229f * u))
}
