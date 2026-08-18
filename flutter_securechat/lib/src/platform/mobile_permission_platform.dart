import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../contacts/contact_service.dart';
import '../onboarding/permission_service.dart';

class MobileAppPermissionPlatform implements AppPermissionPlatform {
  const MobileAppPermissionPlatform({
    required ContactService contacts,
    required Future<bool> Function()? requestNotifications,
  }) : _contacts = contacts,
       _requestNotifications = requestNotifications;

  final ContactService _contacts;
  final Future<bool> Function()? _requestNotifications;

  @override
  Future<bool> request(AppPermission permission) => switch (permission) {
    AppPermission.notifications =>
      _requestNotifications?.call() ?? Future<bool>.value(false),
    AppPermission.contacts => _contacts.requestContactsPermission(),
    AppPermission.microphone => _requestMedia(audio: true, video: false),
    AppPermission.camera => _requestMedia(audio: false, video: true),
  };

  Future<bool> _requestMedia({required bool audio, required bool video}) async {
    MediaStream? stream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({
        'audio': audio,
        'video': video,
      });
      return true;
    } finally {
      if (stream != null) {
        for (final track in stream.getTracks()) {
          track.stop();
        }
        await stream.dispose();
      }
    }
  }
}
