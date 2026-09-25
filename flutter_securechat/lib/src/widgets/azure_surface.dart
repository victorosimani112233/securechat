import 'package:flutter/material.dart';

import '../theme/secure_chat_theme.dart';

/// Icerik tasiyan OPAK yuzey.
///
/// Arka plandaki desen surekli kayiyor. Yazi dogrudan desenin uzerine
/// oturursa okunabilirlik bozulur — mesaj balonlarinda tam olarak bu
/// yasandi. Ayarlar, rehber ve arama gecmisi ekranlarinda `ListTile`'lar
/// desenin uzerinde ciplak duruyordu; bu yuzey onlari da kapatir.
///
/// Renk, mesaj balonlariyla AYNI tarifle uretilir (yuzey rengi zemine
/// harmanlanir) ki uygulama genelinde tek bir malzeme dili olsun.
class AzureSurface extends StatelessWidget {
  const AzureSurface({
    super.key,
    required this.child,
    this.radius = 16,
    this.elevation = 1,
    this.borderColor,
    this.backgroundColor,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double radius;
  final double elevation;
  final Color? borderColor;
  final Color? backgroundColor;
  final EdgeInsetsGeometry padding;

  /// Balon ve kartlarin paylastigi opak yuzey rengi.
  static Color colorOf(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Color.alphaBlend(
      theme.colorScheme.surface.withValues(alpha: .72),
      AzureTokens.ground(dark),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: backgroundColor ?? colorOf(context),
      elevation: elevation,
      shadowColor: dark
          ? Colors.black.withValues(alpha: .6)
          : AzureTokens.ink.withValues(alpha: .18),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(
          color: borderColor ?? scheme.outlineVariant.withValues(alpha: .48),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Duz bir ayar listesini `Divider` sinirlarindan opak bolumlere ayirir.
///
/// Ayarlar ekrani duz bir `ListView` idi: satirlar arasindaki tek ayrim ince
/// bir cizgiydi ve hepsi kayan desenin uzerinde duruyordu. Gruplama hem
/// okunabilirligi hem de "hangi ayar nereye ait" sorusunu cozuyor.
List<Widget> azureSections(List<Widget> items, {String? Function(int)? title}) {
  final groups = <List<Widget>>[<Widget>[]];
  for (final item in items) {
    if (item is Divider) {
      groups.add(<Widget>[]);
      continue;
    }
    groups.last.add(item);
  }
  final filled = groups.where((group) => group.isNotEmpty).toList();
  return [
    for (var index = 0; index < filled.length; index++) ...[
      if (title?.call(index) case final String heading)
        _SectionHeading(heading),
      AzureSurface(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Each action owns its row bounds, not the whole visual section.
            for (final row in filled[index])
              Semantics(container: true, child: row),
          ],
        ),
      ),
      if (index < filled.length - 1) const SizedBox(height: 14),
    ],
  ];
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(6, 6, 6, 8),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 1.2,
      ),
    ),
  );
}
