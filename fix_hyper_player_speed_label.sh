#!/usr/bin/env bash
set -euo pipefail
[[ -d .git && -f pubspec.yaml ]] || { echo 'Run from your repository root.' >&2; exit 1; }
python3 - <<'PY'
from pathlib import Path
p = Path('desktop/hyper_player/lib/main.dart')
s = p.read_text()
old = "Text('${rate}×')"
new = "Text('$rate×')"
if old in s:
    p.write_text(s.replace(old, new))
    print('Fixed unnecessary braces in playback speed label.')
else:
    print('Original speed label not found; no changes made.')
PY
