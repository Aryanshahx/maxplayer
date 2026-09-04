#!/bin/bash
set -euo pipefail

# v102: fix camera AI features not working
# - Air gestures: use CPU delegate instead of GPU (compatibility)
# - Sleep/look-away: force bundled ML Kit face detection model
# - Add logging so failures are visible in logcat

echo "Applying v102 patches..."

python3 - <<'PY'
from pathlib import Path

# Patch 1: lib/state/media_player_state.dart
dart_file = Path('lib/state/media_player_state.dart')
dart_text = dart_file.read_text()

# 1a. Use CPU delegate for hand landmarker
old_create = """      final plugin = HandLandmarkerPlugin.create(
        numHands: 1,
        minHandDetectionConfidence: 0.6,
      );"""
new_create = """      final plugin = HandLandmarkerPlugin.create(
        numHands: 1,
        minHandDetectionConfidence: 0.6,
        delegate: HandLandmarkerDelegate.cpu,
      );"""
if old_create not in dart_text:
    raise SystemExit("ERROR: hand_landmarker create block not found")
dart_text = dart_text.replace(old_create, new_create)

# 1b. Add logging to _syncHands catch block
old_catch1 = """    } catch (_) {
      _hands = null;
    }"""
new_catch1 = """    } catch (e) {
      print('HandLandmarker init failed: $e');
      _hands = null;
    }"""
if old_catch1 not in dart_text:
    raise SystemExit("ERROR: _syncHands catch block not found")
dart_text = dart_text.replace(old_catch1, new_catch1)

# 1c. Add logging to _onSharedCameraFrame catch block
old_catch2 = """    } catch (_) {}
  }

  void _onHandLandmarks"""
new_catch2 = """    } catch (e) {
      print('HandLandmarker processFrame error: $e');
    }
  }

  void _onHandLandmarks"""
if old_catch2 not in dart_text:
    raise SystemExit("ERROR: _onSharedCameraFrame catch block not found")
dart_text = dart_text.replace(old_catch2, new_catch2)

dart_file.write_text(dart_text)

# Patch 2: android/app/build.gradle.kts
gradle_file = Path('android/app/build.gradle.kts')
gradle_text = gradle_file.read_text()

# Insert a resolution strategy to force bundled face-detection model.
# We append it inside the android block, right after the defaultConfig block.
old_anchor = """    defaultConfig {
        applicationId = "com.hypertechlabs.maxplayer"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }"""
new_anchor = """    defaultConfig {
        applicationId = "com.hypertechlabs.maxplayer"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    configurations.all {
        resolutionStrategy {
            force("com.google.mlkit:face-detection:16.1.6")
        }
    }"""
if old_anchor not in gradle_text:
    raise SystemExit("ERROR: defaultConfig block not found in build.gradle.kts")
gradle_text = gradle_text.replace(old_anchor, new_anchor)

gradle_file.write_text(gradle_text)

print("Patches applied successfully.")
PY

echo "Done. Run 'flutter analyze' and 'flutter test' to confirm."
