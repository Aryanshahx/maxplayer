#!/bin/bash
set -euo pipefail

# v102 lint fix: replace print() with debugPrint() in player state

python3 - <<'PY'
from pathlib import Path

p = Path('lib/state/media_player_state.dart')
text = p.read_text()

# Ensure foundation import exists (debugPrint)
if "package:flutter/foundation.dart" not in text:
    anchor = "import 'dart:ui' as ui;"
    if anchor not in text:
        raise SystemExit("ERROR: dart:ui import anchor not found")
    text = text.replace(anchor, anchor + "\nimport 'package:flutter/foundation.dart';", 1)

# Replace the two print calls we added
text = text.replace(
    "print('HandLandmarker init failed: $e');",
    "debugPrint('HandLandmarker init failed: $e');"
)
text = text.replace(
    "print('HandLandmarker processFrame error: $e');",
    "debugPrint('HandLandmarker processFrame error: $e');"
)

p.write_text(text)
print("Lint fix applied.")
PY

echo "Done."
