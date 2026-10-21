import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/invite_link.dart';
import '../l10n/l10n.dart';
import '../platform/native_bridge.dart';

enum _InviteChannel { sms, share }

/// Davet mesajini kullanicinin kendi SMS uygulamasinda ya da sectigi
/// baska bir uygulamada acar. Mesaji kullanici gonderir; numara veya
/// mesaj ELÇİM sunucusuna gitmez.
Future<void> sendInvite(
  BuildContext context, {
  String? phone,
  String? name,
}) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final text = l10n.invite_message(InviteLink.url);
  const bridge = NativeBridge();
  var channel = _InviteChannel.share;
  if (phone != null) {
    final picked = await showModalBottomSheet<_InviteChannel>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                context.l10n.invite_chooser_title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text(
                name == null || name.isEmpty ? phone : '$name · $phone',
              ),
            ),
            ListTile(
              key: const Key('invite-via-sms'),
              leading: const Icon(Icons.sms_outlined),
              title: Text(context.l10n.invite_via_sms),
              onTap: () => Navigator.pop(context, _InviteChannel.sms),
            ),
            ListTile(
              key: const Key('invite-via-share'),
              leading: const Icon(Icons.share_outlined),
              title: Text(context.l10n.invite_via_share),
              onTap: () => Navigator.pop(context, _InviteChannel.share),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null) return;
    channel = picked;
  }
  var opened = false;
  if (channel == _InviteChannel.sms && phone != null) {
    opened = await bridge.composeInviteSms(phone: phone, body: text);
  }
  if (!opened) {
    opened = await bridge.shareInviteText(
      text: text,
      title: l10n.invite_chooser_title,
    );
  }
  if (!opened) {
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(SnackBar(content: Text(l10n.invite_copied)));
  }
}
