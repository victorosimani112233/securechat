import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../services/app_container.dart';
import '../../widgets/azure_backdrop.dart';
import '../../widgets/azure_surface.dart';

/// Hakkinda: surum, guvenlik ozeti ve lisanslar.
///
/// Lisans sayfasi buraya tasindi. Ayarlarda ayri bir satir olarak
/// durmuyor artik, ama KALDIRILMADI: `libsignal_protocol_dart` GPL-3.0
/// lisansli ve lisans metninin kullaniciya ulasabilir olmasi bir yukumluluk.
/// Uygulamalarin alisildik yeri de burasi.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Surum bilgisi yerel koprunun topladigi teshis verisinden geliyor.
    // Ayri bir paket eklemek yerine var olan kaynak kullanildi: yeni bir
    // bagimlilik, dogrulama listesine yeni bir girdi demek.
    final metadata = AppContainerScope.of(context).diagnosticsRuntime?.reporter
        .metadata;
    final version = metadata == null
        ? '—'
        : '${metadata.versionName} (${metadata.versionCode})';

    return AzureBackdrop(
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.settings_about)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            AzureSurface(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: Column(
                children: [
                  Text(
                    'Elçim',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${l10n.about_version} $version',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            AzureSurface(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.about_security_title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.about_security_body,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            AzureSurface(
              child: ListTile(
                leading: const Icon(Icons.article_outlined),
                title: Text(l10n.settings_open_source_licenses),
                subtitle: Text(l10n.settings_open_source_licenses_desc),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Elçim',
                  applicationVersion: version,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
