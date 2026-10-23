import '../crypto/plaintext_padding.dart';
import '../storage/secure_chat_database.dart';

/// HTTP uzerinden sifreli ek alabilme yetenegi: isaretci teslim onayli
/// sifreli mesaj olarak gelir (`BLOBPTR:v1:`).
const blobAttachmentCapability = 'blob-v2';

/// Isaretciyi dosya parcasi cercevesiyle (5 dakikalik kova) alan ilk surum.
/// Bu surum o cerceveleri hala alir; gonderimde artik kullanilmaz.
const legacyBlobAttachmentCapability = 'blob-v1';

/// Birebir aramanin SDP ve ICE sinyallerini uctan uca sifreli tasima.
const callSignalEncryptionCapability = 'call-e2ee-v1';

/// Bu surumun karsi tarafa bildirdigi yetenekler (teslim makbuzunda).
const localPeerCapabilities = <String>[
  legacyBlobAttachmentCapability,
  blobAttachmentCapability,
  callSignalEncryptionCapability,
  plaintextPaddingCapability,
];

/// Karsi taraflarin bildirdigi yetenekler.
///
/// Yetenek uctan uca sifreli teslim makbuzuyla gelir; sunucu kimin hangi
/// surumu kullandigini ogrenmez. Makbuzunda yetenek bildirmeyen (eski)
/// surumden gelen makbuz yetenegi siler: kisi eski surume donduyse ona
/// yeniden eski yoldan gonderilir.
class PeerCapabilities {
  PeerCapabilities(this._state);

  static const _prefix = 'peer-capability:';
  final CryptoStateDao _state;

  static String _key(String capability, String userId) =>
      '$_prefix$capability:$userId';

  Future<void> record(String userId, Iterable<String> capabilities) async {
    if (userId.isEmpty) return;
    final announced = capabilities.toSet();
    for (final capability in localPeerCapabilities) {
      final key = _key(capability, userId);
      final known = await _state.get(key) != null;
      if (announced.contains(capability) && !known) {
        await _state.put(key, '1');
      } else if (!announced.contains(capability) && known) {
        await _state.delete(key);
      }
    }
  }

  /// Karsi tarafin dogrulanmis bir mesajindan anlasilan tek bir yetenegi
  /// kaydeder (makbuzu beklemeden).
  Future<void> recordOne(String userId, String capability) async {
    if (userId.isEmpty) return;
    final key = _key(capability, userId);
    if (await _state.get(key) == null) await _state.put(key, '1');
  }

  Future<bool> allSupport(Iterable<String> userIds, String capability) async {
    final ids = userIds.where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return false;
    for (final id in ids) {
      if (await _state.get(_key(capability, id)) == null) return false;
    }
    return true;
  }
}

/// Uzunluk gizleyen dolgunun hangi alicilara uygulanacagi.
///
/// Kisiye, o kisi [plaintextPaddingCapability] bildirdiyse; gruba, kendisi
/// disindaki TUM uyeler bildirdiyse. Eski surum dolguyu metnin parcasi
/// sanacagi icin tek bir eski uye grubun dolgusuz kalmasi demektir.
({Future<bool> Function(String) direct, Future<bool> Function(String) group})
paddingPolicies(SecureChatDatabase database, String? Function() localUserId) {
  final capabilities = PeerCapabilities(database.cryptoState);
  return (
    direct: (peerId) =>
        capabilities.allSupport([peerId], plaintextPaddingCapability),
    group: (groupId) async {
      final group = await database.conversations.getById(groupId);
      final self = localUserId();
      final members = (group?.groupMembers ?? '')
          .split(',')
          .where((id) => id.isNotEmpty && id != self)
          .toSet();
      return members.isNotEmpty &&
          await capabilities.allSupport(members, plaintextPaddingCapability);
    },
  );
}
