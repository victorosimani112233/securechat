import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/chat/view_once_receipts.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/features/chat/chat_screen.dart';
import 'package:flutter_securechat/src/incoming/incoming_message_handler.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations_tr.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/private_chat_control_support.dart';
import 'support/test_app_container.dart';

/// QA 2026-10-12 Bulgu 13: gonderen, alici acmadan "Acildi" goruyordu;
/// tek gosterimlik metin "medya" diye anlatiliyordu.
void main() {
  final l10n = AppLocalizationsTr();

  LocalMessage message({
    required String id,
    required bool outgoing,
    required bool viewed,
    bool text = false,
    String mime = 'image/jpeg',
  }) => LocalMessage(
    id: id,
    conversationId: 'peer-ayse',
    senderId: outgoing ? 'me' : 'peer-ayse',
    peerId: 'peer-ayse',
    content: text
        ? (viewed ? '' : 'gizli')
        : LocalMessage.buildFileContent(
            fileName: 'foto.jpg',
            mimeType: mime,
            fileSize: 10,
            filePath: '/managed/foto.jpg',
          ),
    contentType: text ? MessageContentType.text : MessageContentType.image,
    timestamp: DateTime.now(),
    status: MessageStatus.delivered,
    isOutgoing: outgoing,
    isViewOnce: true,
    isViewed: viewed,
  );

  Future<void> pump(WidgetTester tester, List<LocalMessage> messages) async {
    final defaults = createWidgetTestContainer(messagesFor: (_) => messages);
    final container = AppContainer.testing(
      session: defaults.session,
      conversations: defaults.conversations,
      crypto: defaults.crypto,
      signaling: defaults.signaling,
      chatAccessRuntime: defaults.chatAccessRuntime,
      callReadinessRuntime: defaults.callReadinessRuntime,
    );
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(
      AppContainerScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChatScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sent view-once photo is not "opened" until told so', (
    tester,
  ) async {
    await pump(tester, [message(id: 'p1', outgoing: true, viewed: false)]);
    expect(find.text(l10n.opened), findsNothing);
    expect(find.text(l10n.media_no_longer_available), findsNothing);
    expect(find.text(l10n.view_once_photo), findsOneWidget);
  });

  testWidgets('sent view-once photo shows opened after the receipt', (
    tester,
  ) async {
    await pump(tester, [message(id: 'p1', outgoing: true, viewed: true)]);
    expect(find.text(l10n.opened), findsOneWidget);
  });

  testWidgets('view-once text speaks of a message, not media', (tester) async {
    await pump(tester, [
      message(id: 't1', outgoing: true, viewed: false, text: true),
      message(id: 't2', outgoing: false, viewed: true, text: true),
    ]);
    expect(find.text(l10n.view_once_message), findsOneWidget);
    expect(find.text(l10n.message_no_longer_available), findsOneWidget);
    expect(find.text(l10n.media_no_longer_available), findsNothing);
    expect(find.text(l10n.opened), findsNothing);
  });

  // QA 2026-10-12 Bulgu 14: dosya "fotograf" diye etiketleniyordu.
  testWidgets('view-once label follows the file type', (tester) async {
    await pump(tester, [
      message(id: 'a', outgoing: false, viewed: false, mime: 'image/png'),
      message(id: 'b', outgoing: false, viewed: false, mime: 'video/mp4'),
      message(id: 'c', outgoing: false, viewed: false, mime: 'text/plain'),
    ]);
    expect(find.text(l10n.view_once_photo), findsOneWidget);
    expect(find.text(l10n.view_once_video), findsOneWidget);
    expect(find.text(l10n.view_once_file), findsOneWidget);
  });

  group('opened receipt', () {
    late Directory root;
    late SecureChatDatabase db;
    final crypto = LocalAeadCryptoService(SecretKey(List.filled(32, 21)));

    setUp(() async {
      root = await Directory.systemTemp.createTemp('view_once_receipt_');
      db = await SecureChatDatabase.open(
        file: File('${root.path}/db'),
        crypto: crypto,
      );
      await db.conversations.insert(
        const ConversationEntity(
          id: 'peer',
          peerId: 'peer',
          peerName: 'Peer',
          peerPhone: '',
        ),
      );
      await db.messages.insert(
        const MessageEntity(
          id: 'm1',
          conversationId: 'peer',
          senderId: 'me',
          content: 'foto',
          contentType: StorageMessageContentType.image,
          timestamp: 1,
          status: StorageMessageStatus.delivered,
          isOutgoing: true,
          isViewOnce: true,
        ),
      );
    });
    tearDown(() async {
      await db.close();
      await root.delete(recursive: true);
    });

    test('only the chat peer can mark a sent view-once as opened', () async {
      expect(
        await db.messages.markOutgoingViewOnceOpened('m1', by: 'x'),
        isFalse,
      );
      expect((await db.messages.getById('m1'))!.isViewed, isFalse);
      expect(
        await db.messages.markOutgoingViewOnceOpened('m1', by: 'peer'),
        isTrue,
      );
      expect((await db.messages.getById('m1'))!.isViewed, isTrue);
    });

    test(
      'an encrypted opened control from the peer reaches the bubble state',
      () async {
        final socket = InMemorySignalingService();
        await socket.connect(userId: 'me', url: 'wss://t', accessToken: 'a');
        final handler = IncomingMessageHandler(
          signaling: socket,
          crypto: crypto,
          database: db,
          session: SessionStore(userId: 'me', accessToken: 'a'),
        )..start();
        addTearDown(handler.close);
        socket.addIncoming(
          await encryptTestPrivateChatControl(
            crypto: crypto,
            control: ViewOnceOpenedSignal(
              senderId: 'peer',
              recipientId: 'me',
              timestamp: DateTime.now(),
              messageId: 'm1',
            ),
          ),
        );
        await handler.waitForIdle();
        expect((await db.messages.getById('m1'))!.isViewed, isTrue);
      },
    );

    test('opening sends a receipt only with read receipts on', () async {
      final socket = InMemorySignalingService();
      await socket.connect(userId: 'me', url: 'wss://t', accessToken: 'a');
      final session = SessionStore(userId: 'me', accessToken: 'a');
      final receipts = ViewOnceReceipts(
        session: session,
        crypto: crypto,
        signaling: socket,
      );
      final incoming = message(id: 'r1', outgoing: false, viewed: false);

      expect(await receipts.notifyOpened(incoming), isTrue);
      final control = await decryptTestPrivateChatControl(
        crypto: crypto,
        wire: socket.sentMessages.whereType<EncryptedSignalMessage>().single,
      );
      expect(control, isA<ViewOnceOpenedSignal>());
      expect((control as ViewOnceOpenedSignal).messageId, 'r1');
      expect(control.recipientId, 'peer-ayse');

      session.shareReadReceipts = false;
      expect(await receipts.notifyOpened(incoming), isFalse);
    });
  });
}
