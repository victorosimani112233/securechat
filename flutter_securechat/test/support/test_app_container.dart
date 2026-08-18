import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/calls/call_readiness_service.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/security/chat_access_service.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/services/conversation_repository.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';

AppContainer createWidgetTestContainer({
  AppNotificationRuntime? notificationRuntime,
}) {
  final conversations = _testConversations();
  return AppContainer.testing(
    session: createLoggedInTestSession(),
    conversations: InMemoryConversationRepository(
      conversations: conversations,
      messages: {
        for (final conversation in conversations)
          conversation.id: _testMessages(conversation.id),
      },
    ),
    crypto: LocalAeadCryptoService(
      SecretKey(List<int>.generate(32, (index) => index + 1)),
    ),
    signaling: InMemorySignalingService(),
    notificationRuntime: notificationRuntime,
    chatAccessRuntime: const AppChatAccessRuntime(
      service: ChatAccessService(
        authenticator: AlwaysAllowDeviceOwnerAuthenticator(),
      ),
    ),
    callReadinessRuntime: const AppCallReadinessRuntime(
      service: CallReadinessService(
        platform: NotApplicableCallReadinessPlatform(),
      ),
    ),
  );
}

SessionStore createLoggedInTestSession() => SessionStore(
  userId: 'me',
  displayName: 'Elcim Kullanici',
  phoneNumber: '+90 500 000 00 00',
  accessToken: 'test-access-token',
  refreshToken: 'test-refresh-token',
  languagePreference: 'tr',
);

InMemoryConversationRepository createTestConversationRepository() {
  final conversations = _testConversations();
  return InMemoryConversationRepository(
    conversations: conversations,
    messages: {
      for (final conversation in conversations)
        conversation.id: _testMessages(conversation.id),
    },
  );
}

List<Conversation> _testConversations() {
  final now = DateTime.now();
  return [
    Conversation(
      id: 'peer-ayse',
      peerId: 'peer-ayse',
      peerName: 'Ayse Demir',
      peerPhone: '+90 532 000 00 01',
      lastMessage: 'Toplantidan sonra yazisalim.',
      lastMessageTimestamp: now.subtract(const Duration(minutes: 4)),
      unreadCount: 2,
      isFavorite: true,
    ),
    Conversation(
      id: 'group-ops',
      peerId: 'group-ops',
      peerName: 'Operasyon Ekibi',
      peerPhone: '',
      lastMessage: 'Anket: vardiya plani',
      lastMessageTimestamp: now.subtract(const Duration(hours: 1)),
      isGroup: true,
      groupMembers: const ['me', 'peer-ayse', 'peer-bora'],
      groupAdmins: const ['me'],
      isPinned: true,
    ),
    Conversation(
      id: 'peer-bora',
      peerId: 'peer-bora',
      peerName: 'Bora Yilmaz',
      peerPhone: '+90 555 000 00 02',
      lastMessage: 'Tek gosterimlik mesaj',
      lastMessageTimestamp: now.subtract(const Duration(days: 1)),
      isMuted: true,
      isLocked: true,
    ),
  ];
}

List<LocalMessage> _testMessages(String conversationId) {
  final now = DateTime.now();
  return [
    LocalMessage(
      id: 'm1',
      conversationId: conversationId,
      senderId: conversationId,
      peerId: conversationId,
      content: 'Merhaba, Flutter tasima ekranini inceliyorum.',
      contentType: MessageContentType.text,
      timestamp: now.subtract(const Duration(minutes: 12)),
      status: MessageStatus.read,
      isOutgoing: false,
    ),
    LocalMessage(
      id: 'm2',
      conversationId: conversationId,
      senderId: 'me',
      peerId: conversationId,
      content: 'Mevcut davranisi koruyarak ilerliyorum.',
      contentType: MessageContentType.text,
      timestamp: now.subtract(const Duration(minutes: 10)),
      status: MessageStatus.read,
      isOutgoing: true,
    ),
    LocalMessage(
      id: 'm3',
      conversationId: conversationId,
      senderId: 'me',
      peerId: conversationId,
      content: 'Signal/WebRTC/native bridge noktalarini ayirdim.',
      contentType: MessageContentType.text,
      timestamp: now.subtract(const Duration(minutes: 2)),
      status: MessageStatus.delivered,
      isOutgoing: true,
      isPinned: true,
    ),
  ];
}
