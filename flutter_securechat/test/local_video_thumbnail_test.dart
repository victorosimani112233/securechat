import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_securechat/src/chat/chat_info_service.dart';
import 'package:flutter_securechat/src/features/chat/shared_content_browser.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/platform/native_bridge.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_securechat/src/widgets/local_video_thumbnail.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

const _channel = MethodChannel('com.securechat/native');
const _fallback = Icon(Icons.videocam_outlined);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  for (final size in [
    const Size(400, 800),
    const Size(800, 400),
    const Size(400, 400),
  ]) {
    testWidgets('chat video preview preserves source ratio $size', (
      tester,
    ) async {
      final bytes = await _png(
        tester,
        width: size.width.toInt(),
        height: size.height.toInt(),
      );
      messenger.setMockMethodCallHandler(_channel, (call) async => bytes);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240, maxHeight: 360),
              child: const LocalVideoThumbnail(
                path: '/video.mp4',
                isViewOnce: false,
                preserveAspectRatio: true,
                fallback: _fallback,
              ),
            ),
          ),
        ),
      );
      await _settleDecode(tester);
      final preview = tester.getSize(find.byType(RawImage));
      expect(
        preview.width / preview.height,
        closeTo(size.width / size.height, .001),
      );
      expect(preview.width, lessThanOrEqualTo(240));
      expect(preview.height, lessThanOrEqualTo(360));
      expect(
        tester.widget<RawImage>(find.byType(RawImage)).fit,
        BoxFit.contain,
      );
      expect(tester.takeException(), isNull);
    });
  }

  test(
    'bridge rejects protected and empty paths before invoking native',
    () async {
      const bridge = NativeBridge();
      expect(
        await bridge.localVideoThumbnail(
          path: '/media/secret.mp4',
          isViewOnce: true,
        ),
        isNull,
      );
      expect(
        await bridge.localVideoThumbnail(path: ' ', isViewOnce: false),
        isNull,
      );
      expect(calls, isEmpty);
    },
  );

  test(
    'bridge caps dimensions and rejects invalid or unavailable output',
    () async {
      const bridge = NativeBridge();
      await bridge.localVideoThumbnail(
        path: '/media/video.mp4',
        isViewOnce: false,
        maxSize: 9999,
      );
      expect(calls.single.method, 'localVideoThumbnail');
      expect(calls.single.arguments, {
        'path': '/media/video.mp4',
        'isViewOnce': false,
        'maxSize': 320,
      });
      await bridge.localVideoThumbnail(
        path: '/media/video.mp4',
        isViewOnce: false,
        maxSize: 0,
      );
      expect((calls.last.arguments as Map)['maxSize'], 1);
      for (final bytes in [Uint8List(0), Uint8List(512 * 1024 + 1)]) {
        messenger.setMockMethodCallHandler(_channel, (_) async => bytes);
        expect(
          await bridge.localVideoThumbnail(
            path: '/media/video.mp4',
            isViewOnce: false,
          ),
          isNull,
        );
      }
      messenger.setMockMethodCallHandler(
        _channel,
        (_) async => throw PlatformException(code: 'MISSING_FILE'),
      );
      expect(
        await bridge.localVideoThumbnail(
          path: '/media/missing.mp4',
          isViewOnce: false,
        ),
        isNull,
      );
      messenger.setMockMethodCallHandler(_channel, null);
      expect(
        await bridge.localVideoThumbnail(
          path: '/media/video.mp4',
          isViewOnce: false,
        ),
        isNull,
      );
    },
  );

  testWidgets('widget renders bounded native frame and reuses it on rebuild', (
    tester,
  ) async {
    final bytes = await _png(tester, width: 640, height: 360);
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return bytes;
    });
    final initialCacheSize = PaintingBinding.instance.imageCache.currentSize;
    await tester.pumpWidget(_app('/media/video.mp4'));
    await _settleDecode(tester);
    final image = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(image.width, 320);
    expect(image.height, 180);
    expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
    expect(calls, hasLength(1));
    expect(PaintingBinding.instance.imageCache.currentSize, initialCacheSize);
    await tester.pumpWidget(_app('/media/video.mp4'));
    await tester.pump();
    expect(calls, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(image.debugDisposed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('widget never requests or displays view-once video', (
    tester,
  ) async {
    await tester.pumpWidget(_app('/media/secret.mp4', viewOnce: true));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(find.byType(RawImage), findsNothing);
    await tester.pumpWidget(_app(''));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
  });

  testWidgets(
    'late response is ignored after a path change or privacy change',
    (tester) async {
      final bytes = await _png(tester);
      final pending = Completer<Uint8List?>();
      messenger.setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        return calls.length == 1 ? pending.future : null;
      });
      await tester.pumpWidget(_app('/media/old.mp4'));
      await tester.pumpWidget(_app('/media/new.mp4'));
      await tester.pump();
      pending.complete(bytes);
      await _settleDecode(tester);
      expect(find.byType(RawImage), findsNothing);
      expect(calls, hasLength(2));

      final privatePending = Completer<Uint8List?>();
      messenger.setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        return privatePending.future;
      });
      await tester.pumpWidget(_app('/media/protected.mp4'));
      await tester.pumpWidget(_app('/media/protected.mp4', viewOnce: true));
      privatePending.complete(bytes);
      await _settleDecode(tester);
      expect(calls, hasLength(3));
      expect(find.byType(RawImage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('late response after disposal is harmless', (tester) async {
    final pending = Completer<Uint8List?>();
    final bytes = await _png(tester);
    messenger.setMockMethodCallHandler(_channel, (_) => pending.future);
    await tester.pumpWidget(_app('/media/video.mp4'));
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(bytes);
    await _settleDecode(tester);
    expect(find.byType(RawImage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing file and corrupt frame bytes retain fallback', (
    tester,
  ) async {
    await tester.pumpWidget(_app('/media/missing.mp4'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.videocam_outlined), findsOneWidget);
    messenger.setMockMethodCallHandler(
      _channel,
      (_) async => Uint8List.fromList([1, 2, 3]),
    );
    await tester.pumpWidget(_app('/media/corrupt.mp4'));
    await _settleDecode(tester);
    expect(find.byType(RawImage), findsNothing);
    expect(find.byIcon(Icons.videocam_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'gallery previews ordinary video but never submits view-once video',
    (tester) async {
      final bytes = await _png(tester);
      messenger.setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        return bytes;
      });
      await tester.pumpWidget(
        AppContainerScope(
          container: createWidgetTestContainer(),
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: SharedContentBrowser(
              service: _MediaService(),
              conversationId: 'chat',
              section: SharedContentSection.media,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _settleDecode(tester);
      expect(find.byType(LocalVideoThumbnail), findsOneWidget);
      expect(find.byType(RawImage), findsOneWidget);
      expect(calls, hasLength(1));
      expect((calls.single.arguments as Map)['path'], '/media/video.mp4');
      expect(
        find.byKey(const ValueKey('chat-info-message-once')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('chat-info-message-viewed')),
        findsNothing,
      );
      expect(find.byIcon(Icons.audiotrack_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'Android decoder contract is bounded, private, in-memory and releases resources',
    () {
      final source = File(
        'android/app/src/main/kotlin/com/securechat/app/MainActivity.kt',
      ).readAsStringSync();
      final handler = source
          .split('private fun localVideoThumbnail(')
          .last
          .split('private fun openLocalFile(')
          .first;
      expect(source, contains('"localVideoThumbnail" -> localVideoThumbnail'));
      expect(
        handler.indexOf('values["isViewOnce"] != false'),
        lessThan(handler.indexOf('videoThumbnailExecutor.execute')),
      );
      expect(handler, contains('File(filesDir, "media").canonicalFile'));
      expect(
        handler,
        contains('file.path.startsWith(root.path + File.separator)'),
      );
      expect(handler, contains('coerceIn(1, 320)'));
      expect(handler, contains('getScaledFrameAtTime('));
      expect(handler, contains('MediaStore.Video.Thumbnails.MINI_KIND'));
      expect(handler, contains('ByteArrayOutputStream().use'));
      expect(handler, contains('frame?.recycle()'));
      expect(handler, contains('retriever?.release()'));
      expect(handler, isNot(contains('FileOutputStream')));
      expect(handler, isNot(contains('getFrameAtTime(')));
      expect(source, contains('ArrayBlockingQueue<Runnable>(24)'));
      expect(source, contains('videoThumbnailExecutor.shutdown()'));
    },
  );

  test(
    'iOS decoder contract bounds and rotates frames without writing thumbnails',
    () {
      final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();
      final handler = source
          .split('private func localVideoThumbnail(')
          .last
          .split('private func openLocalFile(')
          .first;
      expect(source, contains('case "localVideoThumbnail":'));
      expect(
        handler.indexOf('!isViewOnce'),
        lessThan(handler.indexOf('videoThumbnailQueue.addOperation')),
      );
      expect(
        handler,
        contains('SecureChatPrivateFilePolicy.validatedURL(path: path)'),
      );
      expect(handler, contains('Library/Application Support/media'));
      expect(handler, contains('max(1, min(320,'));
      expect(handler, contains('generator.maximumSize = CGSize('));
      expect(
        handler,
        contains('generator.appliesPreferredTrackTransform = true'),
      );
      expect(handler, contains('autoreleasepool'));
      expect(handler, contains('generator.cancelAllCGImageGeneration()'));
      expect(handler, contains('asset.cancelLoading()'));
      expect(handler, contains(r'FlutterStandardTypedData(bytes: $0)'));
      expect(handler, isNot(contains('.write(')));
      expect(source, contains('queue.maxConcurrentOperationCount = 1'));
    },
  );
}

Widget _app(String path, {bool viewOnce = false}) => MaterialApp(
  home: Center(
    child: SizedBox(
      width: 180,
      height: 180,
      child: LocalVideoThumbnail(
        path: path,
        isViewOnce: viewOnce,
        fallback: _fallback,
      ),
    ),
  ),
);

Future<Uint8List> _png(
  WidgetTester tester, {
  int width = 4,
  int height = 2,
}) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.green, BlendMode.src);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(width, height);
  final bytes = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  ))!;
  image.dispose();
  picture.dispose();
  return bytes.buffer.asUint8List();
}

Future<void> _settleDecode(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}

class _MediaService implements ChatInfoService {
  @override
  Stream<List<MessageEntity>> watchMedia(String id) => Stream.value([
    for (final entry in ['video', 'once', 'viewed', 'audio'])
      MessageEntity(
        id: entry,
        conversationId: id,
        senderId: 'peer',
        content: entry == 'audio'
            ? 'Audio.mp3|audio/mpeg|1|/media/audio.mp3'
            : 'Video.mp4|video/mp4|1|/media/$entry.mp4',
        contentType: StorageMessageContentType.file,
        timestamp: 1700000000000,
        status: StorageMessageStatus.read,
        isOutgoing: false,
        isViewOnce: entry == 'once' || entry == 'viewed',
        isViewed: entry == 'viewed',
      ),
  ]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
