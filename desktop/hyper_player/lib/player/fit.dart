// Pure screen-fit model shared by the player screen and unit tests.
//
// Ported 1:1 from the old MaxPlayer (v1.0.0+148) player: six fit modes in
// a fixed loop — Fit -> Crop -> Stretch -> 16:9 -> 4:3 -> Original -> Fit.
// The 16:9 / 4:3 modes force the FRAME to that aspect ratio (VLC-style
// resize, engine-independent, identical in landscape and portrait) while
// "Original" renders pixels 1:1 (BoxFit.none).
library;

import 'package:flutter/material.dart';

enum FitMode { fit, crop, stretch, sixteenNine, fourThree, original }

extension FitModeProps on FitMode {
  /// How the video fills its frame. 16:9 / 4:3 stretch the video INTO the
  /// forced frame (the frame itself is sized by [aspectRatio]).
  BoxFit get boxFit => switch (this) {
        FitMode.fit => BoxFit.contain,
        FitMode.crop => BoxFit.cover,
        FitMode.stretch => BoxFit.fill,
        FitMode.sixteenNine => BoxFit.fill,
        FitMode.fourThree => BoxFit.fill,
        FitMode.original => BoxFit.none,
      };

  /// Non-null forces the frame to that aspect ratio; null keeps the video's
  /// own shape.
  double? get aspectRatio => switch (this) {
        FitMode.sixteenNine => 16 / 9,
        FitMode.fourThree => 4 / 3,
        _ => null,
      };

  String get label => switch (this) {
        FitMode.fit => 'Fit',
        FitMode.crop => 'Crop',
        FitMode.stretch => 'Stretch',
        FitMode.sixteenNine => '16:9',
        FitMode.fourThree => '4:3',
        FitMode.original => 'Original',
      };

  IconData get icon => switch (this) {
        FitMode.fit => Icons.fit_screen,
        FitMode.crop => Icons.crop,
        FitMode.stretch => Icons.open_in_full,
        FitMode.sixteenNine => Icons.crop_16_9,
        FitMode.fourThree => Icons.crop_landscape,
        FitMode.original => Icons.crop_original,
      };
}

/// Next fit in the loop (Original wraps back to Fit).
FitMode nextFitMode(FitMode current) =>
    FitMode.values[(current.index + 1) % FitMode.values.length];

/// Previous fit in the loop (Fit wraps back to Original).
FitMode previousFitMode(FitMode current) => FitMode.values[
    (current.index - 1 + FitMode.values.length) % FitMode.values.length];
