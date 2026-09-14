import 'package:flutter/material.dart';

import '../services/app_container.dart';
import '../theme/secure_chat_theme.dart';

class AzureBackdrop extends StatelessWidget {
  const AzureBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final useDoodle =
        AppContainerScope.of(
          context,
        ).settingsRuntime?.service.current.useDoodleBackground ??
        true;
    final theme = Theme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        // Zemin sabittir: yalnizca desen katmani kayar. Zemin de kaysaydi
        // kenarlarda boyanmamis serit acilirdi.
        ColoredBox(color: AzureTokens.ground(dark)),
        if (useDoodle) _DriftingDoodles(dark: dark),
        Theme(
          data: theme.copyWith(scaffoldBackgroundColor: Colors.transparent),
          child: child,
        ),
      ],
    );
  }
}

/// Desen katmani: cok yavas, capraz ve sonsuz kayar.
///
/// Maliyet notu: desen her karede YENIDEN CIZILMEZ. `CustomPaint` statik
/// kalir ve `RepaintBoundary` ile rasterlenir; animasyon yalnizca hazir
/// katmani oteler. Desen [AzureDoodlePainter.tile] araliginda dosendigi ve
/// gorunur alanin bir tile disina tasacak sekilde cizildigi icin oteleme tam
/// bir tile'a ulastiginda desen kendisiyle ortusur — dikis gorunmez.
class _DriftingDoodles extends StatefulWidget {
  const _DriftingDoodles({required this.dark});

  final bool dark;

  @override
  State<_DriftingDoodles> createState() => _DriftingDoodlesState();
}

class _DriftingDoodlesState extends State<_DriftingDoodles>
    with SingleTickerProviderStateMixin {
  /// Bir tam tile bu surede kat edilir. 280 px / 45 sn yaklasik 6 px/sn:
  /// bakildiginda fark edilir, okurken dikkat dagitmaz.
  static const _period = Duration(seconds: 45);

  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: _period,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Erisilebilirlik: "animasyonlari azalt" acikken desen durur, kaybolmaz.
    // Ayni bayrak widget testlerinde de aciktir; sonsuz bir animasyon
    // `pumpAndSettle`'in oturmasini engellerdi.
    if (MediaQuery.of(context).disableAnimations) {
      _drift.stop();
    } else if (!_drift.isAnimating) {
      _drift.repeat();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    child: AnimatedBuilder(
      animation: _drift,
      builder: (context, child) => Transform.translate(
        offset: Offset(
          _drift.value * AzureDoodlePainter.tile,
          _drift.value * AzureDoodlePainter.tile,
        ),
        child: child,
      ),
      child: RepaintBoundary(
        child: CustomPaint(
          painter: AzureDoodlePainter(
            dark: widget.dark,
            enabled: true,
            drawBase: false,
          ),
        ),
      ),
    ),
  );
}

class AzureGlassPanel extends StatelessWidget {
  const AzureGlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.strong = false,
    this.radius = AzureTokens.cardRadius,
    this.elevation = 0,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool strong;
  final double radius;

  /// Yukseklik. Varsayilan 0'dir; liste kartlari gibi zeminden ayrilmasi
  /// gereken yuzeyler kucuk bir deger verir. Her sey ayni duzlemdeyken kart,
  /// zemin ve baslik birbirinden yalnizca 1 px cerceveyle ayriliyordu.
  final double elevation;

  /// Durumu belli etmek icin cerceve rengini degistiren cagiranlar icin.
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark
        ? Colors.white.withValues(alpha: strong ? .14 : .07)
        : Colors.white.withValues(alpha: strong ? .85 : .62);
    final border = dark
        ? Colors.white.withValues(alpha: strong ? .20 : .12)
        : AzureTokens.ink.withValues(alpha: strong ? .10 : .04);
    return Material(
      color: background,
      elevation: elevation,
      shadowColor: dark
          ? Colors.black.withValues(alpha: .6)
          : AzureTokens.ink.withValues(alpha: .18),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: borderColor ?? border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }
}

class AzureBrandTitle extends StatelessWidget {
  const AzureBrandTitle({super.key, this.fontSize = 22});

  final double fontSize;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Semantics(
      label: 'elçim',
      header: true,
      child: Text.rich(
        TextSpan(
          style: TextStyle(
            fontFamily: 'SpaceGrotesk',
            fontWeight: FontWeight.w600,
            fontSize: fontSize,
            letterSpacing: -.5,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          children: [
            const TextSpan(text: 'elçim'),
            TextSpan(
              text: '.',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class AzureDoodlePainter extends CustomPainter {
  const AzureDoodlePainter({
    required this.dark,
    required this.enabled,
    this.drawBase = true,
  });

  final bool dark;
  final bool enabled;

  /// Kayan katman zemini boyamaz; zemin altta sabit durur.
  final bool drawBase;

  /// Desen dosemesinin kenar uzunlugu. Oteleme bu degere ulastiginda desen
  /// kendisiyle ortustugu icin sonsuz kaydirma dikissiz olur.
  static const tile = 280.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (drawBase) {
      final base = dark ? AzureTokens.night : AzureTokens.paper;
      canvas.drawRect(Offset.zero & size, Paint()..color = base);
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = AzureTokens.azure.withValues(alpha: dark ? .035 : .04),
      );
    }
    if (!enabled) return;

    final stroke = dark
        ? Colors.white.withValues(alpha: .055)
        // Acik temada koyu murekkep, koyu temada beyaza gore daha baskin
        // okunuyordu: ayni deger iki temada ayni sakinligi vermiyor. Cihazda
        // olculup dengelendi.
        : AzureTokens.ink.withValues(alpha: .042);
    final strong = dark
        ? AzureTokens.azureGlow.withValues(alpha: .07)
        : AzureTokens.azureDeep.withValues(alpha: .062);
    // Gorunur alanin bir tile disindan baslanir: katman otelenince acikta
    // kalan kenar bosluk gostermez.
    for (var y = -tile; y < size.height + tile; y += tile) {
      for (var x = -tile; x < size.width + tile; x += tile) {
        canvas.save();
        canvas.translate(x, y);
        _drawTile(canvas, stroke, strong);
        canvas.restore();
      }
    }
  }

  void _drawTile(Canvas canvas, Color stroke, Color strong) {
    final normal = _line(stroke, 1.4);
    final strongLine = _line(strong, 1.6);
    final thin = _line(stroke, 1.2);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(22, 30, 34, 22),
        const Radius.circular(2),
      ),
      normal,
    );
    canvas.drawPath(
      Path()
        ..moveTo(22, 32)
        ..lineTo(39, 44)
        ..lineTo(56, 32),
      normal,
    );

    for (final point in const [
      Offset(110, 36),
      Offset(150, 54),
      Offset(128, 72),
    ]) {
      canvas.drawCircle(point, 3.5, normal);
    }
    final mesh = Path()
      ..moveTo(110, 36)
      ..lineTo(150, 54)
      ..moveTo(150, 54)
      ..lineTo(128, 72)
      ..moveTo(128, 72)
      ..lineTo(110, 36);
    _drawDashedPath(canvas, mesh, normal, 2, 3);

    canvas.drawPath(
      Path()
        ..moveTo(180, 48)
        ..quadraticBezierTo(190, 38, 200, 48)
        ..quadraticBezierTo(210, 58, 220, 48)
        ..quadraticBezierTo(230, 38, 240, 48),
      strongLine,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(38, 108, 16, 13),
        const Radius.circular(2),
      ),
      normal,
    );
    canvas.drawPath(
      Path()
        ..moveTo(41, 108)
        ..lineTo(41, 104)
        ..quadraticBezierTo(41, 97, 46, 97)
        ..quadraticBezierTo(51, 97, 51, 104)
        ..lineTo(51, 108),
      normal,
    );

    canvas.drawPath(
      Path()
        ..moveTo(86, 122)
        ..lineTo(126, 122)
        ..quadraticBezierTo(130, 122, 130, 126)
        ..lineTo(130, 140)
        ..quadraticBezierTo(130, 144, 126, 144)
        ..lineTo(98, 144)
        ..lineTo(88, 152)
        ..lineTo(88, 144)
        ..lineTo(86, 144)
        ..quadraticBezierTo(82, 144, 82, 140)
        ..lineTo(82, 126)
        ..quadraticBezierTo(82, 122, 86, 122)
        ..close(),
      _line(strong, 1.5),
    );

    canvas.drawLine(const Offset(170, 112), const Offset(180, 122), thin);
    canvas.drawLine(const Offset(180, 112), const Offset(170, 122), thin);
    _drawDashedPath(
      canvas,
      Path()
        ..addOval(Rect.fromCircle(center: const Offset(175, 117), radius: 10)),
      thin,
      2,
      3,
    );

    canvas.drawCircle(const Offset(228, 120), 10, normal);
    canvas.drawCircle(const Offset(228, 120), 4, normal);
    canvas.drawPath(
      Path()
        ..moveTo(232, 120)
        ..lineTo(232, 123)
        ..quadraticBezierTo(234, 127, 239, 121),
      normal,
    );

    _drawDashedPath(
      canvas,
      Path()
        ..moveTo(30, 180)
        ..cubicTo(70, 160, 120, 200, 170, 180)
        ..quadraticBezierTo(220, 160, 260, 180),
      normal,
      1,
      4,
    );

    canvas.drawCircle(const Offset(60, 220), 3, _line(stroke, 1.3));
    _drawDashedPath(
      canvas,
      Path()
        ..addOval(Rect.fromCircle(center: const Offset(60, 220), radius: 10)),
      _line(stroke, 1.3),
      2,
      3,
    );
    _drawDashedPath(
      canvas,
      Path()
        ..addOval(Rect.fromCircle(center: const Offset(60, 220), radius: 18)),
      _line(stroke, 1.3),
      1,
      4,
    );

    canvas.drawCircle(const Offset(130, 225), 5, normal);
    canvas.drawLine(const Offset(135, 225), const Offset(153, 225), normal);
    canvas.drawLine(const Offset(148, 225), const Offset(148, 230), normal);
    canvas.drawLine(const Offset(153, 225), const Offset(153, 232), normal);

    canvas.drawPath(
      Path()
        ..moveTo(180, 228)
        ..lineTo(186, 222)
        ..lineTo(192, 228)
        ..lineTo(198, 222)
        ..lineTo(204, 228)
        ..lineTo(210, 222)
        ..lineTo(216, 228),
      normal,
    );

    _plus(canvas, const Offset(254, 46.5), strong, diagonal: true);
    _plus(canvas, const Offset(12, 93.5), strong);
    _plus(canvas, const Offset(254, 265.5), strong);
    _plus(canvas, const Offset(76, 261.5), strong);

    canvas.drawPath(
      Path()
        ..moveTo(216, 222)
        ..quadraticBezierTo(224, 214, 232, 222),
      normal,
    );
    canvas.drawPath(
      Path()
        ..moveTo(220, 226)
        ..quadraticBezierTo(224, 222, 228, 226),
      normal,
    );
    canvas.drawCircle(const Offset(224, 229), 1.2, Paint()..color = stroke);
  }

  Paint _line(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  void _plus(
    Canvas canvas,
    Offset center,
    Color color, {
    bool diagonal = false,
  }) {
    final paint = _line(color, 1.2);
    canvas.drawLine(center.translate(0, -2.5), center.translate(0, 2.5), paint);
    canvas.drawLine(center.translate(-2.5, 0), center.translate(2.5, 0), paint);
    if (!diagonal) return;
    canvas.drawLine(
      center.translate(-2.5, -2.5),
      center.translate(2.5, 2.5),
      paint,
    );
    canvas.drawLine(
      center.translate(2.5, -2.5),
      center.translate(-2.5, 2.5),
      paint,
    );
  }

  void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint,
    double dash,
    double gap,
  ) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant AzureDoodlePainter oldDelegate) =>
      dark != oldDelegate.dark ||
      enabled != oldDelegate.enabled ||
      drawBase != oldDelegate.drawBase;
}
