import 'package:flutter_securechat/src/chat/conversation_preview.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regresyon: tek-gosterimlik bir mesajin icerigi hicbir onizleme yuzeyinde
/// gorunmemeli.
///
/// Cihaz turunda olculen hata: hic acilmamis bir tek-gosterim mesajinin duz
/// metni sohbet listesi satirinda okunabiliyordu
/// ('Q | qa-peer-02 | VO-UNOPENED-A'). Sohbet ekraninda dogru sekilde
/// 'Acmak icin dokunun' olarak gizliydi ve bildirim yolunda da koruma vardi;
/// yalniz sohbet listesi onizlemesine uygulanmamisti.
void main() {
  const secret = 'COK-GIZLI-TEK-GOSTERIM-ICERIGI';

  test('tek-gosterim onizlemesi icerigi sizdirmaz', () {
    final preview = conversationPreview(content: secret, isViewOnce: true);
    expect(preview, isNot(contains(secret)));
    expect(preview, viewOncePreviewLabel);
  });

  test('tek-gosterim bayragi her icerik tipinde onceliklidir', () {
    for (final type in StorageMessageContentType.values) {
      final preview = conversationPreview(
        content: secret,
        isViewOnce: true,
        contentType: type,
      );
      expect(
        preview,
        isNot(contains(secret)),
        reason: '$type tipinde tek-gosterim icerigi sizdi',
      );
    }
  });

  test('normal mesajlarda onizleme davranisi korunur', () {
    expect(
      conversationPreview(content: 'merhaba', isViewOnce: false),
      'merhaba',
    );
    expect(
      conversationPreview(
        content: 'soru',
        isViewOnce: false,
        contentType: StorageMessageContentType.poll,
      ),
      'Anket',
    );
    expect(
      conversationPreview(
        content: 'gizli-dosya-adi.pdf',
        isViewOnce: false,
        contentType: StorageMessageContentType.file,
      ),
      'Dosya',
      reason: 'dosya adi onizlemede gorunmemeli',
    );
    expect(
      conversationPreview(
        content: 'x',
        isViewOnce: false,
        contentType: StorageMessageContentType.image,
      ),
      'Fotoğraf',
    );
    expect(
      conversationPreview(
        content: 'x',
        isViewOnce: false,
        contentType: StorageMessageContentType.voiceNote,
      ),
      'Sesli mesaj',
    );
  });
}
