import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_securechat/src/l10n/service_strings.dart';
import 'package:flutter_securechat/src/notifications/message_notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'invalid custom sound retries the notification without that sound',
    () async {
      final plugin = _InvalidSoundOncePlugin();
      final presenter = PluginLocalNotificationPresenter(
        strings: ServiceStrings.fixed('tr'),
        showNotification: plugin.show,
      );
      addTearDown(presenter.dispose);

      await presenter.show(
        const LocalMessageNotification(
          id: 42,
          title: 'Ayse',
          body: 'Mesaj',
          payload: 'peer-ayse',
          conversationId: 'peer-ayse',
          count: 1,
          silent: false,
          hideOnLockScreen: false,
          sound: 'missing_sound',
        ),
      );

      expect(plugin.details, hasLength(2));
      expect(plugin.details.first.android?.sound?.sound, 'missing_sound');
      expect(plugin.details.last.android?.sound, isNull);
      expect(
        plugin.details.last.android?.channelId,
        endsWith('_sound_fallback_v1'),
      );
      expect(plugin.details.last.iOS?.sound, isNull);
    },
  );

  test('unrelated platform failures remain visible to diagnostics', () async {
    final plugin = _InvalidSoundOncePlugin(errorCode: 'permission_denied');
    final presenter = PluginLocalNotificationPresenter(
      strings: ServiceStrings.fixed('tr'),
      showNotification: plugin.show,
    );
    addTearDown(presenter.dispose);

    await expectLater(
      presenter.show(
        const LocalMessageNotification(
          id: 43,
          title: 'Ayse',
          body: 'Mesaj',
          payload: 'peer-ayse',
          conversationId: 'peer-ayse',
          count: 1,
          silent: false,
          hideOnLockScreen: false,
          sound: 'elcim_bell',
        ),
      ),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'permission_denied',
        ),
      ),
    );
    expect(plugin.details, hasLength(1));
  });
}

class _InvalidSoundOncePlugin {
  _InvalidSoundOncePlugin({this.errorCode = 'invalid_sound'});

  final String errorCode;
  final details = <NotificationDetails>[];

  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async {
    details.add(notificationDetails!);
    if (details.length == 1) throw PlatformException(code: errorCode);
  }
}
