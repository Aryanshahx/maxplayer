#!/usr/bin/env bash
# Run from existing maxplayer repository root after consolidated update.
set -euo pipefail
python3 - <<'PY'
from pathlib import Path
import datetime, subprocess
root = Path.cwd().resolve()
try:
    top = Path(subprocess.check_output(['git', 'rev-parse', '--show-toplevel'], stderr=subprocess.DEVNULL).decode().strip()).resolve()
except (OSError, subprocess.CalledProcessError):
    raise SystemExit('STOP: Open your existing repository root terminal first.')
if top != root or not (root / 'pubspec.yaml').is_file():
    raise SystemExit('STOP: Run from the existing repository ROOT.')
relative = 'desktop/hyper_player/test/consolidated_network_test.dart'
p = root / relative
for parent in [p, *p.parents]:
    if parent == root: break
    if parent.is_symlink(): raise SystemExit('STOP: Symlink path refused.')
if not p.is_file(): raise SystemExit('STOP: Apply the consolidated update first.')
old = '    expect(result.folders, [child.path]);'
new = '''    expect(result.folders, hasLength(1));
    // Windows directory enumeration normalizes separators; compare filesystem
    // identity rather than the spelling of an equivalent folder path.
    expect(await FileSystemEntity.identical(result.folders.single, child.path),
        isTrue);'''
raw = p.read_bytes()
text = raw.decode('utf-8')
normalized = text.replace('\r\n', '\n')
if new in normalized:
    print('Already fixed. No changes needed.')
    raise SystemExit(0)
if normalized.count(old) != 1:
    raise SystemExit('STOP: Test differs from the expected version. No changes made.')
if 'import \'dart:io\';' not in normalized:
    raise SystemExit('STOP: Expected dart:io import missing. No changes made.')
base = Path(subprocess.check_output(['git', 'rev-parse', '--git-path', 'hyper-consolidated-backups']).decode().strip())
if not base.is_absolute(): base = root / base
backup = base / ('windows-path-test-' + datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')) / relative
backup.parent.mkdir(parents=True, exist_ok=False)
backup.write_bytes(raw)
updated = normalized.replace(old, new)
if b'\r\n' in raw: updated = updated.replace('\n', '\r\n')
p.write_bytes(updated.encode('utf-8'))
print('FIXED: ' + relative)
print('Backup: ' + str(backup))
print('Only the test assertion changed. No tests skipped; application and Android code untouched.')
print('Commit/push this correction, then start a NEW Windows workflow run on the pushed branch.')
PY
