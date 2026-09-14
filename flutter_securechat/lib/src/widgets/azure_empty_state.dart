import 'package:flutter/material.dart';

/// Bos ekran durumu.
///
/// Arka plandaki desen icerik yogunlastikca geri cekilir, bosaldikca one
/// cikar. Bu yuzden bos durumlar OPAK bir yuzeye konmaz: desenin gercekten
/// konustugu yer burasidir. Tasarim agirligi tipografiden ve tek bir marka
/// isaretinden gelir, panelden degil.
///
/// Onceden her ekran kendi bosluk metnini farkli sekilde yaziyordu: sohbet
/// listesinde ikon + baslik + aciklama, rehberde tek satir duz yazi, arama
/// gecmisinde ortalanmis tek satir. Ayni durum ucununde ayni dili konusmali.
class AzureEmptyState extends StatelessWidget {
  const AzureEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.topPadding = 72,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Bu widget hem SINIRLI (Scaffold govdesi) hem SINIRSIZ (ListView icinde)
    // baglamda kullaniliyor. Sinirli baglamda buyuk metin olceginde icerik
    // ekrani asiyordu; o durumda kaydirilabilir olmali. Sinirsiz baglamda
    // kaydirma sarmalayicisi eklenemez (ic ice dikey kaydirma).
    return LayoutBuilder(
      builder: (context, constraints) {
        final content = _content(context, theme, scheme);
        if (!constraints.hasBoundedHeight) return content;
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: content),
          ),
        );
      },
    );
  }

  Widget _content(BuildContext context, ThemeData theme, ColorScheme scheme) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, topPadding, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primary.withValues(alpha: .10),
              border: Border.all(color: scheme.primary.withValues(alpha: .22)),
            ),
            child: Icon(icon, size: 36, color: scheme.primary),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            // Marka yazi tipi: bos ekran uygulamanin kendini tanittigi yer.
            style: theme.textTheme.headlineSmall?.copyWith(
              color: scheme.onSurface,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );
  }
}
