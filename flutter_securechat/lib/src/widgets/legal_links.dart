import 'package:flutter/material.dart';

import '../config/legal_links.dart';
import '../l10n/l10n.dart';
import '../platform/native_bridge.dart';

Future<void> openLegalPage(
  BuildContext context,
  Uri url, {
  NativeBridge bridge = const NativeBridge(),
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final failed = context.l10n.legal_open_failed;
  var opened = false;
  try {
    opened = await bridge.openExternalUrl(url);
  } catch (_) {
    opened = false;
  }
  if (!opened) messenger.showSnackBar(SnackBar(content: Text(failed)));
}

/// Kayit/giris ekraninda gosterilen onay metni ve iki politika linki.
/// Devam etmek, sartlarin kabulu sayilir.
class LegalConsentNotice extends StatelessWidget {
  const LegalConsentNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Column(
      key: const ValueKey('legal-consent-notice'),
      children: [
        Text(
          context.l10n.legal_consent_notice,
          style: style,
          textAlign: TextAlign.center,
        ),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            TextButton(
              key: const ValueKey('legal-terms-link'),
              onPressed: () => openLegalPage(context, LegalLinks.terms),
              child: Text(context.l10n.legal_terms),
            ),
            TextButton(
              key: const ValueKey('legal-privacy-link'),
              onPressed: () => openLegalPage(context, LegalLinks.privacy),
              child: Text(context.l10n.legal_privacy),
            ),
          ],
        ),
      ],
    );
  }
}
