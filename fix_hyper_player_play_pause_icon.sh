#!/usr/bin/env bash
set -euo pipefail
[[ -d .git && -f pubspec.yaml ]] || { echo 'Run from your MaxPlayer repository root.' >&2; exit 1; }
python3 - <<'PY'
from pathlib import Path
p = Path('desktop/hyper_player/lib/main.dart')
s = p.read_text()
old = 'Icons.play_pause'
if old in s:
    count = s.count(old)
    p.write_text(s.replace(old, 'Icons.play_arrow'))
    print(f'Replaced {count} unsupported icon reference(s). Playback action unchanged.')
else:
    print('No unsupported play_pause icon found; no changes made.')
PY
