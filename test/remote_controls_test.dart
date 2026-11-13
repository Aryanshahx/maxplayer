import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maxplayer/services/notification_destination.dart';
import 'package:maxplayer/services/push_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('supported screen destinations are allowlisted', () {
    for (final screen in notificationScreens) {
      expect(
        notificationDestination({
          'screen': screen,
          if (screen == 'movie') ...{
            'movieId': '550',
            'movieKind': 'movie',
            'movieTitle': 'Fixture',
          },
        }),
        screen,
      );
    }
    expect(notificationDestination({'screen': 'execute:bad'}), 'home');
    expect(notificationDestination({'screen': 7}), 'home');
  });
  test(
    'legacy HTTPS links still route externally; unsafe links are rejected',
    () {
      expect(
        notificationDestination({'link': 'https://example.test'}),
        'external',
      );
      expect(
        notificationExternalLink({'link': 'https://example.test'})?.host,
        'example.test',
      );
      for (final link in [
        'http://example.test',
        'javascript:run',
        'https://u:p@example.test',
      ]) {
        expect(notificationExternalLink({'link': link}), isNull);
      }
    },
  );
  test(
    'local notification cold-start tap is read without Firebase login',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      const channel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'initialize') return true;
            if (call.method == 'getNotificationAppLaunchDetails') {
              return {
                'notificationLaunchedApp': true,
                'notificationResponse': {
                  'notificationResponseType': 0,
                  'payload': jsonEncode({
                    'noticeId': 'test',
                    'screen': 'audio',
                  }),
                },
              };
            }
            return null;
          });
      try {
        Map<String, dynamic>? tap;
        PushService.instance.onTap = (data) => tap = data;
        await PushService.instance.readLaunchTap();
        expect(calls, contains('getNotificationAppLaunchDetails'));
        expect(tap?['screen'], 'audio');
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
