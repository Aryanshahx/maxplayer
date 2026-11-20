import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_player/local_thumbnail.dart';
import 'package:hyper_player/screens/about_android.dart';
import 'package:hyper_player/screens/info_sheets.dart';

void main() {
  test('Network media never sent to local thumbnail extraction', () async {
    expect(
        await WindowsThumbnails.get('https://example.com/video.mp4'), isNull);
  });
  testWidgets('Thumbnail safely renders unavailable local media',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: SizedBox(
            width: 96, height: 54, child: LocalThumbnail('/missing.mp4'))));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.video_file_outlined), findsOneWidget);
  });
  testWidgets('About uses Android brand header and mission section',
      (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: AboutSheet())));
    expect(find.text('Hyper Player'), findsOneWidget);
    expect(find.text('by Hyper Tech Labs'), findsOneWidget);
    expect(find.text('OUR MISSION'), findsOneWidget);
  });
  testWidgets('Privacy follows Android dialog not generic sheet',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => showWindowsPrivacy(context),
                child: const Text('Open')))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });
}
