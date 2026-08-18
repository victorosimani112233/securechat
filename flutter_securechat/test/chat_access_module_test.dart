import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/security/chat_access_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const unlocked = Conversation(
    id: 'open',
    peerId: 'open',
    peerName: 'Open Chat',
    peerPhone: '',
  );
  const locked = Conversation(
    id: 'locked',
    peerId: 'locked',
    peerName: 'Secret Chat',
    peerPhone: '',
    isLocked: true,
  );

  test('unlocked conversation never invokes device authentication', () async {
    final authenticator = _FakeAuthenticator(result: false);
    final service = ChatAccessService(authenticator: authenticator);

    expect(await service.authorize(unlocked), isTrue);
    expect(authenticator.titles, isEmpty);
  });

  test('locked conversation opens only after successful owner check', () async {
    final authenticator = _FakeAuthenticator(result: true);
    final service = ChatAccessService(authenticator: authenticator);

    expect(await service.authorize(locked), isTrue);
    expect(authenticator.titles, ['Secret Chat']);
  });

  test('platform failure keeps locked conversation closed', () async {
    final authenticator = _FakeAuthenticator(error: StateError('unavailable'));
    final service = ChatAccessService(authenticator: authenticator);

    expect(await service.authorize(locked), isFalse);
  });
}

class _FakeAuthenticator implements DeviceOwnerAuthenticator {
  _FakeAuthenticator({this.result = false, this.error});

  final bool result;
  final Object? error;
  final titles = <String>[];

  @override
  Future<bool> authenticate(String title) async {
    titles.add(title);
    if (error != null) throw error!;
    return result;
  }
}
