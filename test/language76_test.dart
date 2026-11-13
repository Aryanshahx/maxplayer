// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// Pinned production toolchain uses the standard Flutter localization API.

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:maxplayer/utils/app_language.dart';
import 'package:maxplayer/screens/language_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.instance.setLanguage('en');
  });
  test(
    '40 distinct offline catalogs have identical, nonempty UI keys',
    () async {
      expect(uiLanguages.length, 40);
      expect(uiLanguages.map((l) => l.code).toSet().length, 40);
      final base =
          jsonDecode(await rootBundle.loadString('assets/i18n/en.json')) as Map;
      for (final l in uiLanguages) {
        final map =
            jsonDecode(
                  await rootBundle.loadString('assets/i18n/${l.code}.json'),
                )
                as Map;
        expect(map.keys.toSet(), base.keys.toSet(), reason: l.code);
        expect(
          map.values.every((v) => v is String && v.trim().isNotEmpty),
          true,
          reason: l.code,
        );

        expect(
          GlobalMaterialLocalizations.delegate.isSupported(Locale(l.code)),
          true,
          reason: l.code,
        );
        expect(
          GlobalWidgetsLocalizations.delegate.isSupported(Locale(l.code)),
          true,
          reason: l.code,
        );
      }
    },
  );
  test(
    'choice persists and reloading restores catalog without network',
    () async {
      await AppLanguage.instance.setLanguage('hi');
      expect(AppLanguage.instance.text('Language'), 'भाषा');
      expect(
        (await SharedPreferences.getInstance()).getString(
          AppLanguage.preferenceKey,
        ),
        'hi',
      );
      await AppLanguage.instance.load();
      expect(AppLanguage.instance.code, 'hi');
      expect(
        AppLanguage.instance.text('a-user-title-not-in-catalog'),
        'a-user-title-not-in-catalog',
      );
    },
  );
  test(
    'invalid selection rejected and invalid saved value falls back safely',
    () async {
      await expectLater(
        AppLanguage.instance.setLanguage('invalid'),
        throwsArgumentError,
      );
      SharedPreferences.setMockInitialValues({
        AppLanguage.preferenceKey: 'invalid',
      });
      await AppLanguage.instance.load();
      expect(AppLanguage.instance.code, 'system');
      expect(AppLanguage.supports(AppLanguage.instance.effectiveCode), true);
    },
  );
  test('form hint getter follows selected language', () async {
    const d = LInputDecoration(hintText: 'Search languages');
    expect(d.hintText, 'Search languages');
    await AppLanguage.instance.setLanguage('hi');
    expect(d.hintText, 'भाषा खोजें');
  });
  testWidgets(
    'fixed labels translate while user/media text remains original; RTL works',
    (tester) async {
      await tester.runAsync(() => AppLanguage.instance.setLanguage('ar'));
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: uiLanguages.map((l) => Locale(l.code)),

          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const Scaffold(
            body: Column(
              children: [LText('Language'), Text('My original movie title')],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(AppLanguage.instance.text('Language')), findsOneWidget);
      expect(find.text('My original movie title'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byType(Column))),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('picker searches English/native names and applies selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: AppLanguage.instance,
        builder: (context, _) => MaterialApp(
          locale: AppLanguage.instance.locale,
          supportedLocales: uiLanguages.map((l) => Locale(l.code)),

          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const LanguageScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Hindi');
    await tester.pumpAndSettle();
    expect(find.text('हिन्दी'), findsOneWidget);
    await tester.tap(find.text('हिन्दी'));
    await tester.pumpAndSettle();
    expect(AppLanguage.instance.code, 'hi');
    expect(find.text('भाषा'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test('source manifest has unrestricted AD_ID permission', () {
    final xml = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(
      xml,
      contains(
        '<uses-permission android:name="com.google.android.gms.permission.AD_ID" />',
      ),
    );
  });
}
