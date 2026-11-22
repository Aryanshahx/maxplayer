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
      'enabled player overlay is opaque white in $brightness for every accent',
      () {
        AppColors.brightness = brightness;
        for (final accent in [
          Colors.white,
          Colors.black,
          Colors.red,
          Colors.blue,
        ]) {
          AppColors.accent = accent;
          expect(AppColors.playerForeground, Colors.white);
          expect(AppColors.playerForeground.a, 1);
          expect(AppColors.playerMuted, Colors.white);
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
