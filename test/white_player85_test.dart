import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maxplayer/theme.dart';

void main() {
  tearDown(() {
    AppColors.brightness = Brightness.dark;
    AppColors.accent = Colors.white;
  });
  for (final brightness in Brightness.values) {
    test(
      'enabled player overlay is opaque and accent-driven in $brightness',
      () {
        AppColors.brightness = brightness;
        for (final accent in [
          Colors.white,
          Colors.black,
          Colors.red,
          Colors.blue,
        ]) {
          AppColors.accent = accent;
          // v1.0.1+88: theme colour reaches the video controls; the accent is
          // contrast-adapted per brightness, so it is always opaque.
          expect(AppColors.playerForeground, AppColors.accent);
          expect(AppColors.playerForeground.a, 1);
          expect(
            AppColors.playerMuted,
            brightness == Brightness.dark ? Colors.white70 : const Color(0xFF3C4149),
          );
        }
      },
    );
  }
  test('only video controls change, without covering backgrounds', () {
    final source = File(
      'lib/screens/player_screen_impl.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('AppColors.playerChrome')));
    expect(source, contains('activeTrackColor: AppColors.playerForeground'));
    expect(source, contains('thumbColor: AppColors.playerForeground'));
    expect(
      source,
      contains(
        'style: TextStyle(color: AppColors.playerForeground, fontSize: 11)',
      ),
    );
    expect(source, contains('final Color color = enabled'));
    expect(source, contains(': Colors.white38'));
    final top = source.substring(
      source.indexOf('class _TopBar extends'),
      source.indexOf('  PopupMenuItem'),
    );
    expect(top, isNot(contains('AppColors.accent')));
    expect(source, contains('color: AppColors.surface'));
  });
}
