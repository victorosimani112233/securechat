import 'package:flutter/widgets.dart';

import '../core/models.dart';
import '../core/peer_display_name.dart';
import 'generated/app_localizations.dart';

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  /// Birebir karsi tarafin gosterilecek adi; ic kimlik asla gosterilmez
  /// (bkz [peerDisplayName]).
  String peerLabel(String name, {String? peerId, String phone = ''}) =>
      peerDisplayName(
        name,
        peerId: peerId,
        phone: phone,
        unknown: l10n.unknown_contact,
      );

  /// Sohbet basligi: grup adi ya da [peerLabel].
  String conversationTitle(Conversation conversation) => conversation.isGroup
      ? conversation.peerName
      : peerLabel(
          conversation.peerName,
          peerId: conversation.peerId,
          phone: conversation.peerPhone,
        );
}
