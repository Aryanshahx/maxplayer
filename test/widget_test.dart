import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maxplayer/theme.dart';
import 'package:maxplayer/utils/format.dart';
import 'package:maxplayer/utils/resume.dart';

void main() {
  group('formatDuration', () {
    test('zero', () => expect(formatDuration(Duration.zero), '0:00'));
    test('seconds', () {
      expect(formatDuration(const Duration(seconds: 7)), '0:07');
    });
    test('minutes', () {
      expect(formatDuration(const Duration(minutes: 1, seconds: 5)), '1:05');
    });
    test('hours', () {
      expect(formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
          '1:02:03');
    });
    test('negative clamps to zero', () {
      expect(formatDuration(const Duration(seconds: -5)), '0:00');
    });
  });

  group('formatBytes', () {
    test('bytes', () => expect(formatBytes(512), '512B'));
    test('kilobytes', () => expect(formatBytes(1536), '1.5 KB'));
    test('megabytes', () => expect(formatBytes(734003200), '700.0 MB'));
    test('negative clamps', () => expect(formatBytes(-1), '0B'));
  });

  group('resumeTargetMs (v0.3 resume)', () {
    test('under 10s saved -> no prompt', () {
      expect(resumeTargetMs(5000, 600000), isNull);
    });
    test('boundary: exactly 10s saved -> prompt', () {
      expect(resumeTargetMs(minPromptMs, 600000), minPromptMs);
    });
    test('mid-video -> prompt at saved spot', () {
      expect(resumeTargetMs(754000, 3600000), 754000);
    });
    test('inside end margin -> treated as finished, no prompt', () {
      expect(resumeTargetMs(3600000 - endMarginMs + 1, 3600000), isNull);
    });
    test('just outside end margin -> prompt', () {
      expect(resumeTargetMs(3600000 - endMarginMs, 3600000),
          3600000 - endMarginMs);
    });
    test('unknown duration (0) -> prompt for big save', () {
      expect(resumeTargetMs(60000, 0), 60000);
    });
  });

  group('isFinishedMs (v0.3 resume)', () {
    test('near end -> finished', () {
      expect(isFinishedMs(3595000, 3600000), isTrue);
    });
    test('mid -> not finished', () {
      expect(isFinishedMs(1800000, 3600000), isFalse);
    });
    test('unknown duration -> not finished', () {
      expect(isFinishedMs(999999, 0), isFalse);
    });
  });

  testWidgets('theme applies dark design language', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const Scaffold(body: Text('ok')),
    ));
    expect(find.text('ok'), findsOneWidget);
    final theme = Theme.of(tester.element(find.text('ok')));
    expect(theme.scaffoldBackgroundColor, AppColors.background);
    expect(theme.brightness, Brightness.dark);
  });
}
