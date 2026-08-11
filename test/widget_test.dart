import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maxplayer/main.dart';

void main() {
  testWidgets('Max Player launches to the library screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MaxPlayerApp());

    // The library screen's app bar title should be visible on launch.
    expect(find.text('Max Player'), findsOneWidget);
  });
}
