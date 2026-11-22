#!/usr/bin/env bash
set -euo pipefail
[[ -f pubspec.yaml && -d .git ]] || { echo 'Run from the repository root.' >&2; exit 1; }
python3 - <<'PY'
from pathlib import Path
import re
p = Path('desktop/hyper_player/lib/main.dart')
s = p.read_text()
# Match both original and dart-formatted multiline forms. Collection-if widgets
# are deliberately not touched.
pairs = [
 (r'if \(done && selected \+ 1 < queue\.length\)\s*play\(selected \+ 1\);', 'if (done && selected + 1 < queue.length) { play(selected + 1); }'),
 (r'if \(!mounted\)\s*return;', 'if (!mounted) { return; }'),
 (r'if \(index < 0 \|\| index >= queue\.length\)\s*return;', 'if (index < 0 || index >= queue.length) { return; }'),
 (r'if \(!mounted \|\| paths\.isEmpty\)\s*return;', 'if (!mounted || paths.isEmpty) { return; }'),
 (r'if \(selected == -1\)\s*await play\(start\);', 'if (selected == -1) { await play(start); }'),
 (r'if \(busy\)\s*return;', 'if (busy) { return; }'),
 (r'if \(path == null \|\| !mounted\)\s*return;', 'if (path == null || !mounted) { return; }'),
 (r"if \(paths\.isEmpty\)\s*notify\(\s*'No supported media found directly inside this folder\.'\s*,?\s*\);", "if (paths.isEmpty) { notify('No supported media found directly inside this folder.'); }"),
 (r'if \(mounted\)\s*setState\(\(\) => busy = false\);', 'if (mounted) { setState(() => busy = false); }'),
 (r'if \(value == null\)\s*return;', 'if (value == null) { return; }'),
]
count = 0
for pattern, replacement in pairs:
    s, n = re.subn(pattern, lambda _: replacement, s)
    count += n
if count:
    p.write_text(s)
print(f'Added braces to {count} desktop statements. Android and workflow files unchanged.')
PY
