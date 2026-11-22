#!/usr/bin/env bash
set -euo pipefail
[[ -d .git && -f pubspec.yaml ]] || { echo 'Run from the repository root.' >&2; exit 1; }
python3 - <<'PY'
from pathlib import Path
import re
p = Path('desktop/hyper_player/lib/main.dart')
s = p.read_text()
patterns = [
    r"\s*IconButton\(\s*tooltip: 'Open files \(Ctrl\+O\)',\s*onPressed: files,\s*icon: const Icon\(Icons\.video_file_outlined\)\),",
    r"\s*IconButton\(\s*tooltip: 'Current playlist',\s*onPressed: showQueue,\s*icon: const Icon\(Icons\.queue_music\)\),",
]
updated = s
count = 0
for pattern in patterns:
    updated, n = re.subn(pattern, '', updated)
    count += n
if count == 2:
    p.write_text(updated)
    print('Removed Open files and Current playlist header buttons. Other controls unchanged.')
elif count == 0 and "tooltip: 'Open files (Ctrl+O)'" not in s and "tooltip: 'Current playlist'" not in s:
    print('Header buttons already absent. No changes made.')
else:
    raise SystemExit('Unexpected source layout; no changes written. Share the latest main.dart before applying a different patch.')
PY
