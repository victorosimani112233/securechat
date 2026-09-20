import '../storage/storage_entities.dart';

/// Sohbet listesi ve bildirim onizlemesi icin gosterilecek ozet metin.
///
/// Tek-gosterimlik mesajlarin icerigi ASLA onizlemeye girmez: mesajin tamami
/// yalniz bir kez, korumali gorunumde acilmalidir. Onizlemede duz metin
/// gostermek bu garantiyi deler (omuz sorfu, sohbet listesi, kilit ekrani).
///
/// Bildirim yolunda bu koruma zaten vardi; ayni kural sohbet listesine
/// uygulanmadigi icin acilmamis bir tek-gosterim mesajinin duz metni listede
/// gorunuyordu.
String conversationPreview({
  required String content,
  required bool isViewOnce,
  StorageMessageContentType contentType = StorageMessageContentType.text,
}) {
  if (isViewOnce) return viewOncePreviewLabel;
  return switch (contentType) {
    StorageMessageContentType.poll => 'Anket: $content',
    StorageMessageContentType.image => 'Fotoğraf',
    StorageMessageContentType.file => 'Dosya',
    StorageMessageContentType.voiceNote => 'Sesli mesaj',
    _ => content,
  };
}

/// Tek-gosterimlik mesajlar icin icerik sizdirmayan sabit etiket.
const viewOncePreviewLabel = 'Tek gösterimlik mesaj';
