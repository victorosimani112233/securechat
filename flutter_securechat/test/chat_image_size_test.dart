import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/features/chat/chat_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/media/media_attachment.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/services/conversation_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'support/test_app_container.dart';

/// Fotograflar gonderilmeden once kucultulur; balonda da tam
/// cozunurlukte cozulmez.
void main() {
  test('gallery and camera photos are scaled and compressed', () async {
    final picker = _RecordingPicker();
    final selection = PluginMediaSelectionService(imagePicker: picker);

    await selection.pickGallery();
    await selection.takePhoto();

    expect(picker.calls, hasLength(2));
    for (final call in picker.calls) {
      expect(call.maxWidth, PluginMediaSelectionService.sentPhotoMaxDimension);
      expect(call.maxHeight, PluginMediaSelectionService.sentPhotoMaxDimension);
      expect(call.imageQuality, PluginMediaSelectionService.sentPhotoQuality);
    }
  });

  testWidgets('an image bubble decodes at bubble size, not full size', (
    tester,
  ) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('chat-image-size-'),
    ))!;
    addTearDown(() => root.delete(recursive: true));
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.green, BlendMode.src);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(4, 4);
    final data = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    ))!;
    image.dispose();
    picture.dispose();
    final photo = File('${root.path}/photo.png')
      ..writeAsBytesSync(data.buffer.asUint8List());

    final base = createWidgetTestContainer();
    final repo = InMemoryConversationRepository(
      conversations: [
        const Conversation(
          id: 'peer-ayse',
          peerId: 'peer-ayse',
          peerName: 'Ayse Demir',
          peerPhone: '',
        ),
      ],
      messages: {
        'peer-ayse': [
          LocalMessage(
            id: 'photo',
            conversationId: 'peer-ayse',
            senderId: 'peer-ayse',
            peerId: 'peer-ayse',
            content: 'photo.png|image/png|68|${photo.path}',
            contentType: MessageContentType.image,
            timestamp: DateTime.now(),
            status: MessageStatus.delivered,
            isOutgoing: false,
          ),
        ],
      },
    );
    await tester.pumpWidget(
      AppContainerScope(
        container: AppContainer.testing(
          session: base.session,
          conversations: repo,
          crypto: base.crypto,
          signaling: base.signaling,
          chatAccessRuntime: base.chatAccessRuntime,
          callReadinessRuntime: base.callReadinessRuntime,
        ),
        child: const MaterialApp(
          locale: Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChatScreen(),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    final images = tester
        .widgetList<Image>(find.byType(Image))
        .where((widget) => widget.image is ResizeImage)
        .toList();
    expect(images, hasLength(1));
    final resize = images.single.image as ResizeImage;
    final ratio = tester.view.devicePixelRatio;
    expect(resize.width, (360 * ratio).round());
    expect(resize.height, (360 * ratio).round());
    await tester.pumpWidget(const SizedBox());
  });
}

class _PickCall {
  const _PickCall(this.maxWidth, this.maxHeight, this.imageQuality);
  final double? maxWidth;
  final double? maxHeight;
  final int? imageQuality;
}

class _RecordingPicker extends ImagePicker {
  final calls = <_PickCall>[];

  @override
  Future<List<XFile>> pickMultiImage({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    int? limit,
    bool requestFullMetadata = true,
  }) async {
    calls.add(_PickCall(maxWidth, maxHeight, imageQuality));
    return const [];
  }

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    calls.add(_PickCall(maxWidth, maxHeight, imageQuality));
    return null;
  }
}
