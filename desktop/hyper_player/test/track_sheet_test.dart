import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_player/screens/track_sheet.dart';

Widget host(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));
void main() {
  test('Track labels match Android title language codec order', () {
    expect(
        desktopTrackLabel(id: '2', title: 'Main', language: 'hi', codec: 'aac'),
        'Main • HI • aac');
    expect(desktopTrackLabel(id: '3'), 'Track 3');
  });
  testWidgets(
      'Subtitle sheet offers Off and external file without any AI entry',
      (tester) async {
    bool external = false;
    await tester.pumpWidget(host(DesktopTrackSheet(
        subtitle: true,
        selected: 'no',
        tracks: const [],
        onSelect: (_) async {},
        onExternal: () => external = true)));
    expect(find.text('Off'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.text('No embedded subtitle tracks available.'), findsOneWidget);
    await tester.tap(find.text('Load subtitle file'));
    expect(external, isTrue);
    expect(find.text('Generate with AI ✨'), findsNothing);
  });
  testWidgets('Audio rows show selected track and handle selection failures',
      (tester) async {
    String? selected;
    await tester.pumpWidget(host(DesktopTrackSheet(
        subtitle: false,
        selected: '1',
        tracks: const [
          DesktopTrackChoice('1', 'English'),
          DesktopTrackChoice('2', 'Hindi')
        ],
        onSelect: (id) async {
          selected = id;
          throw StateError('failed');
        })));
    expect(find.text('Off'), findsNothing);
    await tester.tap(find.text('Hindi'));
    await tester.pumpAndSettle();
    expect(selected, '2');
    expect(
        find.text('Could not select track. Please try again.'), findsOneWidget);
  });
  testWidgets('Empty audio sheet explains playback requirement',
      (tester) async {
    await tester.pumpWidget(host(DesktopTrackSheet(
        subtitle: false,
        selected: 'auto',
        tracks: const [],
        onSelect: (_) async {})));
    expect(
        find.textContaining('Start playback to load tracks.'), findsOneWidget);
    expect(find.text('Generate with AI ✨'), findsNothing);
  });
}
