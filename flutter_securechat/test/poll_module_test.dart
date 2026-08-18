import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_securechat/src/chat/poll_service.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/domain/send_message_use_case.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('poll model validates schema and toggles single/multiple votes', () {
    final single = PollData(
      question: 'Seçim?',
      options: const ['A', 'B'],
      singleChoice: true,
    );
    final first = single.toggleVote('me', 0);
    expect(first.votes, {
      0: ['me'],
    });
    expect(first.toggleVote('me', 1).votes, {
      1: ['me'],
    });
    expect(first.toggleVote('me', 0).votes, isEmpty);

    final multiple = PollData(
      question: 'Birden fazla?',
      options: const ['A', 'B'],
      singleChoice: false,
    ).toggleVote('me', 0).toggleVote('me', 1);
    expect(multiple.totalVotes, 2);
    expect(PollData.parse(multiple.encode()).votes[1], ['me']);
    expect(
      () =>
          PollData(question: '', options: const ['A', 'B'], singleChoice: true),
      throwsFormatException,
    );
  });

  test('poll creation and vote use encrypted message pipeline', () async {
    final root = await Directory.systemTemp.createTemp('poll_service_');
    addTearDown(() => root.delete(recursive: true));
    final crypto = LocalAeadCryptoService(
      SecretKey(List<int>.generate(32, (index) => index + 1)),
    );
    final database = await SecureChatDatabase.open(
      file: File('${root.path}/storage.securejson'),
      crypto: crypto,
    );
    addTearDown(database.close);
    await database.conversations.insert(
      const ConversationEntity(
        id: 'peer',
        peerId: 'peer',
        peerName: 'Peer',
        peerPhone: '',
      ),
    );
    final signaling = InMemorySignalingService();
    await signaling.connect(
      userId: 'me',
      url: 'wss://test.invalid',
      accessToken: 'token',
    );
    final session = SessionStore(userId: 'me', accessToken: 'token');
    final sender = SendMessageUseCase(
      database: database,
      signaling: signaling,
      session: session,
      crypto: crypto,
      retryDelay: Duration.zero,
    );
    final service = PollService(
      database: database,
      sender: sender,
      signaling: signaling,
      session: session,
      crypto: crypto,
    );

    final outcome = await service.create(
      'peer',
      PollData(
        question: 'Devam?',
        options: const ['Evet', 'Hayır'],
        singleChoice: true,
      ),
    );
    expect(outcome, SendMessageOutcome.sent);
    final pollMessage = (await database.messages.getAllMessages()).single;
    expect(pollMessage.contentType, StorageMessageContentType.poll);
    expect(await service.vote(pollMessage.id, 1), isTrue);

    final updated = await database.messages.getById(pollMessage.id);
    expect(PollData.parse(updated!.content).votes[1], ['me']);
    final voteSignal = signaling.sentMessages
        .whereType<EncryptedSignalMessage>()
        .last;
    expect(voteSignal.envelope, isNot(contains('POLLVOTE')));
    final plaintext = await crypto.decryptDirect(
      senderId: 'peer',
      envelope: voteSignal.envelope,
    );
    expect(plaintext, contains('POLLVOTE:${pollMessage.id}:1'));
  });
}
