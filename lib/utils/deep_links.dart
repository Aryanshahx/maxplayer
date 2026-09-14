import 'dart:io';

import 'package:flutter/material.dart';

import '../screens/player_screen.dart';

/// Root navigator key so events that arrive while ANY screen is on top
/// (e.g. the "Continue watching" notification deep link) can still push
/// the player. Wired to the app's [MaterialApp] in main.dart.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Resumes the video referenced by a "Continue watching" notification tap.
/// The player's normal resume logic offers the saved position ("Resume /
/// Start over"), so tapping the notification lands right back in the video.
void openContinueWatching(String path) {
  if (path.isEmpty) return;
  try {
    if (!File(path).existsSync()) return;
  } catch (_) {
    return;
  }
  final nav = rootNavigatorKey.currentState;
  if (nav == null) return;
  // Warm re-open case: the cached engine already shows the player (the
  // video never stopped) — never stack a second player over a live one.
  if (PlayerScreen.isOpen) return;
  final name = path.split(Platform.pathSeparator).last;
  nav.push(
    MaterialPageRoute(
      builder: (_) => PlayerScreen(path: path, title: name),
    ),
  );
}
