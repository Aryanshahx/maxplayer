import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_player/player/mini_player.dart';
import 'package:hyper_player/player/timeline_preview.dart';

class FakeWindow implements MiniWindowPort {
  Rect rect = const Rect.fromLTWH(80, 100, 1200, 800);
  bool full = false, max = false, top = false, failTopOnce = false;
  @override
  Future<Rect> bounds() async => rect;
  @override
  Future<bool> fullscreen() async => full;
  @override
  Future<bool> maximized() async => max;
  @override
  Future<bool> topmost() async => top;
  @override
  Future<void> setBounds(Rect value) async {
    rect = value;
  }

  @override
  Future<void> setFullscreen(bool value) async {
    full = value;
  }

  @override
  Future<void> setMaximized(bool value) async {
    max = value;
  }

  @override
  Future<void> setTopmost(bool value) async {
    if (failTopOnce) {
      failTopOnce = false;
      throw StateError('native failure');
    }
    top = value;
  }
}

void main() {
  test(
      'Mini-player uses existing window and restores bounds/fullscreen/topmost',
      () async {
    final port = FakeWindow()
      ..full = true
      ..max = true;
    final original = port.rect;
    final mini = MiniPlayerWindow(port);
    await mini.enter();
    expect(mini.active, isTrue);
    expect(port.top, isTrue);
    expect(port.rect.size, const Size(480, 320));
    expect(port.full, isFalse);
    await mini.restore();
    expect(mini.active, isFalse);
    expect(port.rect, original);
    expect(port.full, isTrue);
    expect(port.max, isTrue);
    expect(port.top, isFalse);
  });
  test('Failed mini entry restores the previous native state', () async {
    final port = FakeWindow()..failTopOnce = true;
    final original = port.rect;
    final mini = MiniPlayerWindow(port);
    await expectLater(mini.enter(), throwsStateError);
    expect(port.rect, original);
    expect(port.top, isFalse);
    expect(mini.active, isFalse);
  });
  testWidgets('Mini-player provides accessible play and restore controls',
      (tester) async {
    bool restored = false, played = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MiniPlayerControls(
                title: 'Fixture',
                playing: false,
                onPlayPause: () => played = true,
                onRestore: () => restored = true))));
    await tester.tap(find.byTooltip('Play'));
    await tester.tap(find.byTooltip('Return to full player'));
    expect(played && restored, isTrue);
  });
  testWidgets(
      'Hover is debounced and displays unavailable rather than a fake frame',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 500,
                    child: HoverTimeline(
                        sourceKey: 'a',
                        duration: const Duration(minutes: 2),
                        loader: (_) async {
                          calls++;
                          return null;
                        },
                        child: const SizedBox(height: 40)))))));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(400, 300));
    await mouse.moveTo(const Offset(420, 300));
    await tester.pump(const Duration(milliseconds: 50));
    expect(calls, 0);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(calls, 1);
    expect(find.text('Preview unavailable'), findsOneWidget);
    await mouse.removePointer();
    await tester.pump();
    expect(find.text('Preview unavailable'), findsNothing);
  });
  testWidgets('Leaving hover invalidates a pending image response',
      (tester) async {
    final result = Completer<Uint8List?>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 500,
                    child: HoverTimeline(
                        sourceKey: 'a',
                        duration: const Duration(minutes: 2),
                        loader: (_) => result.future,
                        child: const SizedBox(height: 40)))))));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(400, 300));
    await mouse.moveTo(const Offset(420, 300));
    await tester.pump(const Duration(milliseconds: 250));
    await mouse.moveTo(const Offset(20, 20));
    await tester.pump();
    result.complete(Uint8List.fromList([1, 2, 3]));
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.text('Loading preview…'), findsNothing);
    await mouse.removePointer();
  });
}
