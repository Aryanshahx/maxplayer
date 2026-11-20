import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_player/screens/quick_share_screen.dart';

void main() {
  testWidgets(
      'Quick Share requires trust consent and file selection before sending',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: DesktopQuickShareScreen(knownSources: [])));
    expect(find.text('Quick Share'), findsOneWidget);
    final send = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Direct send'));
    expect(send.onPressed, isNull);
    expect(find.text('I trust this local network'), findsOneWidget);
    await tester.tap(find.byTooltip('Receive from another device'));
    await tester.pumpAndSettle();
    final connect = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Connect / load files'));
    expect(connect.onPressed, isNull);
  });
}
