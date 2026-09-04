#!/usr/bin/env bash
# v101-fix: resolve `flutter pub get` version conflict.
#
# Problem (seen on Pi): hand_landmarker ^3.0.1 requires camera ^0.12.0+1,
# but v100 pinned camera ^0.11.0  ->  "version solving failed".
#
# Fix: bump ONLY the camera line to ^0.12.0+1 (resolves to 0.12.1 on
# Flutter 3.44 / Dart 3.12). Nothing else changes:
#   - camera_android pin is kept (no solver conflict; preserves the v100
#     legacy-Camera2 intent + keeps widget tests green),
#   - camera 0.12's changelog lists additions only, no Dart API breaks,
#     so v100/v101 camera Dart code compiles unchanged,
#   - google_mlkit_face_detection is independent of the camera package.
# v101 never built, so the version stays 1.0.0+101 (no bump).
#
# Run ONCE on the pushed v101 tree (commit 3dc9a06):
#   cd ~/IdeaProjects/maxplayer && git pull && bash update_v101_fix.sh \
#     && flutter pub get && flutter analyze && flutter test
set -eu
cd "$(dirname "$0")"

python3 <<'PYEOF'
import sys

def rep(path, old, new, count=1):
    with open(path, 'r', encoding='utf-8') as f:
        src = f.read()
    n = src.count(old)
    if n != count:
        print(f'PATCH FAILED: {path}: expected {count}x, found {n}x')
        print('--- wanted old text (first 400 chars) ---')
        print(old[:400])
        sys.exit(1)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(src.replace(old, new))
    print(f'patched ({n}x): {path}')

# --- pubspec: camera 0.11 -> 0.12 (hand_landmarker 3 needs ^0.12.0+1) ---
rep('pubspec.yaml',
    '''  # v100: front-camera drowsiness + look-away detection (both opt-in, off by
  # default). camera_android pins the legacy Camera2 backend (API 21+) instead
  # of the CameraX default; ML Kit face detection is on-device (its model
  # downloads once via Play Services, then works offline).
  camera: ^0.11.0
  camera_android: ^0.10.11+1''',
    '''  # v100: front-camera drowsiness + look-away detection (both opt-in, off by
  # default). camera_android pins the legacy Camera2 backend instead of the
  # CameraX default; ML Kit face detection is on-device (its model
  # downloads once via Play Services, then works offline).
  # v101-fix: camera 0.12 (additions only, no Dart API breaks) because
  # hand_landmarker 3 requires camera ^0.12.0+1.
  camera: ^0.12.0+1
  camera_android: ^0.10.11+1''')
PYEOF

echo "ALL v101-fix PATCHES APPLIED"
echo "--- diff stat ---"
git diff --stat
