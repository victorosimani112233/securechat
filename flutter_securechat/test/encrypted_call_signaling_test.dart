import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/media/encrypted_call_signaling.dart';
import 'package:flutter_securechat/src/media/peer_capabilities.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/storage/secure_chat_database.dart';
import 'package:flutter_test/flutter_test.dart';

const _offerSdp =
    'v=0\r\na=fingerprint:sha-256 AA:BB:CC\r\na=ice-ufrag:abcd\r\n';

void main() {
  late Directory root;
  late LocalAeadCryptoService crypto;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('call_signal_e2ee_');
    crypto = LocalAeadCryptoService(
      SecretKey(List<int>.generate(32, (i) => i + 11)),
    );
  });
  tearDown(() => root.delete(recursive: true));

  Future<(EncryptedCallSignaling, InMemorySignalingService, PeerCapabilities)>
  side(String user) async {
    final database = await SecureChatDatabase.open(
      file: File('${root.path}/$user.db'),
      crypto: crypto,
    );
    addTearDown(database.close);
    final inner = InMemorySignalingService();
    await inner.connect(userId: user, url: 'wss://t', accessToken: 't');
    addTearDown(inner.dispose);
    final failures = <String>[];
    final wrapper = EncryptedCallSignaling(
      inner: inner,
      crypto: crypto,
      cryptoState: database.cryptoState,
      onFailure: (operation, _, _) async => failures.add(operation),
    );
    addTearDown(wrapper.dispose);
    return (wrapper, inner, PeerCapabilities(database.cryptoState));
  }

  SdpOfferSignal offer() => SdpOfferSignal(
    senderId: 'alice',
    recipientId: 'bob',
    timestamp: DateTime(2026),
    sdp: _offerSdp,
    callType: 'VIDEO',
  );

  Future<List<SignalMessage>> deliver(
    EncryptedCallSignaling receiver,
    InMemorySignalingService receiverInner,
    List<SignalMessage> signals,
  ) async {
    final received = <SignalMessage>[];
    final subscription = receiver.incoming.listen(received.add);
    addTearDown(subscription.cancel);
    for (final signal in signals) {
      receiverInner.addIncoming(signal);
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return received;
  }

  test('offer, answer and ICE travel encrypted to a capable peer', () async {
    final (alice, aliceInner, aliceCaps) = await side('alice');
    final (bob, bobInner, bobCaps) = await side('bob');
    await aliceCaps.recordOne('bob', callSignalEncryptionCapability);

    expect(await alice.send(offer()), isTrue);
    expect(
      await alice.send(
        IceCandidateSignal(
          senderId: 'alice',
          recipientId: 'bob',
          timestamp: DateTime(2026),
          candidate: 'candidate:1 1 udp 2122260223 10.0.0.2 51000 typ host',
          sdpMid: '0',
          sdpMLineIndex: 0,
        ),
      ),
      isTrue,
    );
    final wire = aliceInner.sentMessages;
    expect(wire, hasLength(2));
    final sealedOffer = wire.first as SdpOfferSignal;
    expect(sealedOffer.sdp, isEmpty);
    expect(sealedOffer.callType, 'VIDEO');
    expect(sealedOffer.e2ee, isNotEmpty);
    // Sunucunun gordugu cercevede parmak izi ve adres yok.
    for (final signal in wire) {
      final json = signal.encode();
      expect(json, isNot(contains('fingerprint')));
      expect(json, isNot(contains('10.0.0.2')));
    }

    final received = await deliver(bob, bobInner, wire);
    expect(received, hasLength(2));
    final opened = received.first as SdpOfferSignal;
    expect(opened.sdp, _offerSdp);
    expect(opened.callType, 'VIDEO');
    expect(opened.senderId, 'alice');
    final ice = received.last as IceCandidateSignal;
    expect(ice.candidate, contains('10.0.0.2'));
    expect(ice.sdpMid, '0');
    // Sifreli sinyal yetenegi kanitlar; yanit da sifreli gider.
    expect(
      await bobCaps.allSupport({'alice'}, callSignalEncryptionCapability),
      isTrue,
    );
    await bob.send(
      SdpAnswerSignal(
        senderId: 'bob',
        recipientId: 'alice',
        timestamp: DateTime(2026),
        sdp: 'v=0\r\na=fingerprint:sha-256 DD:EE\r\n',
      ),
    );
    final answer = bobInner.sentMessages.single as SdpAnswerSignal;
    expect(answer.sdp, isEmpty);
    expect(answer.e2ee, isNotEmpty);
    final aliceReceived = await deliver(alice, aliceInner, [answer]);
    expect((aliceReceived.single as SdpAnswerSignal).sdp, contains('DD:EE'));
  });

  test('peers on an older version keep the plaintext signal', () async {
    final (alice, aliceInner, _) = await side('alice');
    final (bob, bobInner, _) = await side('bob');
    await alice.send(offer());
    final wire = aliceInner.sentMessages.single as SdpOfferSignal;
    expect(wire.e2ee, isNull);
    expect(wire.sdp, _offerSdp);
    final received = await deliver(bob, bobInner, [wire]);
    expect((received.single as SdpOfferSignal).sdp, _offerSdp);
  });

  test('a plaintext signal from an encrypting peer is dropped', () async {
    final (bob, bobInner, bobCaps) = await side('bob');
    await bobCaps.recordOne('alice', callSignalEncryptionCapability);
    final control = CallControlSignal(
      senderId: 'alice',
      recipientId: 'bob',
      timestamp: DateTime(2026),
      action: 'END',
    );
    final received = await deliver(bob, bobInner, [offer(), control]);
    // Sunucu sifreli teklifi dusurup duzunu koyamaz; diger sinyaller gecer.
    expect(received.single, isA<CallControlSignal>());
  });

  test('an encrypted answer cannot be replayed as an offer', () async {
    final (alice, aliceInner, aliceCaps) = await side('alice');
    final (bob, bobInner, _) = await side('bob');
    await aliceCaps.recordOne('bob', callSignalEncryptionCapability);
    await alice.send(
      SdpAnswerSignal(
        senderId: 'alice',
        recipientId: 'bob',
        timestamp: DateTime(2026),
        sdp: 'v=0\r\n',
      ),
    );
    final sealed = aliceInner.sentMessages.single as SdpAnswerSignal;
    final relabeled = SdpOfferSignal(
      senderId: 'alice',
      recipientId: 'bob',
      timestamp: DateTime(2026),
      sdp: '',
      callType: 'VOICE',
      e2ee: sealed.e2ee,
    );
    expect(await deliver(bob, bobInner, [relabeled]), isEmpty);
  });

  test('the e2ee field survives the wire encoding', () {
    final signal = IceCandidateSignal(
      senderId: 'a',
      recipientId: 'b',
      timestamp: DateTime(2026),
      candidate: '',
      sdpMLineIndex: 0,
      e2ee: 'E2EE:v1:x',
    );
    final decoded = SignalMessage.decode(signal.encode()) as IceCandidateSignal;
    expect(decoded.e2ee, 'E2EE:v1:x');
    final plain = SdpAnswerSignal(
      senderId: 'a',
      recipientId: 'b',
      timestamp: DateTime(2026),
      sdp: 'v=0',
    );
    expect(plain.toJson().containsKey('e2ee'), isFalse);
  });
}
