import 'package:flutter/material.dart';

/// Player screen-fit modes. Six modes, cycled by the fit button and by a
/// two-finger pinch (expand = next, contract = previous) when pinch-to-zoom
/// is turned OFF in player settings.
enum FitMode { fit, crop, stretch, fitWidth, fitHeight, sixteenNine }

extension FitModeProps on FitMode {
  BoxFit get boxFit => switch (this) {
        FitMode.fit => BoxFit.contain,
        FitMode.crop => BoxFit.cover,
        FitMode.stretch => BoxFit.fill,
        FitMode.fitWidth => BoxFit.fitWidth,
        FitMode.fitHeight => BoxFit.fitHeight,
        FitMode.sixteenNine => BoxFit.contain,
      };

  String get label => switch (this) {
        FitMode.fit => 'Fit',
        FitMode.crop => 'Crop',
        FitMode.stretch => 'Stretch',
        FitMode.fitWidth => 'Fit width',
        FitMode.fitHeight => 'Fit height',
        FitMode.sixteenNine => '16:9',
      };
}

/// Pure cycle with wraparound: [delta] steps ahead (positive = next,
/// negative = previous). Unit-tested.
int cycleIndex(int current, int length, int delta) =>
    ((current + delta) % length + length) % length;
