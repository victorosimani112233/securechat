import 'dart:convert';
import 'dart:io';

import 'package:flutter_securechat/src/media/janus_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Janus transaction JSEP is consumed once; unsolicited JSEP is emitted',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <WebSocket>[];
      final requests = <Map<String, dynamic>>[];
      final subscription = server.listen((request) async {
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer local-token',
        );
        final socket = await WebSocketTransformer.upgrade(
          request,
          protocolSelector: (protocols) => 'janus-protocol',
        );
        sockets.add(socket);
        socket.listen((raw) {
          final frame = jsonDecode(raw as String) as Map<String, dynamic>;
          requests.add(frame);
          final transaction = frame['transaction'];
          final base = {'transaction': transaction};
          switch (frame['janus']) {
            case 'create':
              socket.add(
                jsonEncode({
                  ...base,
                  'janus': 'success',
                  'data': {'id': 1},
                }),
              );
            case 'attach':
              socket.add(
                jsonEncode({
                  ...base,
                  'janus': 'success',
                  'data': {'id': requests.length + 10},
                }),
              );
            case 'message':
              socket.add(jsonEncode({...base, 'janus': 'ack'}));
              final body = frame['body'] as Map;
              final isSubscriber = body['ptype'] == 'subscriber';
              final isPublish = body['request'] == 'configure';
              socket.add(
                jsonEncode({
                  ...base,
                  'janus': 'event',
                  'sender': frame['handle_id'],
                  'plugindata': {
                    'data': {
                      'videoroom': isSubscriber ? 'attached' : 'joined',
                      if (body['ptype'] == 'publisher')
                        'publishers': [
                          {'id': 99, 'display': 'peer'},
                        ],
                    },
                  },
                  if (isSubscriber || isPublish)
                    'jsep': {
                      'type': isSubscriber ? 'offer' : 'answer',
                      'sdp': 'test-sdp',
                    },
                }),
              );
          }
        });
      });
      final client = JanusClient(requestTimeout: const Duration(seconds: 1));
      final events = <JanusEvent>[];
      final listener = client.events.listen(events.add);
      addTearDown(() async {
        await client.dispose();
        await listener.cancel();
        for (final socket in sockets) {
          await socket.close();
        }
        await subscription.cancel();
        await server.close(force: true);
      });
      expect(
        await client.connect(
          url: 'ws://127.0.0.1:${server.port}',
          accessToken: 'local-token',
        ),
        isTrue,
      );
      await client.createSession();
      await client.attachVideoRoom();
      expect(await client.joinAsPublisher(roomId: 42, displayName: 'self'), [
        (99, 'peer'),
      ]);
      expect(await client.publishSdp('v=0'), 'test-sdp');
      expect(await client.subscribeToFeed(99), 'test-sdp');
      await client.answerSubscription(feedId: 99, answerSdp: 'v=0');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        events,
        isEmpty,
        reason: 'Transaction response must not negotiate SDP twice',
      );
      sockets.single.add(
        jsonEncode({
          'janus': 'event',
          'sender': client.subscriberHandleId(99),
          'jsep': {'type': 'offer', 'sdp': 'renegotiation'},
        }),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(events.whereType<JanusRemoteOffer>().single.sdp, 'renegotiation');
      expect(requests.every((r) => !r.containsKey('apisecret')), isTrue);
    },
  );
}
