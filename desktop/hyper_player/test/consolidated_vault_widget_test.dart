import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_player/screens/private_space_screen.dart';

void main() {
  testWidgets(
      'Private gate uses Android composition with explicit Windows recovery limits',
      (tester) async {
    final password = TextEditingController(), repeat = TextEditingController();
    addTearDown(password.dispose);
    addTearDown(repeat.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PrivateVaultGate(
                creating: true,
                busy: false,
                acknowledged: false,
                password: password,
                repeat: repeat,
                onAcknowledge: (_) {},
                onSubmit: () {},
                onRecovery: () {}))));
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.text('Create a vault password'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Create & open'))
            .onPressed,
        isNull);
    expect(find.textContaining('originals remain outside'), findsOneWidget);
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.obscureText, isTrue);
      expect(field.enableSuggestions, isFalse);
    }
  });
  testWidgets('Non-Windows UI does not silently downgrade account protection',
      (tester) async {
    if (!Platform.isWindows) {
      await tester
          .pumpWidget(const MaterialApp(home: DesktopPrivateSpaceScreen()));
      await tester.pumpAndSettle();
      expect(find.textContaining('No insecure fallback'), findsOneWidget);
      expect(find.text('Create & open'), findsNothing);
    }
  });
}
