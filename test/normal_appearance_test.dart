import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:maxplayer/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('normal palette ignores retired remote-theme preferences', () async {
    SharedPreferences.setMockInitialValues({
      'remote.theme.v1': '{"palette":{"background":"#FF0000"}}',
      'theme.country.code': 'IN',
      'theme.country.at': 123,
    });
    await SharedPreferences.getInstance();
    expect(AppColors.background.toARGB32(), 0xFF060608);
    expect(AppColors.surface.toARGB32(), 0xFF101013);
    expect(AppColors.textPrimary.toARGB32(), 0xFFF5F6F8);
    expect(AppColors.danger.toARGB32(), 0xFFE5484D);
  });
  test('local accent remains supported with ordinary card shape', () {
    const accent = Color(0xFF55CCAA);
    final theme = buildAppTheme(accent: accent);
    expect(theme.colorScheme.primary, accent);
    expect(theme.scaffoldBackgroundColor, AppColors.background);
    expect(
      (theme.cardTheme.shape as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(16),
    );
  });
}
