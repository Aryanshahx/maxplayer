import 'package:flutter/material.dart';

/// Shared [Image.frameBuilder]: thumbnails fade in softly (~220ms) instead
/// of popping onto the screen. Wraps the decoded frame of any Image.file /
/// Image.network that doesn't already handle transitions.
Widget fadeInImageFrame(
  BuildContext context,
  Widget child,
  int? frame,
  bool wasSynchronouslyLoaded,
) {
  if (wasSynchronouslyLoaded) return child;
  return AnimatedOpacity(
    opacity: frame == null ? 0 : 1,
    duration: const Duration(milliseconds: 220),
    curve: Curves.easeOut,
    child: child,
  );
}
