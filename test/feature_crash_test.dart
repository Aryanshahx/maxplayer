import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maxplayer/services/app_analytics.dart';
import 'package:maxplayer/utils/crash_log.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('eight distinct feature keys are supported', () {
    expect(AppAnalytics.featureKeys, [
      'discover',
      'private',
      'folders',
      'playlists',
      'audio',
      'network',
      'cloud',
      'quickShare',
    ]);
    expect(AppAnalytics.featureKeys.toSet().length, 8);
  });
  test(
    'captured app error persists stack and is not replaced by playback logging',
    () async {
      final dir = await Directory.systemTemp.createTemp('maxplayer_crash_test');
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => dir.path);
      try {
        await CrashLog.init();
        CrashLog.captureCrash(
          'dart.error',
          StateError('test uncaught failure'),
          StackTrace.fromString('test_stack_frame'),
          fatal: true,
        );
        final text = await CrashLog.peekCrashReport();
        expect(text, isNotNull);
        final report = jsonDecode(text!);
        expect(report['stack'], 'test_stack_frame');
        expect(report['fatal'], true);
        expect(report['id'], matches(RegExp(r'^[a-f0-9]{32}$')));
        CrashLog.error('player.open_failed', 'format test');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(await CrashLog.peekCrashReport(), text);
        await CrashLog.clearCrashReport('different report');
        expect(await CrashLog.peekCrashReport(), text);
        await CrashLog.clearCrashReport(text);
        expect(await CrashLog.peekCrashReport(), isNull);
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await dir.delete(recursive: true);
      }
    },
  );
}
