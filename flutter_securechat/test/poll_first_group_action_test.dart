import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/chat/poll_service.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/crypto/crypto_protocol_store.dart';
import 'package:flutter_securechat/src/crypto/libsignal_protocol_store.dart';
import 'package:flutter_securechat/src/crypto/pre_key_manager.dart';
import 'package:flutter_securechat/src/crypto/signal_protocol_crypto_service.dart';
import 'package:flutter_securechat/src/domain/send_message_use_case.dart';
import 'package:flutter_securechat/src/incoming/incoming_message_handler.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart' as signal;

const _groupId = 'new-two-member-group';

void main() {
  for (final (sendTextFirst, rejectDistribution) in [
    (false, false),
    (true, false),
    (false, true),
  ]) {
    test(
      sendTextFirst
          ? 'group vote works after voter sends first group text'
          : rejectDistribution
          ? 'failed group key distribution leaves vote unchanged and retryable'
          : 'first outgoing group action can be a vote on a received poll',
      () async {
        final root = await Directory.systemTemp.createTemp('first_group_vote_');
        addTearDown(() => root.delete(recursive: true));
        final bundles = _Bundles();
        final alice = await _Peer.open(root, 'alice', bundles);
        addTearDown(alice.close);
        final bob = await _Peer.open(root, 'bob', bundles);
        addTearDown(bob.close);

        expect(
          await bob.polls.create(
            _groupId,
            PollData(
              question: 'Which option?',
              options: const ['One', 'Two'],
              singleChoice: true,
            ),
          ),
          SendMessageOutcome.sent,
        );
        await bob.deliverTo(alice);
        await alice.deliverTo(bob);
        final received = (await alice.database.messages.getAllMessages())
            .where(
              (message) =>
                  message.contentType == StorageMessageContentType.poll,
            )
            .single;
        expect(received.senderId, 'bob');
        expect(PollData.parse(received.content).totalVotes, 0);

        if (rejectDistribution) {
          alice.signaling.rejectSend = true;
          expect(await alice.polls.vote(received.id, 0), isFalse);
          expect(alice.signaling.sentMessages, isEmpty);
          for (final peer in [alice, bob]) {
            final unchanged = await peer.database.messages.getById(received.id);
            expect(PollData.parse(unchanged!.content).totalVotes, 0);
          }
          alice.signaling.rejectSend = false;
        }

        if (sendTextFirst) {
          expect(
            await alice.sender(
              const SendMessageRequest(
                conversationId: _groupId,
                content: 'first group text',
              ),
            ),
            SendMessageOutcome.sent,
          );
          await alice.deliverTo(bob);
          await bob.deliverTo(alice);
          expect(
            (await bob.database.messages.getAllMessages()).where(
              (message) => message.content == 'first group text',
            ),
            hasLength(1),
          );
        }

        expect(
          await alice.polls.vote(received.id, 0),
          isTrue,
          reason:
              'Voting must initialize and distribute the voter sender key '
              'without requiring an earlier group text.',
        );
        await alice.deliverTo(bob);
        await bob.deliverTo(alice);
        await _expectVotes(alice, received.id, 0);
        await _expectVotes(bob, received.id, 0);

        expect(await alice.polls.vote(received.id, 1), isTrue);
        await alice.deliverTo(bob);
        await bob.deliverTo(alice);
        await _expectVotes(alice, received.id, 1);
        await _expectVotes(bob, received.id, 1);
      },
    );
  }
}

Future<void> _expectVotes(_Peer peer, String id, int option) async {
  final message = await peer.database.messages.getById(id);
  expect(message, isNotNull);
  final poll = PollData.parse(message!.content);
  expect(poll.totalVotes, 1);
  expect(poll.votes, {
    option: ['alice'],
  });
  expect(peer.failures, isEmpty);
}

class _Peer {
  _Peer(this.database, this.crypto, String id) {
    final session = SessionStore(userId: id, accessToken: 'token');
    signaling.setConnected(true);
    sender = SendMessageUseCase(
      database: database,
      signaling: signaling,
      session: session,
      crypto: crypto,
      maxRetryCount: 0,
      retryDelay: Duration.zero,
    );
    polls = PollService(
      database: database,
      sender: sender,
      signaling: signaling,
      session: session,
      crypto: crypto,
    );
    incoming = IncomingMessageHandler(
      database: database,
      signaling: signaling,
      session: session,
      crypto: crypto,
      onAsyncFailure: (operation, error, stackTrace) async {
        failures.add(error);
      },
    )..start();
  }

  final SecureChatDatabase database;
  final SignalProtocolCryptoService crypto;
  final signaling = _Signaling();
  final failures = <Object>[];
  late final SendMessageUseCase sender;
  late final PollService polls;
  late final IncomingMessageHandler incoming;

  static Future<_Peer> open(Directory root, String id, _Bundles bundles) async {
    final database = await SecureChatDatabase.open(
      file: File('${root.path}/$id.securejson'),
      crypto: LocalAeadCryptoService(SecretKey(List.filled(32, 1))),
    );
    final raw = DatabaseCryptoProtocolStore(database);
    final bundle = await PreKeyManager(
      raw,
      batchSize: 4,
    ).generateAndSerializeInitialBundle();
    final oneTime = bundle.oneTimePreKeys.first;
    bundles.values[id] = signal.PreKeyBundle(
      bundle.registrationId,
      1,
      oneTime.keyId,
      signal.Curve.decodePoint(Uint8List.fromList(oneTime.publicKey), 0),
      bundle.signedPreKeyId,
      signal.Curve.decodePoint(Uint8List.fromList(bundle.signedPreKey), 0),
      Uint8List.fromList(bundle.signedPreKeySignature),
      signal.IdentityKey.fromBytes(
        Uint8List.fromList(bundle.identityPublicKey),
        0,
      ),
    );
    await database.conversations.insert(
      const ConversationEntity(
        id: _groupId,
        peerId: _groupId,
        peerName: 'New group',
        peerPhone: '',
        isGroup: true,
        groupMembers: 'alice,bob',
      ),
    );
    return _Peer(
      database,
      SignalProtocolCryptoService(
        store: PersistentSignalProtocolStore(raw),
        preKeyBundles: bundles,
      ),
      id,
    );
  }

  Future<void> deliverTo(_Peer peer) async {
    final outgoing = signaling.sentMessages.toList();
    signaling.sentMessages.clear();
    for (final message in outgoing) {
      peer.signaling.addIncoming(message);
    }
    await peer.incoming.waitForIdle();
    expect(peer.failures, isEmpty);
  }

  Future<void> close() async {
    await incoming.close();
    await signaling.dispose();
    await database.close();
  }
}

class _Signaling extends InMemorySignalingService {
  bool rejectSend = false;

  @override
  Future<bool> send(SignalMessage message) async =>
      rejectSend ? false : super.send(message);
}

class _Bundles implements PreKeyBundleProvider {
  final values = <String, signal.PreKeyBundle>{};

  @override
  Future<signal.PreKeyBundle?> fetch(String recipientId) async =>
      values[recipientId];
}
