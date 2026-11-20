import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_player/screens/desktop_display_screen.dart';

void main() {
  testWidgets('Folder grouping persists before updating its selection',
      (tester) async {
    bool? saved;
    await tester.pumpWidget(MaterialApp(
        home: DesktopDisplayScreen(
            listMode: false,
            onChange: (mode, sort) async {},
            onGroupByFolder: (value) async {
              saved = value;
            })));
    final grouping =
        find.widgetWithText(SwitchListTile, 'Group videos by folder');
    await tester.scrollUntilVisible(grouping, 250);
    await tester.ensureVisible(grouping);
    await tester.pumpAndSettle();
    await tester.tap(grouping);
    await tester.pumpAndSettle();
    expect(saved, isTrue);
    expect(tester.widget<SwitchListTile>(grouping).value, isTrue);
  });
  testWidgets('Saved sort selection is reflected when reopening settings',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: DesktopDisplayScreen(
            listMode: false,
            initialSort: 'nameDesc',
            onChange: (mode, sort) async {})));
    final row = find.widgetWithText(ListTile, 'Name · Z–A');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: row, matching: find.byIcon(Icons.radio_button_checked)),
        findsOneWidget);
  });
  testWidgets('Favourite filter is saved and reflected in the switch',
      (tester) async {
    bool? saved;
    await tester.pumpWidget(MaterialApp(
        home: DesktopDisplayScreen(
            listMode: false,
            onChange: (mode, sort) async {},
            onOnlyFavourites: (value) async {
              saved = value;
            })));
    final filter = find.widgetWithText(SwitchListTile, 'Show only favourites');
    await tester.scrollUntilVisible(filter, 250);
    await tester.ensureVisible(filter);
    await tester.pumpAndSettle();
    await tester.tap(filter);
    await tester.pumpAndSettle();
    expect(saved, isTrue);
    expect(tester.widget<SwitchListTile>(filter).value, isTrue);
  });
  testWidgets('Favourite filter save failure keeps original selection',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: DesktopDisplayScreen(
            listMode: false,
            onChange: (mode, sort) async {},
            onOnlyFavourites: (value) async {
              throw StateError('disk');
            })));
    final filter = find.widgetWithText(SwitchListTile, 'Show only favourites');
    await tester.scrollUntilVisible(filter, 250);
    await tester.ensureVisible(filter);
    await tester.pumpAndSettle();
    await tester.tap(filter);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(filter).value, isFalse);
    expect(find.text('Could not save favourites filter.'), findsOneWidget);
  });
  testWidgets('Playback action saves before changing selection',
      (tester) async {
    bool? stored;
    await tester.pumpWidget(MaterialApp(
        home: DesktopDisplayScreen(
            listMode: false,
            onChange: (mode, sort) async {},
            onQueueAll: (value) async {
              stored = value;
            })));
    await tester.scrollUntilVisible(
        find.widgetWithText(SwitchListTile, 'Queue All'), 250);
    await tester
        .ensureVisible(find.widgetWithText(SwitchListTile, 'Queue All'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, 'Queue All'));
    await tester.pumpAndSettle();
    expect(stored, isFalse);
    expect(
        tester
            .widget<SwitchListTile>(
                find.widgetWithText(SwitchListTile, 'Queue All'))
            .value,
        isFalse);
    expect(find.textContaining('Play Single: stop'), findsOneWidget);
  });
  testWidgets('Playback action retains previous value when persistence fails',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: DesktopDisplayScreen(
            listMode: false,
            onChange: (mode, sort) async {},
            onQueueAll: (value) async {
              throw StateError('disk');
            })));
    await tester.scrollUntilVisible(
        find.widgetWithText(SwitchListTile, 'Queue All'), 250);
    await tester
        .ensureVisible(find.widgetWithText(SwitchListTile, 'Queue All'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, 'Queue All'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<SwitchListTile>(
                find.widgetWithText(SwitchListTile, 'Queue All'))
            .value,
        isTrue);
    expect(find.text('Could not save playback action.'), findsOneWidget);
  });
  testWidgets('Display layout commits through the real change callback',
      (tester) async {
    bool? saved;
    await tester.pumpWidget(MaterialApp(
        home: DesktopDisplayScreen(
            listMode: false,
            onChange: (mode, sort) async {
              saved = mode;
            })));
    await tester.tap(find.text('List View'));
    await tester.pumpAndSettle();
    expect(saved, isTrue);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
  testWidgets(
      'Failed display change restores selected layout and reports failure',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: DesktopDisplayScreen(
            listMode: false,
            onChange: (mode, order) async {
              throw StateError('storage unavailable');
            })));
    Card modeCard(String title) => tester.widget<Card>(
        find.ancestor(of: find.text(title), matching: find.byType(Card)));
    double width(String title) =>
        (modeCard(title).shape! as RoundedRectangleBorder).side.width;
    expect(width('Grid View'), 1.6);
    await tester.tap(find.text('List View'));
    await tester.pumpAndSettle();
    expect(width('Grid View'), 1.6);
    expect(width('List View'), 1);
    expect(find.text('Could not save display settings.'), findsOneWidget);
  });
}
