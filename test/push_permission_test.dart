import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:maxplayer/services/push_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'waits for media permission, asks once, and respects OS denial',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      var requests = 0;
      const channel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'areNotificationsEnabled') return false;
            if (call.method == 'requestNotificationsPermission') {
              requests++;
              return false;
            }
            if (call.method == 'initialize') return true;
            return null;
          });
      try {
        final service = PushService.instance;
        await service.requestOnForeground();
        expect(
          requests,
          0,
          reason: 'Do not compete with the initial media permission popup',
        );
        service.mediaPermissionSettled();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(requests, 1);
        await service.requestOnForeground();
        expect(
          requests,
          1,
          reason: 'Do not loop while the same foreground session is active',
        );
        service.backgrounded();
        await service.requestOnForeground();
        expect(
          requests,
          1,
          reason: 'Short cooldown prevents a permission-dialog lifecycle loop',
        );
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
  test(
    'old disabled app preference cannot silently block a tray notification',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      SharedPreferences.setMockInitialValues({'push.enabled': false});
      final calls = <MethodCall>[];
      const channel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'areNotificationsEnabled') return true;
            return null;
          });
      try {
        await PushService.instance.show(
          const RemoteMessage(
            messageId: 'test',
            data: {
              'noticeId': 'notice_test',
              'title': 'Test title',
              'message': 'Test body',
            },
          ),
        );
        expect(calls.where((call) => call.method == 'show').length, 1);
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
