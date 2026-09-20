import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../l10n/service_strings.dart';
import '../storage/secure_chat_database.dart';
import '../storage/storage_entities.dart';

/// Guvenlik olaylarini sohbetin icinde gorunur kilar.
///
/// Karsi tarafin Signal kimlik anahtari degistiginde oturum fail-closed kalir
/// ve bu olay sohbette gorunur olur. Mesru bir yeniden kurulum ile prekey
/// bundle'ini degistirebilen bir sunucunun araya girmesi ayni gorunume sahip
/// oldugundan yeni kimlik kullanici onayi veya key-transparency kaniti olmadan
/// otomatik kabul edilmez.
class SecurityNoticeService {
  SecurityNoticeService({
    required SecureChatDatabase database,
    ServiceStrings? strings,
  }) : _database = database,
       _strings = strings ?? ServiceStrings.fixed('tr');

  final SecureChatDatabase _database;
  final ServiceStrings _strings;

  /// Sohbete, kimlik degisikligini bildiren bir sistem mesaji yazar.
  ///
  /// Ayni peer icin ayni gun tekrar tekrar yazilmamasi adina kayit kimligi
  /// peer ve gunden turetilir; boylece tekrar eden rotasyonlar sohbeti
  /// doldurmaz.
  Future<void> peerIdentityRotated(String peerId, {DateTime? at}) async {
    final text = (await _strings.load()).security_number_changed;
    await _write(
      conversationId: peerId,
      text: text,
      scope: 'identity-rotated',
      at: at ?? DateTime.now(),
    );
  }

  /// Cozulemeyen bir mesaj geldiginde sohbete gorunur bir iz birakir.
  ///
  /// Onceki davranis: cozulemeyen zarf sessizce dusuyordu. Kullanici mesajin
  /// var oldugunu hic ogrenemiyordu; gonderen "gonderdim" diyor, alan "bana
  /// gelmedi" diyordu. Ozellikle grup yolunda bu kalici: sender key kurulamazsa
  /// o gondericinin mesajlari cozulemez ve 1:1 oturum kurtarmasi grup anahtarini
  /// geri getirmez.
  ///
  /// Gun basina tek kayit yazilir: amac kullanicinin kaybi FARK ETMESI, her
  /// dusen cerceve icin sohbeti doldurmak degil.
  Future<void> messageUnreadable(String conversationId, {DateTime? at}) async {
    final text = (await _strings.load()).security_message_unreadable;
    await _write(
      conversationId: conversationId,
      text: text,
      scope: 'message-unreadable',
      at: at ?? DateTime.now(),
    );
  }

  /// Ayni olayin ayni gun tekrar tekrar yazilmamasi adina kayit kimligi
  /// olay turu, sohbet ve gunden turetilir.
  Future<void> _write({
    required String conversationId,
    required String text,
    required String scope,
    required DateTime at,
  }) async {
    final conversation = await _database.conversations.getById(conversationId);
    if (conversation == null) return;
    final day = '${at.year}-${at.month}-${at.day}';
    final id = base64UrlEncode(
      (await Sha256().hash(
        utf8.encode('$scope:$conversationId:$day'),
      )).bytes,
    );
    if (await _database.messages.getById(id) != null) return;
    await _database.messages.insert(
      MessageEntity(
        id: id,
        conversationId: conversationId,
        senderId: 'SYSTEM',
        content: text,
        contentType: StorageMessageContentType.system,
        timestamp: at.millisecondsSinceEpoch,
        status: StorageMessageStatus.delivered,
        isOutgoing: false,
      ),
    );
    await _database.conversations.updateLastMessageById(
      conversationId,
      text,
      at.millisecondsSinceEpoch,
      type: StorageMessageContentType.system,
      outgoing: false,
    );
    await _database.conversations.incrementUnreadCount(conversationId);
  }
}
