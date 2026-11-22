// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:maxplayer/utils/app_language.dart';
import 'package:maxplayer/utils/pashto_localizations.dart';
import 'package:maxplayer/utils/privacy_policy.dart';
import 'package:maxplayer/services/review_prompt.dart';

void main() {
  test(
    'Review eligibility requires age, playback and sessions; has cooldown and cap',
    () {
      final now = DateTime(2026, 9, 5);
      bool allowed({
        int age = 3,
        int sessions = 3,
        int seconds = 1200,
        int attempts = 0,
        DateTime? last,
      }) => ReviewEligibility.allows(
        now: now,
        firstUse: now.subtract(Duration(days: age)),
        sessions: sessions,
        seconds: seconds,
        attempts: attempts,
        lastAttempt: last,
      );
      expect(allowed(), isTrue);
      expect(allowed(age: 2), isFalse);
      expect(allowed(sessions: 2), isFalse);
      expect(allowed(seconds: 1199), isFalse);
      expect(allowed(attempts: 3), isFalse);
      expect(allowed(last: now.subtract(const Duration(days: 119))), isFalse);
      expect(
        allowed(attempts: 1, last: now.subtract(const Duration(days: 120))),
        isTrue,
      );
      expect(allowed(last: now.add(const Duration(days: 1))), isFalse);
    },
  );
  test(
    'No advertising SDK or ad service remains; manifest blocks ad identifier merging',
    () {
      expect(File('lib/services/ad_service.dart').existsSync(), isFalse);
      expect(
        File('pubspec.yaml').readAsStringSync(),
        isNot(contains('google_mobile_ads')),
      );
      expect(
        File('pubspec.lock').readAsStringSync(),
        isNot(contains('google_mobile_ads')),
      );
      for (final file
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        expect(
          file.readAsStringSync(),
          isNot(contains('AdService')),
          reason: file.path,
        );
        expect(
          file.readAsStringSync(),
          isNot(contains('CineBannerSlot')),
          reason: file.path,
        );
      }
      final xml = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(xml, contains('AD_ID" tools:node="remove"'));
      expect(xml, isNot(contains('com.google.android.gms.ads.APPLICATION_ID')));
      expect(
        xml,
        contains(
          'google_analytics_adid_collection_enabled" android:value="false"',
        ),
      );
    },
  );
  test(
    'Bundled and published privacy text match without internal release/admin detail',
    () {
      final markdown = File('PRIVACY_POLICY.md').readAsStringSync();
      final plain = markdown
          .replaceAll(RegExp(r'^#+\s*', multiLine: true), '')
          .replaceAll('**', '');
      expect(kPrivacyPolicyText, plain);
      for (final text in [markdown, kPrivacyPolicyText]) {
        expect(text.toLowerCase(), isNot(contains('admin')));
        expect(text, isNot(matches(RegExp(r'\+(69|70|74|76)'))));
        expect(text, contains('country.is'));
        expect(text, contains('Firebase'));
        expect(text, contains('techlabs.hyper@gmail.com'));
      }
    },
  );
  test(
    'New catalogs cover all existing keys and have native language labels',
    () {
      final base =
          jsonDecode(File('assets/i18n/en.json').readAsStringSync()) as Map;
      for (final code in ['ps', 'uz']) {
        final data =
            jsonDecode(File('assets/i18n/$code.json').readAsStringSync())
                as Map;
        expect(data.keys.toSet(), base.keys.toSet());
        expect(
          data.values.every((v) => v is String && v.trim().isNotEmpty),
          isTrue,
        );
      }
      expect(AppLanguage.supports('ps'), isTrue);
      expect(AppLanguage.supports('uz'), isTrue);
    },
  );
  testWidgets('Pashto app strings render RTL with safe framework fallback', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.instance.setLanguage('ps');
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ps'),
        supportedLocales: const [Locale('ps')],
        localizationsDelegates: const [
          PashtoMaterialFallback(),
          PashtoCupertinoFallback(),
          PashtoWidgetsLocalizationDelegate(),
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: const Scaffold(body: LText('Language')),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      Directionality.of(tester.element(find.byType(LText))),
      TextDirection.rtl,
    );
    expect(find.text('ژبه'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await AppLanguage.instance.setLanguage('en');
  });
}
