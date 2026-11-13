import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:maxplayer/services/remote_theme.dart';
import 'package:maxplayer/services/notification_destination.dart';
import 'package:maxplayer/services/push_service.dart';
import 'package:maxplayer/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Map<String, dynamic> config() => {
    'schemaVersion': 1,
    'name': 'Christmas',
    'palette': {'background': '#081810', 'accent': '#FFE090'},
    'decoration': 'christmas',
    'headerLabel': 'Happy holidays',
  };
  test(
    'theme schema merges supported defaults and rejects executable properties',
    () {
      final theme = validateTheme(config());
      expect(theme['palette']['accent'], '#FFE090');
      expect(theme['palette']['surface'], '#101013');
      expect(
        () => validateTheme({...config(), 'script': 'alert(1)'}),
        throwsFormatException,
      );
      expect(
        () => validateTheme({
          ...config(),
          'palette': {'accent': 'javascript:run'},
        }),
        throwsFormatException,
      );
    },
  );
  test('rejects unknown decorations and unreadable background', () {
    expect(
      () => validateTheme({...config(), 'decoration': 'download-code'}),
      throwsFormatException,
    );
    expect(
      () => validateTheme({
        ...config(),
        'palette': {'background': '#FFFFFF', 'textPrimary': '#FFFFFF'},
      }),
      throwsFormatException,
    );
  });
  test('shared app tokens change and default restores', () {
    RemoteTheme.instance.current = validateTheme(config());
    expect(AppColors.background.toARGB32(), 0xff081810);
    RemoteTheme.instance.current = null;
    expect(AppColors.background.toARGB32(), 0xff060608);
  });
  test(
    'cached theme is valid offline; malformed cache restores default',
    () async {
      SharedPreferences.setMockInitialValues({
        'remote.theme.v1': jsonEncode(config()),
      });
      await RemoteTheme.instance.loadCache();
      expect(RemoteTheme.instance.active, true);
      SharedPreferences.setMockInitialValues({'remote.theme.v1': 'bad json'});
      await RemoteTheme.instance.loadCache();
      expect(RemoteTheme.instance.active, false);
    },
  );
  test('supported screen destinations are allowlisted', () {
    for (final screen in notificationScreens) {
      expect(notificationDestination({'screen': screen}), screen);
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
