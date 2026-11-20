import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hyper_player/app_design.dart';
import 'package:hyper_player/screens/library_layouts.dart';
import 'package:hyper_player/screens/onboarding_flow.dart';
import 'package:hyper_player/utils/onboarding.dart';
import 'package:hyper_player/library_projection.dart';
import 'package:hyper_player/discover/ai_suggest.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  testWidgets(
      'Three layouts have different navigation structures and active actions',
      (tester) async {
    var opens = 0;
    Widget layout(AppDesignMode mode) => MaterialApp(
        home: Scaffold(
            body: LibraryLayouts(
                mode: mode,
                androidLibrary: const Text('Android library fixture'),
                videos: const [],
                play: (_) {},
                destinations: [
                  LibraryDestination('Folders', Icons.folder, () => opens++)
                ])));
    await tester.pumpWidget(layout(AppDesignMode.android));
    expect(find.text('Android library fixture'), findsOneWidget);
    expect(find.text('LIBRARY WORKSPACE'), findsNothing);
    await tester.pumpWidget(layout(AppDesignMode.compact));
    expect(find.text('LIBRARY WORKSPACE'), findsOneWidget);
    await tester.tap(find.text('Folders'));
    expect(opens, 1);
    expect(find.text('YOUR PRIVATE CINEMA'), findsNothing);
    await tester.pumpWidget(layout(AppDesignMode.cinema));
    expect(find.text('YOUR PRIVATE CINEMA'), findsOneWidget);
    expect(find.text('Ready to watch'), findsOneWidget);
    expect(find.text('Android library fixture'), findsNothing);
    await tester.tap(find.text('Folders'));
    expect(opens, 2);
  });
  testWidgets('Compact navigation collapses to icon rail on a narrow window',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 500,
                child: LibraryLayouts(
                    mode: AppDesignMode.compact,
                    androidLibrary: const Text('Videos'),
                    videos: const [],
                    play: (_) {},
                    destinations: [
                      LibraryDestination('Folders', Icons.folder, () {})
                    ])))));
    expect(find.byTooltip('Folders'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'Android welcome/usage flow is shown and completion persists once',
      (tester) async {
    expect(await Onboarding.hasSeen(), isFalse);
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const OnboardingFlow())),
                    child: const Text('Start guide'))))));
    await tester.tap(find.text('Start guide'));
    await tester.pumpAndSettle();
    expect(find.text('Skip'), findsOneWidget);
    expect(find.textContaining('phone'), findsNothing);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(await Onboarding.hasSeen(), isTrue);
    expect(find.text('Start guide'), findsOneWidget);
  });
  test(
      'Android display sort options keep unknown durations last in both directions',
      () {
    const queue = ['a.mp4', 'unknown.mp4', 'b.mp4'];
    List<int> sorted(String sort) => visibleLibraryIndices(queue,
        onlyFavourites: false,
        favourites: const [],
        sort: sort,
        sizes: const {'a.mp4': 200, 'b.mp4': 100},
        lengths: const {'a.mp4': 1000, 'b.mp4': 5000});
    expect(sorted('sizeAsc'), [2, 0, 1]);
    expect(sorted('sizeDesc'), [0, 2, 1]);
    expect(sorted('lengthAsc'), [0, 2, 1]);
    expect(sorted('lengthDesc'), [2, 0, 1]);
    expect(sorted('dateDesc'), [2, 1, 0]);
  });
  test('Accent selection persists locally without replacing the layout',
      () async {
    final design = AppDesign();
    await design.select(AppDesignMode.cinema);
    await design.selectAccent(2);
    final restored = AppDesign();
    await restored.load();
    expect(restored.mode, AppDesignMode.cinema);
    expect(restored.accentIndex, 2);
    expect(restored.theme(ThemeData.dark()).colorScheme.primary,
        AppDesign.accentPalette[2]);
  });
  test(
      'Android recommender parser accepts real JSON title picks and rejects garbage',
      () {
    expect(
        parseAiSuggestionJson(
                '```json\n[{"title":"3 Idiots","year":2009}]\n```')
            .single
            .title,
        '3 Idiots');
    expect(parseAiSuggestionJson('not an AI result'), isEmpty);
  });
}
