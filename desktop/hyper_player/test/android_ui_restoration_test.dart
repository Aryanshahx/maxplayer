import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hyper_player/screens/local_ai_screen.dart';
import 'package:hyper_player/screens/cloud_storage_screen.dart';
import 'package:hyper_player/screens/ftp_screen.dart';
import 'package:hyper_player/discover/ask_ai_sheet.dart';
import 'package:hyper_player/discover/ai_suggest_sheet.dart';
import 'package:hyper_player/discover/tmdb.dart';
import 'package:hyper_player/app_design.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  testWidgets(
      'AI subtitle options include Android fast model language and karaoke',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: LocalAiScreen(source: 'fixture.mp4')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Fast (recommended)'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Speech language'), 250);
    expect(find.text('Speech language'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Karaoke style'), 200);
    expect(find.text('Karaoke style'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text('Translate speech to English'), 200);
    expect(find.text('Translate speech to English'), findsOneWidget);
  });
  testWidgets('Cloud screen includes disclosed pCloud sponsor grid',
      (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: DesktopCloudStorageScreen()));
    await tester.pumpAndSettle();
    expect(find.text('pCloud · more space for your videos'), findsOneWidget);
    expect(find.textContaining('Partner link'), findsOneWidget);
  });
  testWidgets('FTP page defaults to TLS and uses password obscuring',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: FtpScreen()));
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue);
    expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .where((field) => field.obscureText)
            .length,
        1);
  });
  testWidgets(
      'Ask AI is the Android question screen instead of unavailable control',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: AskAiSheet(
                    movie: TmdbMovie(
                        id: 1,
                        title: 'Fixture film',
                        rating: 7,
                        overview: 'Fixture story.'))))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ask AI about'), findsOneWidget);
    expect(find.text('Explain the story in 3 lines.'), findsOneWidget);
  });
  testWidgets('Discover AI uses Android taste prompt composition',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: AiSuggestSheet()))));
    await tester.pumpAndSettle();
    expect(find.text('AI Suggestor'), findsOneWidget);
    expect(find.text('Funny action like Dhoom'), findsOneWidget);
  });
  test('App icon is a bundled real PNG, not a missing asset fallback',
      () async {
    final data = await rootBundle.load('assets/icon.png');
    expect(
        data.buffer.asUint8List().take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
  });
  test('Accent applies to slider and progress widgets as well as colour scheme',
      () async {
    final design = AppDesign();
    await design.selectAccent(3);
    final theme = design.theme(ThemeData.dark());
    expect(theme.sliderTheme.thumbColor, design.accent);
    expect(theme.progressIndicatorTheme.color, design.accent);
    expect(theme.iconTheme.color, design.accent);
  });
}
