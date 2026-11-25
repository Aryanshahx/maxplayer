#!/usr/bin/env bash
# RunX Player — bump to 1.0.1+90.
#
# WHY: the +89 bundle was rejected, and Play keeps one live artifact per track.
# You cannot reuse a rejected versionCode for the VPN-free build, so this bumps
# the version everywhere it is asserted (pubspec, the analytics tag and the
# widget test that pins it). Nothing else changes.
#
# Usage — run from your existing repository root:
#   bash update_android_version_90.sh --check
#   bash update_android_version_90.sh
#   bash update_android_version_90.sh --verify
#
# Then:
#   flutter pub get && flutter analyze --no-fatal-infos && flutter test
#   git add -A && git commit -m "1.0.1+90: VPN-free build for Play resubmission"
#   git push origin main
set -euo pipefail
command -v python3 >/dev/null || { echo 'Python 3 is required'; exit 1; }
python3 - "$@" <<'ANDVER90_PY'
import pathlib, re, subprocess, sys

NEW = '1.0.1+90'

def fail(m):
    print('STOP: ' + m, file=sys.stderr)
    sys.exit(1)

args = sys.argv[1:] or ['--apply']
if len(args) != 1 or args[0] not in ['--check', '--apply', '--verify']:
    fail('Use no argument (apply), --check or --verify from the repository root.')
mode = args[0]

try:
    root = pathlib.Path(subprocess.check_output(
        ['git', 'rev-parse', '--show-toplevel'], stderr=subprocess.DEVNULL
    ).decode().strip()).resolve()
except Exception:
    fail('Not inside a Git repository.')
if pathlib.Path.cwd().resolve() != root:
    fail('Run from your existing repository root; no files changed.')

targets = [
    ('pubspec.yaml', r'^version:\s*1\.0\.1\+\d+\s*$', 'version: ' + NEW),
    ('lib/services/app_analytics.dart',
     r"static const String kAppVersionTag = '1\.0\.1\+\d+';",
     "static const String kAppVersionTag = '%s';" % NEW),
    ('test/widget_test.dart',
     r"expect\(AppAnalytics\.kAppVersionTag, '1\.0\.1\+\d+'\);",
     "expect(AppAnalytics.kAppVersionTag, '%s');" % NEW),
]

plan, problems = [], []
for rel, pattern, replacement in targets:
    p = root / rel
    if not p.is_file():
        problems.append('  missing: ' + rel)
        continue
    text = p.read_text(encoding='utf-8')
    m = re.search(pattern, text, re.M)
    if not m:
        problems.append('  no version line found in ' + rel)
        continue
    plan.append((rel, text, m.group(0), replacement))

if problems:
    fail('These files are unexpected:\n' + '\n'.join(problems))

if mode == '--verify':
    bad = [rel for rel, text, _, repl in plan if repl not in text]
    if bad:
        fail('Not on ' + NEW + ':\n  ' + '\n  '.join(bad))
    print('VERIFIED: all %d files are on %s.' % (len(plan), NEW))
    sys.exit(0)

print('Version bump to %s:' % NEW)
for rel, _, current, repl in plan:
    state = 'already' if current == repl else 'bump  '
    print('  %s %-32s %s -> %s' % (state, rel, current.strip(), repl.strip()))

if mode == '--check':
    print('CHECK PASSED. No files written.')
    sys.exit(0)

for rel, text, current, repl in plan:
    if current == repl:
        continue
    (root / rel).write_text(text.replace(current, repl, 1), encoding='utf-8')

print('')
print('Next:')
print('  flutter pub get && flutter analyze --no-fatal-infos && flutter test')
print('  git add -A && git commit -m "1.0.1+90: VPN-free build for Play resubmission"')
print('Then upload 90 to production, halt any testing track still on a VPN build,')
print('and complete App content -> VPN service with the "no VPN" video.')
ANDVER90_PY
