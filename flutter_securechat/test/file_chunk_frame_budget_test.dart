import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/media/file_transfer_manager.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regresyon: dolu bir dosya parcasi asla `SignalMessage.maxEncodedBytes`
/// (256 KiB) sinirini asmamali.
///
/// Cihaz turunda olculen hata: 128 KiB'lik ham parca telde 311.171 byte
/// oluyordu (+49.027 byte asim). Sebep, sifreli zarfin ucuncu kez
/// base64'lenmesiydi (1,333^3 = 2,37x sisme). Etkisi uc katmanda birden
/// gorunuyordu:
///   * `SignalMessage.decode` cerceveyi `FormatException` ile reddediyordu,
///   * alis yolu bu hatayi sessizce dusuruyordu,
///   * production sunucu `maxFrameSize = 256 KiB` ile cerceveyi hic kabul
///     etmiyordu.
/// Sonuc: ~85 KB ustundeki hicbir dosya teslim edilemiyordu.
void main() {
  late Directory root;
  late InMemorySignalingService signaling;
  late LocalAeadCryptoService crypto;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('chunk_budget_');
    signaling = InMemorySignalingService();
    await signaling.connect(
      userId: 'me',
      url: 'wss://test.invalid',
      accessToken: 'token',
    );
    crypto = LocalAeadCryptoService(
      SecretKey(List<int>.generate(32, (index) => index + 1)),
    );
  });

  tearDown(() async {
    await signaling.dispose();
    await root.delete(recursive: true);
  });

  test('uretim parca boyutunda dolu parca 256 KiB cerceve butcesine sigar',
      () async {
    final manager = FileTransferManager(
      signaling: signaling,
      crypto: crypto,
      filesDirectory: root,
      // Uretim varsayilani; test burayi kucultmemeli yoksa butce anlamsizlasir.
    );
    addTearDown(manager.dispose);

    // Iki dolu parca uretmek icin tam olarak 2 x chunkSize gonder.
    final payload = Uint8List.fromList(
      List<int>.generate(manager.chunkSize * 2, (index) => index % 256),
    );
    final result = await manager.sendStream(
      localUserId: 'me',
      recipientId: 'peer',
      stream: Stream.value(payload),
      fileSize: payload.length,
      fileName: 'buyuk.bin',
      mimeType: 'application/octet-stream',
      caption: 'baslik',
    );
    expect(result, isA<FileTransferSuccess>());

    final chunks = signaling.sentMessages
        .whereType<FileTransferSignal>()
        .toList();
    expect(chunks, hasLength(2), reason: 'iki dolu parca beklenir');

    for (final chunk in chunks) {
      final frameBytes = utf8.encode(chunk.encode()).length;
      expect(
        frameBytes,
        lessThan(SignalMessage.maxEncodedBytes),
        reason:
            'parca ${chunk.chunkIndex}/${chunk.totalChunks} cerceve butcesini '
            'asiyor: $frameBytes byte > ${SignalMessage.maxEncodedBytes}',
      );
      // Cerceve, alici tarafta gercekten decode edilebilmeli.
      expect(
        () => SignalMessage.decode(chunk.encode()),
        returnsNormally,
      );
    }
  });

  test('v4 zarfi ham tasir, gereksiz base64 katmani yok', () async {
    final manager = FileTransferManager(
      signaling: signaling,
      crypto: crypto,
      filesDirectory: root,
      chunkSize: 1024,
    );
    addTearDown(manager.dispose);

    final payload = Uint8List.fromList(List<int>.filled(512, 7));
    await manager.sendStream(
      localUserId: 'me',
      recipientId: 'peer',
      stream: Stream.value(payload),
      fileSize: payload.length,
      fileName: 'kucuk.bin',
      mimeType: 'application/octet-stream',
    );
    final chunk = signaling.sentMessages
        .whereType<FileTransferSignal>()
        .single;

    expect(chunk.encryption, FileTransferManager.directWireVersion);
    // Zarf artik oldugu gibi tasiniyor: ASCII ve taninabilir onekli.
    expect(chunk.data, startsWith('E2EE:'));
    // Manifest (caption alani) de ayni sekilde ham zarf.
    expect(chunk.caption, isNotNull);
    expect(chunk.caption!, startsWith('E2EE:'));
  });

  test('eski v2 gonderenin cerceveleri hala cozulup birlestiriliyor', () async {
    final manager = FileTransferManager(
      signaling: signaling,
      crypto: crypto,
      filesDirectory: root,
      chunkSize: 32,
    );
    addTearDown(manager.dispose);

    final payload = Uint8List.fromList(
      List<int>.generate(77, (index) => (index * 13) % 256),
    );
    final result = await manager.sendStream(
      localUserId: 'me',
      recipientId: 'peer',
      stream: Stream.value(payload),
      fileSize: payload.length,
      fileName: 'eski.bin',
      mimeType: 'application/pdf',
      caption: 'eski baslik',
    );
    expect(result, isA<FileTransferSuccess>());

    // v4 cikisini eski v2 teline geri cevir: zarflari tekrar base64'le ve
    // surum etiketini dusur. Alici bu bicimi hala desteklemeli.
    final downgraded = signaling.sentMessages
        .whereType<FileTransferSignal>()
        .map((chunk) {
          final json = chunk.toJson();
          return FileTransferSignal.fromJson({
            ...json,
            'senderId': 'peer',
            'recipientId': 'me',
            'data': base64Encode(utf8.encode(chunk.data)),
            'caption': chunk.caption == null
                ? null
                : base64Encode(utf8.encode(chunk.caption!)),
            'encryption': 'flutter-file-v2-direct',
          });
        })
        .toList();

    ReceivedFile? received;
    for (final chunk in downgraded.reversed) {
      received = await manager.receiveChunk(chunk) ?? received;
    }
    expect(received, isNotNull, reason: 'v2 cerceveleri birlestirilemedi');
    expect(await received!.file.readAsBytes(), payload);
    expect(received.fileName, 'eski.bin');
    expect(received.mimeType, 'application/pdf');
    expect(received.caption, 'eski baslik');
  });

  test('sisme orani tek base64 katmanina dustu', () async {
    final manager = FileTransferManager(
      signaling: signaling,
      crypto: crypto,
      filesDirectory: root,
      chunkSize: 64 * 1024,
    );
    addTearDown(manager.dispose);

    final payload = Uint8List.fromList(
      List<int>.generate(manager.chunkSize, (index) => index % 256),
    );
    await manager.sendStream(
      localUserId: 'me',
      recipientId: 'peer',
      stream: Stream.value(payload),
      fileSize: payload.length,
      fileName: 'olcum.bin',
      mimeType: 'application/octet-stream',
    );
    final chunk = signaling.sentMessages
        .whereType<FileTransferSignal>()
        .first;
    final expansion = chunk.data.length / manager.chunkSize;
    // Onceden 2,37x idi (uc katman). Iki katman kaldigi icin ~1,78x beklenir.
    expect(
      expansion,
      lessThan(2.0),
      reason: 'olculen sisme ${expansion.toStringAsFixed(3)}x',
    );
  });
}
