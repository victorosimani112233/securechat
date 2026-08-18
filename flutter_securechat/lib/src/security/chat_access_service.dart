import '../core/models.dart';
import '../platform/native_bridge.dart';

abstract interface class DeviceOwnerAuthenticator {
  Future<bool> authenticate(String title);
}

class NativeDeviceOwnerAuthenticator implements DeviceOwnerAuthenticator {
  const NativeDeviceOwnerAuthenticator({
    NativeBridge bridge = const NativeBridge(),
  }) : _bridge = bridge;

  final NativeBridge _bridge;

  @override
  Future<bool> authenticate(String title) =>
      _bridge.authenticateLockedChat(title);
}

class ChatAccessService {
  const ChatAccessService({required DeviceOwnerAuthenticator authenticator})
    : _authenticator = authenticator;

  final DeviceOwnerAuthenticator _authenticator;

  Future<bool> authorize(Conversation conversation) async {
    if (!conversation.isLocked) return true;
    try {
      return await _authenticator.authenticate(
        conversation.peerName.trim().isEmpty
            ? 'Kilitli Sohbet'
            : conversation.peerName,
      );
    } catch (_) {
      // Locked chats fail closed on plugin/platform errors.
      return false;
    }
  }
}

class AlwaysAllowDeviceOwnerAuthenticator implements DeviceOwnerAuthenticator {
  const AlwaysAllowDeviceOwnerAuthenticator();

  @override
  Future<bool> authenticate(String title) async => true;
}
