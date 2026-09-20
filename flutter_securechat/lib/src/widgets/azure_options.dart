import 'package:flutter/material.dart';

/// Secim listelerinin ortak satiri.
///
/// Uygulamadaki her secici (tema, dil, bildirim sesi, kaybolan mesaj suresi)
/// ayri ayri `ListTile` + `radio_button_checked` ikonuyla yazilmisti. Sonuc
/// hem sade hem tutarsizdi: secili durum yalnizca kucuk bir daireden
/// okunuyordu ve satirlar acilir yuzeyin geri kalanindan ayrismiyordu.
///
/// Burada secili durum UC ISARETLE birden anlatiliyor — zemin rengi, cerceve
/// ve ikon. Tek bir isaret (kucuk radyo dairesi) hizli bakista kaciyor,
/// ozellikle uzun listelerde.
class AzureOptionTile extends StatelessWidget {
  const AzureOptionTile({
    super.key,
    required this.selected,
    required this.title,
    required this.onTap,
    this.icon,
    this.subtitle,
    this.trailing,
  });

  final bool selected;
  final String title;
  final VoidCallback onTap;
  final IconData? icon;
  final String? subtitle;

  /// Satirin sagindaki ek eylem (orn. sesi dinleme dugmesi).
  ///
  /// Secim isaretinin YERINI ALMAZ, yanina gelir: kullanici bir secenegi
  /// secmeden de deneyebilmeli.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: .10)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected
                ? scheme.primary.withValues(alpha: .55)
                : scheme.outlineVariant.withValues(alpha: .40),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 8, 10),
            child: Row(
              children: [
                if (icon != null) ...[
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: selected
                          ? scheme.primary.withValues(alpha: .16)
                          : scheme.surfaceContainerHighest.withValues(
                              alpha: .55,
                            ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      icon,
                      size: 19,
                      color: selected
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: text.bodyLarge?.copyWith(
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: selected ? scheme.primary : scheme.onSurface,
                        ),
                      ),
                      if (subtitle case final String value)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            value,
                            style: text.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (trailing case final Widget widget) widget,
                const SizedBox(width: 4),
                Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  size: 20,
                  color: selected ? scheme.primary : scheme.outlineVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Acilir yuzeylerin basligi.
///
/// Sayfalarin cogunda baslik yoktu; acilan panelin neyi degistirdigi yalniz
/// satirlardan anlasiliyordu.
class AzureSheetHeading extends StatelessWidget {
  const AzureSheetHeading(this.text, {super.key, this.subtitle, this.onClose});

  final String text;
  final String? subtitle;

  /// Kapatma dugmesi.
  ///
  /// Uzun listeli bir sayfa ekrani neredeyse tamamen kapliyor: disarida
  /// dokunulacak yer kalmiyor ve asagi kaydirma hareketi sayfayi kapatmak
  /// yerine LISTEYE gidiyor. Kullanici sikisip kaliyordu. Acik bir cikis
  /// dugmesi bu duruma bagli olmayan tek cozum.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        24,
        4,
        onClose == null ? 24 : 8,
        14,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(text, style: theme.textTheme.titleMedium),
                if (subtitle case final String value)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      value,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (onClose case final VoidCallback close)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: close,
            ),
        ],
      ),
    );
  }
}
