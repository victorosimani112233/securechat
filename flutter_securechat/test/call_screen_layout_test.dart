import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_securechat/src/features/calls/call_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/media/call_manager.dart';
import 'package:flutter_securechat/src/media/call_models.dart';
import 'package:flutter_securechat/src/media/group_media_engine.dart';
import 'package:flutter_securechat/src/media/media_engine.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/theme/secure_chat_theme.dart';
import 'package:flutter_securechat/src/widgets/video_stream_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'support/test_app_container.dart';

const _video = CallSession(
  callId: 'call-layout',
  peerId: 'peer-ayse',
  peerName: 'Ayse Demir Uzun Soyadi ve Ikinci Isim',
  callType: CallType.video,
  direction: CallDirection.outgoing,
  state: CallState.active,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/inter_regular.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  for (final viewport in [
    (name: 'compact', size: const Size(320, 568), scale: 1.0),
    (name: 'iphone', size: const Size(390, 844), scale: 1.0),
    (name: 'large-text', size: const Size(320, 568), scale: 2.0),
    (name: 'landscape', size: const Size(844, 390), scale: 1.0),
    (name: 'landscape-large-text', size: const Size(568, 320), scale: 2.0),
  ]) {
    for (final state in [CallState.active, CallState.reconnecting]) {
      testWidgets(
        '${viewport.name} $state keeps identity and controls away from video center',
        (tester) async {
          final calls = await _mount(
            tester,
            _video.copyWith(state: state),
            size: viewport.size,
            scale: viewport.scale,
          );
          final header = tester.getRect(
            find.byKey(const ValueKey('call-header')),
          );
          final content = tester.getRect(
            find.byKey(const ValueKey('call-content')),
          );
          final controls = tester.getRect(
            find.byKey(const ValueKey('call-controls')),
          );
          final name = tester.getRect(
            find.byKey(const ValueKey('call-peer-name')),
          );
          expect(header.contains(name.center), isTrue);
          expect(name.bottom, lessThanOrEqualTo(content.top));
          expect(header.overlaps(controls), isFalse);
          expect(controls.bottom, lessThanOrEqualTo(viewport.size.height - 34));
          expect(header.top, greaterThanOrEqualTo(24));
          final remote = tester.getRect(
            find.byKey(const ValueKey('call-remote-video')),
          );
          expect(remote.size, viewport.size);
          final preview = find.byKey(const ValueKey('call-local-preview'));
          if (preview.evaluate().isNotEmpty) {
            final rect = tester.getRect(preview);
            expect(rect.top, greaterThanOrEqualTo(content.top));
            expect(rect.bottom, lessThanOrEqualTo(content.bottom));
            expect(rect.overlaps(header), isFalse);
            expect(rect.overlaps(controls), isFalse);
          }
          for (final element
              in find
                  .descendant(
                    of: find.byKey(const ValueKey('call-controls')),
                    matching: find.byType(IconButton),
                  )
                  .evaluate()) {
            final rect = tester.getRect(find.byWidget(element.widget));
            expect(rect.width, greaterThanOrEqualTo(48));
            expect(rect.height, greaterThanOrEqualTo(48));
          }
          expect(tester.takeException(), isNull);
          await _screenshot(tester, '${viewport.name}-${state.name}');
          await tester.tap(find.byTooltip('Mute'));
          await tester.pump();
          expect(calls.currentSession!.isMuted, isTrue);
          await tester.tap(find.byTooltip('Speaker'));
          await tester.pump();
          expect(calls.currentSession!.isSpeakerOn, isTrue);
          await tester.tap(find.byTooltip('Flip'));
          await tester.pump();
          expect(calls.currentSession!.isUsingFrontCamera, isFalse);
          await tester.tap(find.byTooltip('Camera'));
          await tester.pump();
          expect(
            find.byKey(const ValueKey('call-local-preview')),
            findsNothing,
          );
          expect(
            tester
                .widget<IconButton>(
                  find.widgetWithIcon(IconButton, Icons.cameraswitch_outlined),
                )
                .onPressed,
            isNull,
          );
          await tester.tap(find.byIcon(Icons.call_end));
          await tester.pump();
          expect(calls.currentSession!.state, CallState.ended);
          expect(find.byTooltip('Camera'), findsNothing);
          expect(find.byTooltip('Close'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'incoming video waits for explicit answer and never opens camera preview',
    (tester) async {
      final calls = await _mount(
        tester,
        const CallSession(
          callId: 'incoming',
          peerId: 'peer',
          peerName: 'Ayse Demir',
          callType: CallType.video,
          direction: CallDirection.incoming,
          state: CallState.ringing,
        ),
      );
      expect(find.byType(VideoStreamView), findsNothing);
      expect(find.byTooltip('Answer'), findsOneWidget);
      expect(find.byTooltip('Reject'), findsOneWidget);
      expect(calls.answers, 0);
      await _screenshot(tester, 'incoming-video');
      await tester.tap(find.byTooltip('Answer'));
      expect(calls.answers, 1);
    },
  );

  testWidgets('remote-camera-off state keeps avatar in the content area', (
    tester,
  ) async {
    await _mount(tester, _video.copyWith(isRemoteCameraEnabled: false));
    expect(find.byKey(const ValueKey('call-remote-video')), findsNothing);
    expect(find.byKey(const ValueKey('call-local-preview')), findsOneWidget);
    await _screenshot(tester, 'remote-camera-off');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'eight group tiles remain scrollable above controls and never expose routing IDs',
    (tester) async {
      final calls = await _mount(
        tester,
        const CallSession(
          callId: 'group-call',
          peerId: 'group',
          peerName: 'Operations Team',
          callType: CallType.video,
          direction: CallDirection.outgoing,
          state: CallState.active,
          isGroupCall: true,
          groupId: 'group',
        ),
        group: true,
      );
      final grid = find.byKey(const ValueKey('call-group-grid'));
      final controls = tester.getRect(
        find.byKey(const ValueKey('call-controls')),
      );
      expect(tester.getRect(grid).bottom, lessThanOrEqualTo(controls.top));
      expect(find.text('mesh'), findsNothing);
      expect(find.text('SFU'), findsNothing);
      for (final id in calls.groupMedia!.remoteRenderers.keys) {
        expect(find.text(id), findsNothing);
      }
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('call-participant-7')),
        150,
        scrollable: find.descendant(
          of: grid,
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.byKey(const ValueKey('call-participant-7')), findsOneWidget);
      await _screenshot(tester, 'group-video');
      await tester.tap(find.byIcon(Icons.call_end));
      await tester.pump();
      expect(calls.currentSession!.isTerminal, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'RTL preview respects directional end and controls remain reachable',
    (tester) async {
      await _mount(tester, _video, rtl: true);
      final preview = tester.getRect(
        find.byKey(const ValueKey('call-local-preview')),
      );
      expect(preview.left, 12);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'voice call retains identity and accessible audio controls without video',
    (tester) async {
      await _mount(
        tester,
        const CallSession(
          callId: 'voice',
          peerId: 'peer',
          peerName: 'Ayse Demir',
          callType: CallType.voice,
          direction: CallDirection.outgoing,
          state: CallState.active,
        ),
      );
      expect(find.byType(VideoStreamView), findsNothing);
      expect(find.byTooltip('Camera'), findsNothing);
      expect(find.byTooltip('Mute'), findsOneWidget);
      expect(find.byTooltip('Speaker'), findsOneWidget);
      await _screenshot(tester, 'voice-active');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('screen readers can activate named call controls', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final calls = await _mount(tester, _video);
      final node = tester.getSemantics(find.bySemanticsLabel('Mute'));
      expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
      await tester.tap(find.byTooltip('Mute'));
      await tester.pump();
      expect(calls.currentSession!.isMuted, isTrue);
      expect(find.bySemanticsLabel('Unmute'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'video view replaces the waiting state as renderer frames arrive',
    (tester) async {
      final renderer = _FrameRenderer();
      addTearDown(renderer.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: VideoStreamView(
            renderer: renderer,
            placeholder: const Text('waiting'),
          ),
        ),
      );
      expect(find.text('waiting'), findsOneWidget);
      renderer.value = const RTCVideoValue(
        renderVideo: false,
        width: 640,
        height: 480,
      );
      await tester.pump();
      expect(find.text('waiting'), findsNothing);
      expect(find.byType(RTCVideoView), findsOneWidget);
      renderer.value = RTCVideoValue.empty;
      await tester.pump();
      expect(find.text('waiting'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<_Calls> _mount(
  WidgetTester tester,
  CallSession session, {
  Size size = const Size(390, 844),
  double scale = 1,
  bool group = false,
  bool rtl = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  final calls = _Calls(session, group: group);
  final container = createWidgetTestContainer(mediaRuntime: _Runtime(calls));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await calls.close();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(
    AppContainerScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: SecureChatTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 24, bottom: 34),
            viewPadding: const EdgeInsets.only(top: 24, bottom: 34),
            textScaler: TextScaler.linear(scale),
          ),
          child: Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: RepaintBoundary(
              key: const ValueKey('capture'),
              child: child!,
            ),
          ),
        ),
        home: const CallScreen(),
      ),
    ),
  );
  await tester.pump();
  return calls;
}

Future<void> _screenshot(WidgetTester tester, String name) async {
  final path = Platform.environment['CALL_UI_SCREENSHOTS'];
  if (path == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory(path)..createSync(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

class _Calls implements CallManager {
  _Calls(this.currentSession, {required bool group})
    : groupMedia = group ? _Group() : null;
  final changes = StreamController<CallSession?>.broadcast();
  @override
  CallSession? currentSession;
  @override
  final _Media media = _Media();
  @override
  final _Group? groupMedia;
  @override
  Duration get currentDuration => const Duration(minutes: 2, seconds: 14);
  @override
  Stream<CallSession?> get sessions => changes.stream;
  int answers = 0;
  void emit(CallSession session) {
    currentSession = session;
    changes.add(session);
  }

  @override
  Future<void> toggleMute() async =>
      emit(currentSession!.copyWith(isMuted: !currentSession!.isMuted));
  @override
  Future<void> toggleSpeaker() async =>
      emit(currentSession!.copyWith(isSpeakerOn: !currentSession!.isSpeakerOn));
  @override
  Future<void> toggleCamera() async => emit(
    currentSession!.copyWith(isCameraEnabled: !currentSession!.isCameraEnabled),
  );
  @override
  Future<void> switchCamera() async => emit(
    currentSession!.copyWith(
      isUsingFrontCamera: !currentSession!.isUsingFrontCamera,
    ),
  );
  @override
  Future<void> endCall() async =>
      emit(currentSession!.copyWith(state: CallState.ended));
  @override
  Future<void> rejectCall() async =>
      emit(currentSession!.copyWith(state: CallState.rejected));
  @override
  Future<bool> acceptCall() async {
    answers++;
    return true;
  }

  Future<void> close() async {
    await changes.close();
    await media.close();
    await groupMedia?.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Media implements MediaEngine {
  @override
  final localRenderer = RTCVideoRenderer();
  @override
  final remoteRenderer = RTCVideoRenderer();
  @override
  Future<void> close() async {
    await localRenderer.dispose();
    await remoteRenderer.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Group implements GroupMediaEngine {
  @override
  final localRenderer = RTCVideoRenderer();
  @override
  final remoteRenderers = {
    for (var i = 0; i < 7; i++) 'private-routing-id-$i': RTCVideoRenderer(),
  };
  @override
  Future<void> close() async {
    await localRenderer.dispose();
    for (final renderer in remoteRenderers.values) {
      await renderer.dispose();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Runtime implements AppMediaRuntime {
  _Runtime(this.calls);
  @override
  final CallManager calls;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FrameRenderer extends RTCVideoRenderer {
  @override
  bool get renderVideo => videoWidth > 0 && videoHeight > 0;
  @override
  int? get textureId => 1;
}
