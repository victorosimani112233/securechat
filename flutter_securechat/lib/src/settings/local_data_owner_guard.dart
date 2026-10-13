import 'dart:io';

import '../storage/secure_chat_database.dart';

/// Cihazdaki yerel verinin hangi hesaba ait oldugunu tutar.
///
/// Cikis artik yerel veriyi siliyor, ama eski surumle cikis yapilmis
/// cihazlarda onceki hesabin sohbetleri duruyor. Yeni bir hesap giris
/// yaptiginda bu veri ona gosterilmemeli; sahibi farkliysa (ya da sahibi
/// bilinmiyorsa ve icerik varsa) giristen once silinir.
class LocalDataOwnerGuard {
  LocalDataOwnerGuard({
    required SecureChatDatabase database,
    required List<Directory> managedDirectories,
    Future<void> Function()? forgetDiagnostics,
  }) : _database = database,
       _managedDirectories = List.unmodifiable(managedDirectories),
       _forgetDiagnostics = forgetDiagnostics;

  /// `cryptoState` icinde tutulur: `clearAll` ile birlikte silinir, yedekten
  /// geri yuklemede yerel deger korunur.
  static const ownerKey = 'local_data_owner_v1';

  final SecureChatDatabase _database;
  final List<Directory> _managedDirectories;

  /// Onceki hesabin cokme kayitlarini siler (QA 2026-10-12 R2).
  final Future<void> Function()? _forgetDiagnostics;

  /// [userId] hesabi giris yapmadan once cagrilir.
  ///
  /// Sahip ayniysa hicbir sey silinmez. Sahip farkliysa ya da kayitli degil
  /// ama icerik varsa (eski surumden kalan veri) kullanici icerigi ve
  /// yonetilen dizinler silinir. Kripto durumu korunur. Sahip en son yazilir:
  /// silme yarida kalirsa sonraki giris yeniden siler.
  Future<void> claim(String userId) async {
    final owner = await _database.cryptoState.get(ownerKey);
    if (owner == userId) return;
    if (owner != null || await _database.hasAccountContent()) {
      await _database.clearAccountContent();
      for (final directory in _managedDirectories) {
        if (!await directory.exists()) continue;
        await directory.delete(recursive: true);
      }
      await _forgetDiagnostics?.call();
    }
    await markOwner(userId);
  }

  /// Verinin [userId] hesabina ait oldugunu kaydeder (ör. cevrimdisi yedek
  /// geri yuklemesi sonrasi).
  Future<void> markOwner(String userId) =>
      _database.cryptoState.put(ownerKey, userId);
}
