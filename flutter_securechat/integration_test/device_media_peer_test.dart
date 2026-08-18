import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/core/signal_message.dart';
import 'package:flutter_securechat/src/features/chat/media_preview_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/media/call_models.dart';
import 'package:flutter_securechat/src/media/file_transfer_manager.dart';
import 'package:flutter_securechat/src/media/media_attachment.dart';
import 'package:flutter_securechat/src/media/media_engine.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'physical encrypted media and two-peer WebRTC lifecycle',
    (tester) async {
      final fixture = await tester.runAsync(_verifyMediaAndPeer);
      expect(fixture, isNotNull);
      addTearDown(fixture!.dispose);

      Future<MediaSendRequest?>? result;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  key: const ValueKey('open-media-preview'),
                  onPressed: () {
                    result = Navigator.of(context).push<MediaSendRequest>(
                      MaterialPageRoute(
                        builder: (_) => MediaPreviewScreen(
                          attachments: [fixture.attachment],
                        ),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open-media-preview')));
      await tester.pumpAndSettle();
      expect(find.text(fixture.attachment.fileName), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Device media caption');
      await tester.tap(find.byKey(const ValueKey('media-view-once')));
      await tester.tap(find.byKey(const ValueKey('media-send')));
      await tester.pumpAndSettle();
      final request = await result;
      expect(request?.caption, 'Device media caption');
      expect(request?.isViewOnce, isTrue);
      expect(request?.attachments.single.path, fixture.attachment.path);
      debugPrint('[device-media-peer] preview-caption-view-once');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<_MediaFixture> _verifyMediaAndPeer() async {
  final root = await Directory.systemTemp.createTemp('device_media_peer_');
  try {
    final attachment = await _verifyEncryptedFileTransfer(root);
    await _verifyWebRtcPeerLoopback();
    return _MediaFixture(root, attachment);
  } catch (_) {
    if (await root.exists()) await root.delete(recursive: true);
    rethrow;
  }
}

Future<MediaAttachment> _verifyEncryptedFileTransfer(Directory root) async {
  final signaling = InMemorySignalingService();
  await signaling.connect(
    userId: 'me',
    url: 'wss://device.invalid',
    accessToken: 'token',
  );
  final crypto = LocalAeadCryptoService(
    SecretKey(List<int>.generate(32, (index) => index + 11)),
  );
  final manager = FileTransferManager(
    signaling: signaling,
    crypto: crypto,
    filesDirectory: Directory('${root.path}/received'),
    chunkSize: 32,
  );
  try {
    final payload = Uint8List.fromList(
      List<int>.generate(257, (index) => (index * 29) % 256),
    );
    final source = File('${root.path}/device-report.bin');
    await source.writeAsBytes(payload, flush: true);
    final result = await manager.sendFile(
      localUserId: 'me',
      recipientId: 'peer',
      file: source,
      mimeType: 'application/octet-stream',
      caption: 'private-device-caption',
      isViewOnce: true,
      originalMessageId: 'device-private-message-id',
    );
    expect(result, isA<FileTransferSuccess>());

    final chunks = signaling.sentMessages
        .whereType<FileTransferSignal>()
        .toList(growable: false);
    expect(chunks, hasLength(9));
    final wire = jsonEncode(chunks.map((chunk) => chunk.toJson()).toList());
    expect(wire, isNot(contains('private-device-caption')));
    expect(wire, isNot(contains('device-private-message-id')));
    expect(wire, isNot(contains('device-report.bin')));

    ReceivedFile? received;
    for (final chunk in chunks.reversed) {
      received =
          await manager.receiveChunk(
            FileTransferSignal.fromJson({
              ...chunk.toJson(),
              'senderId': 'peer',
              'recipientId': 'me',
            }),
          ) ??
          received;
    }
    expect(received, isNotNull);
    expect(await received!.file.readAsBytes(), orderedEquals(payload));
    expect(received.caption, 'private-device-caption');
    expect(received.isViewOnce, isTrue);
    expect(received.originalMessageId, 'device-private-message-id');
    final attachment = await MediaAttachment.fromPath(
      received.file.path,
      fileName: received.fileName,
      mimeType: received.mimeType,
      fileSize: received.fileSize,
    );
    debugPrint('[device-media-peer] encrypted-transfer-out-of-order');
    return attachment;
  } finally {
    await manager.dispose();
    await signaling.disconnect();
  }
}

Future<void> _verifyWebRtcPeerLoopback() async {
  final caller = WebRtcMediaEngine();
  final callee = WebRtcMediaEngine();
  final callerCandidates = <_Candidate>[];
  final calleeCandidates = <_Candidate>[];
  final callerStates = <MediaConnectionState>[];
  final calleeStates = <MediaConnectionState>[];
  final callerSubscription = caller.connectionStates.listen(callerStates.add);
  final calleeSubscription = callee.connectionStates.listen(calleeStates.add);
  try {
    final offer = await caller.createOffer(
      video: false,
      iceServers: const <IceServerConfig>[],
      onIceCandidate: (candidate, mid, index) {
        callerCandidates.add(_Candidate(candidate, mid, index));
      },
    );
    await caller.setMuted(true);
    final answer = await callee.acceptOffer(
      offerSdp: offer,
      video: false,
      iceServers: const <IceServerConfig>[],
      onIceCandidate: (candidate, mid, index) {
        calleeCandidates.add(_Candidate(candidate, mid, index));
      },
    );
    await callee.setMuted(true);
    await caller.applyAnswer(answer);

    var callerForwarded = 0;
    var calleeForwarded = 0;
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline)) {
      while (callerForwarded < callerCandidates.length) {
        final candidate = callerCandidates[callerForwarded++];
        await callee.addIceCandidate(
          candidate: candidate.value,
          sdpMid: candidate.mid,
          sdpMLineIndex: candidate.index,
        );
      }
      while (calleeForwarded < calleeCandidates.length) {
        final candidate = calleeCandidates[calleeForwarded++];
        await caller.addIceCandidate(
          candidate: candidate.value,
          sdpMid: candidate.mid,
          sdpMLineIndex: candidate.index,
        );
      }
      if (callerStates.contains(MediaConnectionState.connected) &&
          calleeStates.contains(MediaConnectionState.connected)) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    expect(offer, contains('m=audio'));
    expect(answer, contains('m=audio'));
    expect(callerCandidates, isNotEmpty);
    expect(calleeCandidates, isNotEmpty);
    expect(callerStates, contains(MediaConnectionState.connected));
    expect(calleeStates, contains(MediaConnectionState.connected));
    expect(caller.remoteRenderer.srcObject, isNotNull);
    expect(callee.remoteRenderer.srcObject, isNotNull);
    debugPrint('[device-media-peer] webrtc-offer-answer-ice-connected');
  } finally {
    await callerSubscription.cancel();
    await calleeSubscription.cancel();
    await caller.dispose();
    await callee.dispose();
  }
}

class _Candidate {
  const _Candidate(this.value, this.mid, this.index);

  final String value;
  final String? mid;
  final int index;
}

class _MediaFixture {
  const _MediaFixture(this.root, this.attachment);

  final Directory root;
  final MediaAttachment attachment;

  Future<void> dispose() async {
    if (await root.exists()) await root.delete(recursive: true);
  }
}
