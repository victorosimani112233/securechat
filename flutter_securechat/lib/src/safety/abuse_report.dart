import 'block_list.dart';

/// Bildirim sebepleri. `wire` degeri sunucudaki izinli listeyle birebir
/// aynidir; yeni bir sebep iki tarafta birlikte eklenmelidir.
enum ReportReason {
  spam('spam'),
  harassment('harassment'),
  inappropriate('inappropriate'),
  childSafety('child_safety'),
  impersonation('impersonation'),
  other('other');

  const ReportReason(this.wire);
  final String wire;
}

/// Kotuye kullanim bildirimi.
///
/// Uctan uca sifreleme nedeniyle sunucu icerigi goremez ve bildirim de
/// icerik tasimaz: yalniz hedef hesap kimlikleri, sebep ve kullanicinin
/// yazdigi kisa not gider. Sunucu grup tutmadigi icin bir grup, sorumlu
/// hesaplari (yoneticiler; yoksa uyeler) uzerinden bildirilir.
class AbuseReportService {
  AbuseReportService({
    required Future<void> Function(Map<String, Object?> report) submit,
    required BlockList blockList,
    required String? Function() localUserId,
  }) : _submit = submit,
       _blockList = blockList,
       _localUserId = localUserId;

  final Future<void> Function(Map<String, Object?> report) _submit;
  final BlockList _blockList;
  final String? Function() _localUserId;

  static const maxNoteLength = 500;
  static const maxGroupTargets = 32;

  BlockList get blockList => _blockList;

  Future<void> reportUser(
    String userId, {
    required ReportReason reason,
    String note = '',
    bool alsoBlock = false,
  }) async {
    await _submit(_body('user', [userId], reason, note));
    if (alsoBlock) await _blockList.block(userId);
  }

  Future<void> reportGroup({
    required List<String> admins,
    required List<String> members,
    required ReportReason reason,
    String note = '',
  }) async {
    final targets = groupReportTargets(
      admins: admins,
      members: members,
      localUserId: _localUserId(),
    );
    if (targets.isEmpty) {
      throw StateError('Bildirilecek grup üyesi bulunamadı.');
    }
    await _submit(_body('group', targets, reason, note));
  }

  Map<String, Object?> _body(
    String kind,
    List<String> targets,
    ReportReason reason,
    String note,
  ) {
    final trimmed = note.trim();
    return {
      'kind': kind,
      'targetUserIds': targets,
      'reason': reason.wire,
      if (trimmed.isNotEmpty)
        'note': trimmed.length > maxNoteLength
            ? trimmed.substring(0, maxNoteLength)
            : trimmed,
    };
  }
}

/// Grup bildiriminde gonderilecek hesaplar: once yoneticiler, yonetici
/// bilgisi yoksa uyeler. Bildiren kisi listeye girmez.
List<String> groupReportTargets({
  required List<String> admins,
  required List<String> members,
  required String? localUserId,
}) {
  List<String> others(List<String> ids) => [
    for (final id in ids)
      if (id.trim().isNotEmpty && id.trim() != localUserId) id.trim(),
  ];
  final responsible = others(admins);
  final targets = responsible.isNotEmpty ? responsible : others(members);
  return targets.toSet().take(AbuseReportService.maxGroupTargets).toList();
}
