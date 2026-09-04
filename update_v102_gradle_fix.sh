#!/bin/bash
set -euo pipefail

# v102 gradle fix: force bundled ML Kit face detection model
# (no Google Play Services required)

echo "Applying Gradle bundled face model patch..."

python3 - <<'PY'
from pathlib import Path

gradle_file = Path('android/app/build.gradle.kts')
text = gradle_file.read_text()

insert_block = """    configurations.all {
        resolutionStrategy {
            force("com.google.mlkit:face-detection:16.1.6")
        }
    }

"""

# Anchor on the first occurrence of the buildTypes line (inside android block)
anchor = "    buildTypes {"
if "force(\"com.google.mlkit:face-detection:16.1.6\")" in text:
    print("Patch already present, skipping.")
elif anchor not in text:
    raise SystemExit("ERROR: buildTypes anchor not found")
else:
    text = text.replace(anchor, insert_block + anchor, 1)
    gradle_file.write_text(text)
    print("Patch inserted successfully.")
PY

echo "Done."
