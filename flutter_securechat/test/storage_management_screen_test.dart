import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/features/chat/media_viewer_screen.dart';
import 'package:flutter_securechat/src/features/settings/chat_storage_screen.dart';
import 'package:flutter_securechat/src/features/settings/storage_usage_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/security/chat_access_service.dart';
import 'package:flutter_securechat/src/security/chat_lock_credential_service.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_securechat/src/storage/storage_management_service.dart';
import 'package:flutter_securechat/src/theme/secure_chat_theme.dart';
import 'package:flutter_securechat/src/widgets/local_image_thumbnail.dart';
import 'package:flutter_securechat/src/widgets/local_video_thumbnail.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

const _chatId = 'storage-chat';
const _privateName = 'private-view-once-filename.png';
const _nativeChannel = MethodChannel('com.securechat/native');
const _captureKey = ValueKey('storage-test-capture');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final nativeCalls = <MethodCall>[];
  late _Fixture fixture;

  setUpAll(() async {
    for (final font in {
      'Inter': 'assets/fonts/inter_regular.ttf',
      'SpaceGrotesk': 'assets/fonts/space_grotesk_semibold.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  setUp(() {
    fixture = _Fixture();
    addTearDown(fixture.container.signaling.dispose);
    addTearDown(fixture.service.messageUpdates.close);
    nativeCalls.clear();
    messenger.setMockMethodCallHandler(_nativeChannel, (call) async {
      nativeCalls.add(call);
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(_nativeChannel, null));

  testWidgets(
    'browse tap opens image; only trash enters selection and close restores browsing',
    (tester) async {
      final bytes = await _previewPng(tester);
      final photo = await _mediaFile(tester, 'browse.png', bytes);
      fixture.service.files
        ..clear()
        ..add(
          _storageFile(
            'photo',
            'browse.png',
            'image/png',
            bytes.length,
            path: photo.path,
          ),
        );
      await _pumpScreen(tester, fixture);
      await _openDetail(tester, selecting: false);
      expect(find.byType(Checkbox), findsNothing);
      expect(_deleteSelected, findsNothing);
      expect(
        tester.widget<Semantics>(_file('photo')).properties.checked,
        isNull,
      );
      await tester.tap(_file('photo'));
      await tester.pumpAndSettle();
      expect(find.byType(MediaViewerScreen), findsOneWidget);
      expect(fixture.service.openRequests, ['photo']);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('storage-selection-mode')));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsOneWidget);
      expect(tester.widget<FilledButton>(_deleteSelected).onPressed, isNull);
      await tester.tap(_file('photo'));
      await tester.pumpAndSettle();
      expect(_selected(tester, 'photo'), isTrue);
      expect(fixture.service.openRequests, ['photo']);
      await tester.tap(find.byTooltip(_strings(tester).cancel_selection));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNothing);
      expect(_deleteSelected, findsNothing);
      await tester.tap(_file('photo'));
      await tester.pumpAndSettle();
      expect(find.byType(MediaViewerScreen), findsOneWidget);
      expect(fixture.service.openRequests, ['photo', 'photo']);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  for (final (id, mime) in [
    ('video', 'video/mp4'),
    ('document', 'application/pdf'),
    ('audio', 'audio/ogg'),
  ]) {
    testWidgets('browse tap opens $id with existing native file facility', (
      tester,
    ) async {
      fixture.service.files
        ..clear()
        ..add(_storageFile(id, '$id.bin', mime, 10));
      await _pumpScreen(tester, fixture);
      await _openDetail(tester, selecting: false);
      await tester.tap(_file(id));
      await tester.pumpAndSettle();
      expect(
        nativeCalls
            .where((call) => call.method == 'openLocalFile')
            .single
            .arguments,
        {'path': '/managed/$id.bin', 'mimeType': mime},
      );
      expect(find.byType(Checkbox), findsNothing);
      expect(_deleteSelected, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'protected deferred missing and expired media cannot open in browse mode',
    (tester) async {
      fixture.service.files
        ..clear()
        ..addAll([
          _storageFile('once', 'once.png', 'image/png', 1, viewOnce: true),
          _storageFile(
            'deferred',
            'deferred.png',
            'image/png',
            1,
            deferred: true,
          ),
          _storageFile(
            'missing',
            'missing.pdf',
            'application/pdf',
            1,
            available: false,
          ),
          _storageFile(
            'expired',
            'expired.png',
            'image/png',
            1,
            expiresAt: DateTime(2000),
          ),
        ]);
      await _pumpScreen(tester, fixture);
      await _openDetail(tester, selecting: false);
      for (final id in ['once', 'deferred', 'missing']) {
        await tester.tap(_file(id));
        await tester.pumpAndSettle();
      }
      expect(_file('expired'), findsNothing);
      expect(fixture.service.openRequests, isEmpty);
      expect(nativeCalls, isEmpty);
      expect(find.byType(MediaViewerScreen), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
    },
  );

  for (final revoke in [
    'pause',
    'expired',
    'deferred',
    'view-once',
    'removed',
  ]) {
    testWidgets('open image viewer is revoked on $revoke', (tester) async {
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      final bytes = await _previewPng(tester);
      final photo = await _mediaFile(tester, 'revoke.png', bytes);
      fixture.service.files
        ..clear()
        ..add(
          _storageFile(
            'photo',
            'revoke.png',
            'image/png',
            bytes.length,
            path: photo.path,
          ),
        );
      await _pumpScreen(tester, fixture);
      await _openDetail(tester, selecting: false);
      await tester.tap(_file('photo'));
      await tester.pumpAndSettle();
      expect(find.byType(MediaViewerScreen), findsOneWidget);
      if (revoke == 'pause') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.scheduleForcedFrame();
      } else {
        fixture.service.messageUpdates.add([
          if (revoke != 'removed')
            _storageFile(
              'photo',
              'revoke.png',
              'image/png',
              bytes.length,
              path: photo.path,
              deferred: revoke == 'deferred',
              viewOnce: revoke == 'view-once',
              expiresAt: revoke == 'expired' ? DateTime(2000) : null,
            ).message,
        ]);
      }
      await tester.pumpAndSettle();
      expect(find.byType(MediaViewerScreen), findsNothing);
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'pending file validation cannot open after background and reauthorization',
    (tester) async {
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      fixture.service.files
        ..clear()
        ..add(_storageFile('document', 'file.pdf', 'application/pdf', 1));
      fixture.service.pendingOpen = Completer<ChatStorageFile?>();
      await _pumpScreen(tester, fixture);
      await _openDetail(tester, selecting: false);
      await tester.tap(_file('document'));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      fixture.service.pendingOpen!.complete(fixture.service.files.single);
      await tester.pumpAndSettle();
      expect(
        nativeCalls.where((call) => call.method == 'openLocalFile'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pull to refresh reloads disk files without duplicating message watchers',
    (tester) async {
      fixture.service.files
        ..clear()
        ..add(_storageFile('first', 'first.pdf', 'application/pdf', 1024));
      await _pumpScreen(tester, fixture);
      await _openDetail(tester);
      fixture.service.files.add(
        _storageFile('new', 'new.pdf', 'application/pdf', 2048),
      );
      expect(_file('new'), findsNothing);
      await tester.drag(find.byType(GridView), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(fixture.service.fileRequests, [_chatId, _chatId]);
      expect(fixture.service.watchRequests, [_chatId]);
      expect(_file('new'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final mime in ['image/png', 'video/mp4']) {
    for (final update in ['removed', 'deleted', 'view-once', 'expired']) {
      testWidgets('live $update update revokes $mime preview', (tester) async {
        final bytes = await _previewPng(tester);
        final name = mime.startsWith('image/')
            ? 'live-private.png'
            : 'live-private.mp4';
        final media = await _mediaFile(tester, name, bytes);
        fixture.service.files
          ..clear()
          ..add(
            _storageFile('live', name, mime, bytes.length, path: media.path),
          );
        messenger.setMockMethodCallHandler(_nativeChannel, (call) async {
          nativeCalls.add(call);
          return bytes;
        });
        await _pumpScreen(tester, fixture);
        final cacheSize = PaintingBinding.instance.imageCache.currentSize;
        await _openDetail(tester);
        await _settleDecode(tester);
        final decoded = tester
            .widget<RawImage>(
              find.descendant(
                of: _preview('live'),
                matching: find.byType(RawImage),
              ),
            )
            .image!;
        await tester.tap(_file('live'));
        await tester.pumpAndSettle();
        expect(_selected(tester, 'live'), isTrue);
        final nativeRequestCount = nativeCalls.length;

        fixture.service.messageUpdates.add([
          if (update != 'removed')
            _storageFile(
              'live',
              name,
              mime,
              bytes.length,
              path: media.path,
              viewOnce: update == 'view-once',
              deleted: update == 'deleted',
              expiresAt: update == 'expired' ? DateTime(2000) : null,
            ).message,
        ]);
        await tester.pumpAndSettle();
        expect(_preview('live'), findsNothing);
        expect(find.byType(LocalImageThumbnail), findsNothing);
        expect(find.byType(LocalVideoThumbnail), findsNothing);
        expect(find.byType(RawImage), findsNothing);
        expect(decoded.debugDisposed, isTrue);
        expect(PaintingBinding.instance.imageCache.currentSize, cacheSize);
        expect(nativeCalls, hasLength(nativeRequestCount));
        expect(find.textContaining(name), findsNothing);
        expect(
          find.bySemanticsLabel(RegExp(RegExp.escape(name))),
          findsNothing,
        );
        if (update == 'view-once') {
          // Protected files remain selectable for cleanup, but never previewable.
          expect(_file('live'), findsOneWidget);
          expect(_selected(tester, 'live'), isTrue);
          expect(
            find.text(_strings(tester).view_once_protected),
            findsOneWidget,
          );
        } else {
          expect(_file('live'), findsNothing);
          expect(_deleteSelected, findsNothing);
          expect(find.text(_strings(tester).storage_no_files), findsOneWidget);
        }
        expect(fixture.service.fileRequests, [_chatId]);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(fixture.service.messageUpdates.hasListener, isFalse);
      });
    }
  }

  testWidgets(
    'message watching requires access and stops on pause and disposal',
    (tester) async {
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      fixture.service.conversation = fixture.service.conversation.copyWith(
        isLocked: true,
      );
      fixture.auth.allowed = false;
      await _pumpScreen(tester, fixture);
      await _openDetail(tester);
      expect(fixture.service.watchRequests, isEmpty);
      expect(fixture.service.messageUpdates.hasListener, isFalse);
      fixture.auth.allowed = true;
      await tester.tap(find.text(_strings(tester).chat_lock_unlock_action));
      await tester.pumpAndSettle();
      expect(fixture.service.watchRequests, [_chatId]);
      expect(fixture.service.messageUpdates.hasListener, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(fixture.service.messageUpdates.hasListener, isFalse);
      fixture.auth.allowed = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(fixture.service.watchRequests, [_chatId]);
      expect(fixture.service.messageUpdates.hasListener, isFalse);
      fixture.auth.allowed = true;
      await tester.tap(find.text(_strings(tester).chat_lock_unlock_action));
      await tester.pumpAndSettle();
      expect(fixture.service.watchRequests, [_chatId, _chatId]);
      expect(fixture.service.messageUpdates.hasListener, isTrue);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(fixture.service.messageUpdates.hasListener, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'expired and deleted media at load never enter the grid or decoder',
    (tester) async {
      final bytes = await _previewPng(tester);
      final photo = await _mediaFile(tester, 'expired-private.png', bytes);
      fixture.service.files
        ..clear()
        ..addAll([
          for (final mime in ['image/png', 'video/mp4'])
            _storageFile(
              'expired-$mime',
              'expired-private.png',
              mime,
              bytes.length,
              path: photo.path,
              expiresAt: DateTime(2000),
            ),
          _storageFile(
            'deleted',
            'deleted-private.png',
            'image/png',
            bytes.length,
            path: photo.path,
            deleted: true,
          ),
        ]);
      messenger.setMockMethodCallHandler(_nativeChannel, (call) async {
        nativeCalls.add(call);
        return bytes;
      });
      await _pumpScreen(tester, fixture);
      await _openDetail(tester);
      await _settleDecode(tester);
      expect(find.text(_strings(tester).storage_no_files), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(LocalImageThumbnail), findsNothing);
      expect(find.byType(LocalVideoThumbnail), findsNothing);
      expect(find.byType(RawImage), findsNothing);
      expect(nativeCalls, isEmpty);
      expect(_deleteSelected, findsNothing);
      for (final file in fixture.service.files) {
        expect(_file(file.message.id), findsNothing);
      }
      for (final name in ['expired-private.png', 'deleted-private.png']) {
        expect(find.textContaining(name), findsNothing);
        expect(
          find.bySemanticsLabel(RegExp(RegExp.escape(name))),
          findsNothing,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('photo grid preview decodes real local image pixels', (
    tester,
  ) async {
    final bytes = await _previewPng(tester);
    final photo = await _mediaFile(tester, 'photo.png', bytes);
    fixture.service.files
      ..clear()
      ..add(
        _storageFile(
          'photo',
          'photo.png',
          'image/png',
          bytes.length,
          path: photo.path,
        ),
      );
    await _pumpScreen(tester, fixture);
    final cacheSize = PaintingBinding.instance.imageCache.currentSize;
    await _openDetail(tester);
    await _settleDecode(tester);
    expect(
      tester.widget<LocalImageThumbnail>(_preview('photo')).isViewOnce,
      isFalse,
    );
    final raw = tester.widget<RawImage>(
      find.descendant(of: _preview('photo'), matching: find.byType(RawImage)),
    );
    final decodedImage = raw.image!;
    expect(decodedImage.width, 384);
    expect(decodedImage.height, 256);
    expect(raw.fit, BoxFit.contain);
    expect(PaintingBinding.instance.imageCache.currentSize, cacheSize);
    await _expectPreviewPixels(tester, 'photo');
    expect(_selected(tester, 'photo'), isFalse);
    await tester.tap(_preview('photo'));
    await tester.pumpAndSettle();
    expect(_selected(tester, 'photo'), isTrue);
    expect(nativeCalls, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(decodedImage.debugDisposed, isTrue);
    expect(PaintingBinding.instance.imageCache.currentSize, cacheSize);
  });

  testWidgets(
    'image thumbnail decodes percent-encoded file URI without global caching',
    (tester) async {
      final bytes = await _previewPng(tester);
      final photo = await _mediaFile(tester, 'photo #1.png', bytes);
      final cacheSize = PaintingBinding.instance.imageCache.currentSize;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: LocalImageThumbnail(
            key: const ValueKey('storage-preview-uri'),
            path: photo.uri.toString(),
            isViewOnce: false,
            fallback: const SizedBox(),
          ),
        ),
      );
      await _settleDecode(tester);
      await _expectPreviewPixels(tester, 'uri');
      final image = tester.widget<RawImage>(find.byType(RawImage)).image!;
      expect(PaintingBinding.instance.imageCache.currentSize, cacheSize);
      await tester.pumpWidget(const SizedBox());
      expect(image.debugDisposed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('video grid preview decodes the mocked native frame', (
    tester,
  ) async {
    final bytes = await _previewPng(tester);
    final video = await _mediaFile(tester, 'video.mp4', [1]);
    fixture.service.files
      ..clear()
      ..add(
        _storageFile('video', 'video.mp4', 'video/mp4', 1, path: video.path),
      );
    messenger.setMockMethodCallHandler(_nativeChannel, (call) async {
      nativeCalls.add(call);
      return bytes;
    });
    await _pumpScreen(tester, fixture);
    await _openDetail(tester);
    await _settleDecode(tester);
    expect(
      tester.widget<LocalVideoThumbnail>(_preview('video')).preserveAspectRatio,
      isTrue,
    );
    expect(nativeCalls, hasLength(1));
    expect(nativeCalls.single.method, 'localVideoThumbnail');
    expect(nativeCalls.single.arguments, {
      'path': video.path,
      'isViewOnce': false,
      'maxSize': 320,
    });
    await _expectPreviewPixels(tester, 'video');
    await tester.tap(_file('video'));
    await tester.pumpAndSettle();
    expect(_selected(tester, 'video'), isTrue);
    expect(nativeCalls, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('view-once photo and video never decode or expose filenames', (
    tester,
  ) async {
    final bytes = await _previewPng(tester);
    final photo = await _mediaFile(tester, _privateName, bytes);
    fixture.service.files
      ..clear()
      ..addAll([
        _storageFile(
          'secret-photo',
          _privateName,
          'image/png',
          bytes.length,
          path: photo.path,
          viewOnce: true,
        ),
        _storageFile(
          'secret-video',
          'private-video.mp4',
          'video/mp4',
          bytes.length,
          path: photo.path,
          viewOnce: true,
        ),
      ]);
    messenger.setMockMethodCallHandler(_nativeChannel, (call) async {
      nativeCalls.add(call);
      return bytes;
    });
    await _pumpScreen(tester, fixture);
    await _openDetail(tester);
    await _settleDecode(tester);
    expect(find.byType(LocalImageThumbnail), findsNothing);
    expect(find.byType(LocalVideoThumbnail), findsNothing);
    expect(find.byType(RawImage), findsNothing);
    expect(nativeCalls, isEmpty);
    for (final file in fixture.service.files) {
      await _showFile(tester, file.message.id);
      expect(find.textContaining(file.message.fileName!), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(file.message.fileName!))),
        findsNothing,
      );
    }
    expect(find.text(_strings(tester).view_once_protected), findsNWidgets(2));
    await tester.tap(_file('secret-video'));
    await tester.pumpAndSettle();
    expect(_selected(tester, 'secret-video'), isTrue);
    expect(nativeCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final deferred in [false, true]) {
    testWidgets(
      '${deferred ? 'deferred' : 'unavailable'} media skips preview decoding',
      (tester) async {
        final bytes = await _previewPng(tester);
        final photo = await _mediaFile(tester, 'unopened.png', bytes);
        fixture.service.files
          ..clear()
          ..addAll([
            for (final mime in ['image/png', 'video/mp4'])
              _storageFile(
                mime,
                'unopened.png',
                mime,
                bytes.length,
                path: photo.path,
                deferred: deferred,
                available: deferred,
              ),
          ]);
        messenger.setMockMethodCallHandler(_nativeChannel, (call) async {
          nativeCalls.add(call);
          return bytes;
        });
        await _pumpScreen(tester, fixture);
        await _openDetail(tester);
        await _settleDecode(tester);
        expect(find.byType(LocalImageThumbnail), findsNothing);
        expect(find.byType(LocalVideoThumbnail), findsNothing);
        expect(find.byType(RawImage), findsNothing);
        expect(nativeCalls, isEmpty);
        expect(find.byType(Checkbox), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('corrupt image and video frames retain selectable fallbacks', (
    tester,
  ) async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final corrupt = await _mediaFile(tester, 'corrupt.png', bytes);
    fixture.service.files
      ..clear()
      ..addAll([
        _storageFile(
          'photo',
          'corrupt.png',
          'image/png',
          bytes.length,
          path: corrupt.path,
        ),
        _storageFile(
          'video',
          'corrupt.mp4',
          'video/mp4',
          bytes.length,
          path: corrupt.path,
        ),
      ]);
    messenger.setMockMethodCallHandler(_nativeChannel, (call) async {
      nativeCalls.add(call);
      return bytes;
    });
    await _pumpScreen(tester, fixture);
    await _openDetail(tester);
    await _settleDecode(tester);
    expect(find.byType(RawImage), findsNothing);
    expect(nativeCalls, hasLength(1));
    for (final id in ['photo', 'video']) {
      expect(
        find.descendant(of: _preview(id), matching: find.byType(Icon)),
        findsWidgets,
      );
      await tester.tap(_file(id));
      await tester.pumpAndSettle();
      expect(_selected(tester, id), isTrue);
    }
    expect(
      find.text(_strings(tester).storage_delete_action(2)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final (width, scale, dark) in [
    (390.0, 1.0, false),
    (390.0, 1.0, true),
    (320.0, 2.0, false),
  ]) {
    testWidgets(
      'real media grid fits ${width}px ${scale}x ${dark ? 'dark' : 'light'}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final bytes = await _previewPng(tester);
        final photo = await _mediaFile(tester, 'photo.png', bytes);
        fixture.service.files[0] = _storageFile(
          'photo',
          'photo.png',
          'image/png',
          bytes.length,
          path: photo.path,
        );
        messenger.setMockMethodCallHandler(_nativeChannel, (call) async {
          nativeCalls.add(call);
          return bytes;
        });
        await _pumpScreen(tester, fixture, textScale: scale, dark: dark);
        await _openDetail(tester);
        await _settleDecode(tester);
        final grid = tester.widget<GridView>(find.byType(GridView));
        expect(
          (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
              .crossAxisCount,
          scale == 2 ? 1 : 2,
        );
        await _expectPreviewPixels(tester, 'photo');
        await _captureScreen(
          tester,
          'media-${width.toInt()}-${scale}x-${dark ? 'dark' : 'light'}',
        );
        for (final file in fixture.service.files) {
          await _showFile(tester, file.message.id);
          expect(
            tester.getRect(_file(file.message.id)).width,
            lessThanOrEqualTo(width),
          );
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets('overview opens chat detail and refreshes when returning', (
    tester,
  ) async {
    await _pumpScreen(tester, fixture);
    expect(find.text(_summary(tester, fixture)), findsOneWidget);
    expect(fixture.service.analyzeCalls, 1);
    await _openDetail(tester);
    expect(find.byType(ChatStorageScreen), findsOneWidget);
    expect(find.text(fixture.service.conversation.peerName), findsOneWidget);
    expect(fixture.service.fileRequests, [_chatId]);
    expect(fixture.auth.requests, isEmpty);
    expect(find.byType(GridView), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(5));

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ChatStorageScreen), findsNothing);
    expect(find.text(_summary(tester, fixture)), findsOneWidget);
    expect(fixture.service.analyzeCalls, 2);
  });

  testWidgets('category filters and select-all affect the visible files', (
    tester,
  ) async {
    await _pumpScreen(tester, fixture);
    await _openDetail(tester);
    final strings = _strings(tester);
    for (final (label, ids) in [
      (strings.photos, ['photo', 'view-once']),
      (strings.videos, ['video']),
      (strings.storage_audio, ['audio']),
      (strings.documents, ['document']),
    ]) {
      await _filter(tester, label);
      expect(find.byType(Checkbox), findsNWidgets(ids.length));
      for (final id in ids) {
        await _showFile(tester, id);
        expect(_file(id), findsOneWidget);
      }
    }

    await _filter(tester, strings.photos);
    await tester.tap(find.byTooltip(strings.select_all));
    await tester.pumpAndSettle();
    expect(_selected(tester, 'photo'), isTrue);
    expect(_selected(tester, 'view-once'), isTrue);
    expect(find.text(strings.storage_delete_action(2)), findsOneWidget);

    await _filter(tester, strings.documents);
    expect(_selected(tester, 'document'), isFalse);
    await tester.tap(_file('document'));
    await tester.pumpAndSettle();
    expect(find.text(strings.storage_delete_action(3)), findsOneWidget);
    await _filter(tester, strings.storage_all_files);
    await _showFile(tester, 'photo');
    expect(_selected(tester, 'photo'), isTrue);
    await _showFile(tester, 'document');
    expect(_selected(tester, 'document'), isTrue);
    await _showFile(tester, 'video');
    expect(_selected(tester, 'video'), isFalse);

    await tester.tap(find.byTooltip(strings.select_all));
    await tester.pumpAndSettle();
    expect(find.text(strings.storage_delete_action(5)), findsOneWidget);
    await tester.tap(find.byTooltip(strings.select_all));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(_deleteSelected).onPressed, isNull);
    for (final file in fixture.service.files) {
      await _showFile(tester, file.message.id);
      expect(_selected(tester, file.message.id), isFalse);
    }
  });

  testWidgets(
    'cancel preserves files and confirm refreshes detail and overview',
    (tester) async {
      await _pumpScreen(tester, fixture);
      final originalSummary = _summary(tester, fixture);
      await _openDetail(tester);
      final strings = _strings(tester);
      await _showFile(tester, 'video');
      await tester.tap(_file('video'));
      await tester.pumpAndSettle();
      await tester.tap(_deleteSelected);
      await tester.pumpAndSettle();
      expect(find.text(strings.storage_delete_selected(1)), findsOneWidget);
      await tester.tap(find.text(strings.cancel));
      await tester.pumpAndSettle();
      expect(fixture.service.cleanRequests, isEmpty);
      expect(_selected(tester, 'video'), isTrue);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text(originalSummary), findsOneWidget);

      await _openDetail(tester);
      await _showFile(tester, 'video');
      expect(_selected(tester, 'video'), isFalse);
      await tester.tap(_file('video'));
      await tester.pumpAndSettle();
      await tester.tap(_deleteSelected);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, strings.cd_clear));
      await tester.pumpAndSettle();
      expect(fixture.service.cleanRequests, hasLength(1));
      expect(fixture.service.cleanRequests.single.$1, _chatId);
      expect(fixture.service.cleanRequests.single.$2, {'video'});
      expect(_file('video'), findsNothing);
      expect(_file('photo'), findsOneWidget);
      expect(_deleteSelected, findsNothing);
      expect(
        find.text(strings.storage_cleanup_result(1, formatStorageBytes(3072))),
        findsOneWidget,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text(originalSummary), findsNothing);
      expect(find.text(_summary(tester, fixture)), findsOneWidget);
      expect(fixture.service.analyzeCalls, 3);
    },
  );

  for (final throwsError in [false, true]) {
    testWidgets(
      'locked chat fails closed on ${throwsError ? 'error' : 'denial'}',
      (tester) async {
        fixture.service.conversation = fixture.service.conversation.copyWith(
          isLocked: true,
        );
        fixture.auth.allowed = false;
        fixture.auth.error = throwsError
            ? PlatformException(code: 'authentication-unavailable')
            : null;
        await _pumpScreen(tester, fixture);
        await _openDetail(tester);
        expect(fixture.auth.requests, [fixture.service.conversation.peerName]);
        expect(fixture.service.fileRequests, isEmpty);
        _expectNoFiles(tester, fixture);
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const ValueKey('storage-selection-mode')),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<PopupMenuButton<StorageFileCategory?>>(
                find.byType(PopupMenuButton<StorageFileCategory?>),
              )
              .enabled,
          isFalse,
        );

        fixture.auth.allowed = true;
        fixture.auth.error = null;
        await tester.tap(find.text(_strings(tester).chat_lock_unlock_action));
        await tester.pumpAndSettle();
        expect(fixture.auth.requests, hasLength(2));
        expect(fixture.service.fileRequests, [_chatId]);
        expect(_file('photo'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'password-protected chat never falls back to device authentication',
    (tester) async {
      fixture.service.conversation = fixture.service.conversation.copyWith(
        isLocked: true,
      );
      fixture.credentials.present = true;
      await _pumpScreen(tester, fixture);
      // The detail screen stays busy underneath the password dialog.
      await tester.tap(_chat);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      final strings = _strings(tester);
      expect(
        find.byKey(const ValueKey('chat-unlock-password')),
        findsOneWidget,
      );
      expect(fixture.auth.requests, isEmpty);
      expect(fixture.service.fileRequests, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('chat-unlock-password')),
        'incorrect-password',
      );
      await tester.tap(find.byKey(const ValueKey('chat-unlock-submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(strings.chat_lock_wrong_password), findsOneWidget);
      expect(fixture.service.fileRequests, isEmpty);
      await tester.tap(find.text(strings.cancel));
      await tester.pumpAndSettle();
      _expectNoFiles(tester, fixture);
      expect(fixture.auth.requests, isEmpty);
    },
  );

  testWidgets('view-once filenames are absent from text and semantics', (
    tester,
  ) async {
    await _pumpScreen(tester, fixture);
    await _openDetail(tester);
    await _showFile(tester, 'view-once');
    final strings = _strings(tester);
    expect(find.text(strings.view_once_protected), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    expect(find.textContaining(_privateName), findsNothing);
    expect(find.bySemanticsLabel(RegExp(_privateName)), findsNothing);
    expect(
      find.descendant(of: _file('view-once'), matching: find.byType(Image)),
      findsNothing,
    );
    expect(
      find.descendant(
        of: _file('view-once'),
        matching: find.byType(LocalVideoThumbnail),
      ),
      findsNothing,
    );
    expect(
      nativeCalls.where(
        (call) => (call.arguments as Map?)?['path'] == '/managed/$_privateName',
      ),
      isEmpty,
    );
    await tester.tap(_file('view-once'));
    await tester.pumpAndSettle();
    await tester.tap(_deleteSelected);
    await tester.pumpAndSettle();
    expect(find.text(strings.storage_delete_selected(1)), findsOneWidget);
    expect(find.textContaining(_privateName), findsNothing);
    expect(find.bySemanticsLabel(RegExp(_privateName)), findsNothing);
    await tester.tap(find.text(strings.cancel));
    await tester.pumpAndSettle();
    expect(fixture.service.cleanRequests, isEmpty);
  });

  for (final state in [AppLifecycleState.hidden, AppLifecycleState.paused]) {
    testWidgets('$state clears access and selection until reauthorized', (
      tester,
    ) async {
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      fixture.service.conversation = fixture.service.conversation.copyWith(
        isLocked: true,
      );
      await _pumpScreen(tester, fixture);
      await _openDetail(tester);
      await tester.tap(_file('photo'));
      await tester.pumpAndSettle();
      expect(_deleteSelected, findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      _expectNoFiles(tester, fixture);
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
      _expectNoFiles(tester, fixture);

      fixture.auth.allowed = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(fixture.auth.requests, hasLength(2));
      expect(fixture.service.fileRequests, [_chatId]);
      _expectNoFiles(tester, fixture);
      fixture.auth.allowed = true;
      await tester.tap(find.text(_strings(tester).chat_lock_unlock_action));
      await tester.pumpAndSettle();
      expect(fixture.auth.requests, hasLength(3));
      expect(_selected(tester, 'photo'), isFalse);
      expect(_deleteSelected, findsNothing);
    });
  }

  testWidgets('an unlock completed after pause cannot expose files', (
    tester,
  ) async {
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    fixture.service.conversation = fixture.service.conversation.copyWith(
      isLocked: true,
    );
    final pending = Completer<bool>();
    fixture.auth.pending = pending;
    await _pumpScreen(tester, fixture);
    await tester.tap(_chat);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(fixture.auth.requests, hasLength(1));
    expect(fixture.service.fileRequests, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    pending.complete(true);
    await tester.pump();
    _expectNoFiles(tester, fixture);
    expect(fixture.service.fileRequests, isEmpty);

    fixture.auth.pending = null;
    fixture.auth.allowed = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(fixture.auth.requests, hasLength(2));
    expect(fixture.service.fileRequests, isEmpty);
    _expectNoFiles(tester, fixture);
  });

  testWidgets('pausing invalidates an outstanding delete confirmation', (
    tester,
  ) async {
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    fixture.service.conversation = fixture.service.conversation.copyWith(
      isLocked: true,
    );
    await _pumpScreen(tester, fixture);
    await _openDetail(tester);
    await tester.tap(_file('photo'));
    await tester.pumpAndSettle();
    await tester.tap(_deleteSelected);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    // A new successful authorization must not revive the old confirmation.
    fixture.auth.allowed = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    if (find.byType(AlertDialog).evaluate().isNotEmpty) {
      await tester.tap(
        find.widgetWithText(FilledButton, _strings(tester).cd_clear),
      );
      await tester.pumpAndSettle();
    }
    expect(fixture.service.cleanRequests, isEmpty);
    expect(fixture.service.files, hasLength(5));
  });

  for (final (language, textScale) in [
    for (final language in ['en', 'tr', 'de', 'ar'])
      for (final scale in [1.0, 2.0]) (language, scale),
  ]) {
    testWidgets(
      'storage workflow fits 320px at ${textScale}x text in $language',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 568);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        fixture.service.conversation = fixture.service.conversation.copyWith(
          peerName: 'Storage Conversation With A Long Display Name',
        );
        await _pumpScreen(
          tester,
          fixture,
          locale: Locale(language),
          textScale: textScale,
        );
        expect(tester.takeException(), isNull);
        await _openDetail(tester);
        expect(tester.takeException(), isNull);
        await _captureScreen(tester, 'storage-$language-${textScale}x');
        final strings = _strings(tester);
        await _filter(tester, strings.documents);
        expect(tester.takeException(), isNull);
        await _showFile(tester, 'document');
        await tester.tap(_file('document'));
        await tester.pumpAndSettle();
        expect(_deleteSelected.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(_deleteSelected);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
        final cancel = find.widgetWithText(TextButton, strings.cancel);
        expect(cancel.hitTestable(), findsOneWidget);
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byType(StorageUsageScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Finder get _chat => find.byKey(const ValueKey('storage-chat-$_chatId'));
Finder get _deleteSelected =>
    find.byKey(const ValueKey('storage-delete-selected'));
Finder _file(String id) => find.byKey(ValueKey('storage-file-$id'));
Finder _preview(String id) => find.byKey(ValueKey('storage-preview-$id'));
bool _selected(WidgetTester tester, String id) =>
    tester.widget<Semantics>(_file(id)).properties.checked ?? false;

Future<void> _showFile(WidgetTester tester, String id) async {
  if (_file(id).evaluate().isEmpty) {
    final scrollable = find.descendant(
      of: find.byType(GridView),
      matching: find.byType(Scrollable),
    );
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(
      _file(id),
      150,
      scrollable: find.descendant(
        of: find.byType(GridView),
        matching: find.byType(Scrollable),
      ),
    );
  }
  await tester.ensureVisible(_file(id));
  await tester.pumpAndSettle();
}

AppLocalizations _strings(WidgetTester tester) => AppLocalizations.of(
  tester.element(find.byType(StorageUsageScreen, skipOffstage: false)),
);

String _summary(WidgetTester tester, _Fixture fixture) {
  final summary = fixture.service.summary;
  return _strings(tester).storage_summary(
    summary.messageCount,
    summary.fileCount,
    formatStorageBytes(summary.totalBytes),
  );
}

void _expectNoFiles(WidgetTester tester, _Fixture fixture) {
  expect(find.byType(Checkbox), findsNothing);
  expect(_deleteSelected, findsNothing);
  for (final file in fixture.service.files) {
    expect(find.text(file.message.fileName!), findsNothing);
  }
}

Future<void> _openDetail(WidgetTester tester, {bool selecting = true}) async {
  await tester.ensureVisible(_chat);
  await tester.pumpAndSettle();
  await tester.tap(_chat);
  await tester.pumpAndSettle();
  expect(find.byType(Checkbox), findsNothing);
  final mode = find.byKey(const ValueKey('storage-selection-mode'));
  if (selecting && tester.widget<IconButton>(mode).onPressed != null) {
    await tester.tap(mode);
    await tester.pumpAndSettle();
  }
}

Future<void> _filter(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip(_strings(tester).storage_filter));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _Fixture fixture, {
  Locale locale = const Locale('en'),
  double textScale = 1,
  bool dark = false,
}) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: AppContainerScope(
        container: fixture.container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: dark ? SecureChatTheme.dark() : SecureChatTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: const StorageUsageScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<Uint8List> _previewPng(WidgetTester tester) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(const Color(0xff19c66a), BlendMode.src);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(768, 512);
  final data = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  ))!;
  image.dispose();
  picture.dispose();
  return data.buffer.asUint8List();
}

Future<File> _mediaFile(
  WidgetTester tester,
  String name,
  List<int> bytes,
) async {
  final directory = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('storage-grid-'),
  ))!;
  addTearDown(() => directory.delete(recursive: true));
  return (await tester.runAsync(
    () => File('${directory.path}/$name').writeAsBytes(bytes),
  ))!;
}

Future<void> _settleDecode(WidgetTester tester) async {
  for (var attempt = 0; attempt < 15; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}

Future<void> _expectPreviewPixels(WidgetTester tester, String id) async {
  final raw = tester.widget<RawImage>(
    find.descendant(of: _preview(id), matching: find.byType(RawImage)),
  );
  expect(raw.image, isNotNull);
  final image = raw.image!;
  final data = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  final offset = ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
  expect(data.buffer.asUint8List().sublist(offset, offset + 4), [
    25,
    198,
    106,
    255,
  ]);
}

Future<void> _captureScreen(WidgetTester tester, String name) async {
  final output = Platform.environment['STORAGE_SCREENSHOTS'];
  if (output == null || output.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  final data = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  ))!;
  image.dispose();
  await tester.runAsync(() async {
    await Directory(output).create(recursive: true);
    await File('$output/$name.png').writeAsBytes(data.buffer.asUint8List());
  });
}

class _Fixture {
  _Fixture() {
    final defaults = createWidgetTestContainer();
    container = AppContainer.testing(
      session: defaults.session,
      conversations: defaults.conversations,
      crypto: defaults.crypto,
      signaling: defaults.signaling,
      chatAccessRuntime: AppChatAccessRuntime(
        service: ChatAccessService(authenticator: auth),
        credentials: credentials,
      ),
      callReadinessRuntime: defaults.callReadinessRuntime,
      storageRuntime: AppStorageRuntime(service: service),
    );
  }

  final service = _StorageService();
  final auth = _Authenticator();
  final credentials = _Credentials();
  late final AppContainer container;
}

class _StorageService extends Fake implements StorageManagementService {
  ConversationEntity conversation = const ConversationEntity(
    id: _chatId,
    peerId: 'peer',
    peerName: 'Storage Chat',
    peerPhone: '',
  );
  final files = [
    _storageFile('photo', 'photo.png', 'image/png', 4096),
    _storageFile('video', 'video.mp4', 'video/mp4', 3072),
    _storageFile('audio', 'audio.ogg', 'audio/ogg', 2048),
    _storageFile(
      'document',
      'quarterly-planning-document-with-a-long-name.pdf',
      'application/pdf',
      1024,
    ),
    _storageFile('view-once', _privateName, 'image/png', 512, viewOnce: true),
  ];
  final fileRequests = <String>[];
  final watchRequests = <String>[];
  final messageUpdates = StreamController<List<LocalMessage>>.broadcast();
  final cleanRequests = <(String, Set<String>)>[];
  final openRequests = <String>[];
  Completer<ChatStorageFile?>? pendingOpen;
  int analyzeCalls = 0;

  ChatStorageBreakdown get summary {
    final bytes = files.fold(0, (total, file) => total + file.diskBytes);
    return ChatStorageBreakdown(
      conversationId: conversation.id,
      displayName: conversation.peerName,
      isGroup: conversation.isGroup,
      messageCount: files.length + 1,
      fileCount: files.length,
      fileBytes: bytes,
      totalBytes: bytes + StorageManagementService.textOverheadPerMessage,
    );
  }

  @override
  Future<List<ChatStorageBreakdown>> analyzeAll() async {
    analyzeCalls++;
    return [summary];
  }

  @override
  Future<ConversationEntity?> getConversation(String id) async =>
      id == conversation.id ? conversation : null;

  @override
  Future<String?> resolveMediaPath(
    String storedPath, {
    bool strict = false,
  }) async => storedPath;

  @override
  Stream<List<LocalMessage>> watchChatMessages(String conversationId) {
    watchRequests.add(conversationId);
    return messageUpdates.stream;
  }

  @override
  Future<List<ChatStorageFile>> filesForChat(String conversationId) async {
    fileRequests.add(conversationId);
    return List.of(files);
  }

  @override
  Future<ChatStorageFile?> fileForOpening(
    String conversationId,
    String id,
  ) async {
    openRequests.add(id);
    if (pendingOpen != null) return pendingOpen!.future;
    return files
        .where((file) => file.message.id == id && file.canOpen)
        .firstOrNull;
  }

  @override
  Future<StorageCleanupResult> cleanSelectedFiles(
    String conversationId,
    Iterable<String> messageIds,
  ) async {
    final ids = messageIds.toSet();
    cleanRequests.add((conversationId, ids));
    final removed = files
        .where((file) => ids.contains(file.message.id))
        .toList();
    files.removeWhere((file) => ids.contains(file.message.id));
    return StorageCleanupResult(
      deletedCount: removed.length,
      freedBytes: removed.fold(0, (total, file) => total + file.diskBytes),
      failedIds: const [],
    );
  }
}

class _Authenticator implements DeviceOwnerAuthenticator {
  bool allowed = true;
  Object? error;
  Completer<bool>? pending;
  final requests = <String>[];

  @override
  Future<bool> authenticate(String title) async {
    requests.add(title);
    if (error != null) throw error!;
    return pending == null ? allowed : await pending!.future;
  }
}

class _Credentials extends Fake implements ChatLockCredentialService {
  bool present = false;

  @override
  Future<bool> hasCredential(String conversationId) async => present;

  @override
  Future<bool> verifyPassword(String conversationId, String password) async =>
      false;
}

ChatStorageFile _storageFile(
  String id,
  String name,
  String mime,
  int bytes, {
  bool viewOnce = false,
  bool deferred = false,
  bool available = true,
  String? path,
  DateTime? expiresAt,
  bool deleted = false,
}) => ChatStorageFile(
  message: LocalMessage(
    id: id,
    conversationId: _chatId,
    senderId: 'peer',
    peerId: 'me',
    content: LocalMessage.buildFileContent(
      fileName: name,
      mimeType: mime,
      fileSize: bytes,
      filePath: path ?? '/managed/$name',
    ),
    contentType: deleted ? MessageContentType.deleted : MessageContentType.file,
    timestamp: DateTime(2026, 9, 22),
    status: MessageStatus.delivered,
    isOutgoing: false,
    isViewOnce: viewOnce,
    isMediaPreviewDeferred: deferred,
    expiresAt: expiresAt,
  ),
  diskBytes: bytes,
  available: available,
);
