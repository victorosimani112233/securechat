import 'package:flutter_securechat/src/crypto/vodozemac/group_replay_window.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

/// Megolm replay penceresi. Native kutuphane gerektirmez.
void main() {
  test('sirali trafikte kume bos kalir, filigran ilerler', () {
    var window = const GroupReplayWindow(watermark: -1);
    for (var index = 0; index < 5; index++) {
      expect(window.isReplay(index), isFalse);
      window = window.accept(index);
    }
    expect(window.watermark, 4);
    expect(window.seen, isEmpty);
  });

  test('sira disi indeks kabul edilir, bosluk dolunca emilir', () {
    var window = const GroupReplayWindow(watermark: -1).accept(2);
    expect(window.watermark, -1);
    expect(window.seen, [2]);
    expect(window.isReplay(0), isFalse);
    expect(window.isReplay(1), isFalse);
    expect(window.isReplay(2), isTrue);

    window = window.accept(0);
    expect(window.watermark, 0);
    window = window.accept(1);
    expect(window.watermark, 2);
    expect(window.seen, isEmpty);
  });

  test('ayni indeks iki kez kabul edilmez', () {
    final window = const GroupReplayWindow(watermark: -1).accept(3);
    expect(window.isReplay(3), isTrue);
    expect(() => window.accept(3), throwsStateError);
  });

  test('kume sinirlidir; en eski bosluk feda edilir', () {
    var window = const GroupReplayWindow(watermark: -1);
    // 0 hic gelmiyor; 1..max+1 geliyor.
    for (var index = 1; index <= GroupReplayWindow.maxOutOfOrder + 1; index++) {
      window = window.accept(index);
    }
    expect(window.seen.length, lessThanOrEqualTo(GroupReplayWindow.maxOutOfOrder));
    // Feda edilen bosluk artik reddedilir; bellek sinirli kaldi.
    expect(window.isReplay(0), isTrue);
  });

  test('eski kayit (yalniz en yuksek indeks) eski davranisi korur', () {
    // Onceki surum yalniz `highestMessageIndex` yaziyordu ve altindaki her
    // indeksi reddediyordu. Filigran olarak okunmasi birebir ayni sonuc.
    final entity = VodozemacInboundGroupSessionEntity.fromJson({
      'groupId': 'g',
      'senderId': 's',
      'sessionId': 'x',
      'pickle': 'p',
      'highestMessageIndex': 7,
    });
    expect(entity.seenMessageIndexes, isEmpty);
    final window = GroupReplayWindow(
      watermark: entity.highestMessageIndex,
      seen: entity.seenMessageIndexes,
    );
    expect(window.isReplay(7), isTrue);
    expect(window.isReplay(3), isTrue);
    expect(window.isReplay(8), isFalse);
  });

  test('pencere kalici kayitta gidip gelir', () {
    final entity = const VodozemacInboundGroupSessionEntity(
      groupId: 'g',
      senderId: 's',
      sessionId: 'x',
      pickle: 'p',
      highestMessageIndex: 4,
      seenMessageIndexes: [6, 9],
    );
    final restored = VodozemacInboundGroupSessionEntity.fromJson(
      entity.toJson(),
    );
    expect(restored.highestMessageIndex, 4);
    expect(restored.seenMessageIndexes, [6, 9]);
  });
}
