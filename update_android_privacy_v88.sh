#!/usr/bin/env bash
# RunX Player 1.0.1+88 — privacy copy follow-up (2 files).
#
# WHY: update_android_play_v88.sh added the in-app VPN disclosure, so the
# bundled policy text was updated — but the two PUBLIC copies still contained
# the old sentence "there is no separate in-app consent or instruction screen".
# ad_free_review77_test.dart and ui_theme82_test.dart compare all three copies,
# so they failed. This patch syncs PRIVACY_POLICY.md and privacy/index.html
# with lib/utils/privacy_policy.dart. Nothing else changes.
#
# Usage — run from your existing repository root, AFTER update_android_play_v88.sh:
#   bash update_android_privacy_v88.sh --check     # dry run, writes nothing
#   bash update_android_privacy_v88.sh             # apply (default)
#   bash update_android_privacy_v88.sh --verify    # re-check later
#
# Then:
#   flutter test
#   git add -A && git commit -m "1.0.1+88: sync public privacy copies with in-app disclosure"
#   git push origin main
set -euo pipefail
command -v python3 >/dev/null || { echo 'Python 3 is required'; exit 1; }
python3 - "$@" <<'ANDPRIV88_PY'
import base64, gzip, hashlib, json, pathlib, subprocess, sys

PAYLOAD_HASH = '75e1ad78ac912c14d8639ed460693c66032ecdd4b561959653de34eecbbd9517'
PAYLOAD = """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
GR9TKzwqPanuwnA+XfWBzDuG10ITtk6q3q3sjZh0RJcqrpV5W621tV5C3DKHvsFd7WM38XtmD3M9E+1Tq+j5FzPTXJp7pd0HH6F/
Zm3R1Ln0vK93LdfhwhLOx3a6kVqH7HWgtAVniUr3fD7NjhgMxrPTXcDaBDDqtajb0j7bwMyNg2+gVaR2Qa7m+qi94xJuB+re0FX3
mD7hsDp7yZc6kmdd1UyUzH3Lemcj3Ssr8quNen5rpec8jBZI87knhzOmkpuZPHiusKxU12qn5WdqLG2Z3DHvDRjNpO6UyNwN14m4
HbBnkuO/yo3UXQ7pv1xUP5VYL7VHzhXxDtBGZrmkhsJ7XHLHIM+DFmlp38WsmqoZyZlTF4Pz/uOPf/39b8VNx+2v5TGML/+23CSz
8z8W+yy9ver48G69O3HFrrihW4mimT2rPDqVBxcKczZ7mFWd6MF+f4+javUxtMP4vZYk9Upcr7w74fsssZKbq46xXQ0Ty31/dGuP
YS1MZpWk9j7Db+26NXt4r74/2G71vW7xYQ/ue+I8VKN6zcZb7Fpk1evlq44/my2E/qDCK4WUs5F/+rO5On8kbWunJGLsdunyq2od
brAIvlfrgBqOPtL9L6T8nyOG9HT/0uz++bNtpWzlyYjuW2WpUneWDl+XpeuDbneTbAOY+mc+8m85cNdK2CTVpDJ+0YeMgmnTn29P
y5+rs7oK8FYbgfanKt1Eerj8vpz3XstXNI3L1fssk7Xx+9UZ0Jvyt0tIo9rMDrCO14fnt+A0a7IEPrUQnrqEZFnh6HxlqtWXazRp
9mIDTpt6fd8/qoO3xmn2fQ/36iGtrz4MvuPvmoJfHBkvozR7eG5+uzxvGtUXm6HvXl6Wz7wOen3Onh5FjtgJW36H4PvHCs6ZvU/o
inuEW8qrSUipWqvgbYtQG+8TjtZ+32cclXgB5JFicB7udLKH1DwfkUKsnq/ryovfWr6/nZhK1gCVf/5suh+EOJyB7B1/ShkZf/K5
f96vut6vut6vut6vut6vut6vut6vut6vut6vut6vut6vut6vut6vut6vut6vut6vut6vut6vut6vut6vut6vut6vut6vut6vut6v
ut6vut6vut6vut6vut6vut6vut6vut6vut6vut6vut6vut6vut6vut6vut6vut6vut6vut6vut6vut6vut6vut6vut6vut6vut6v
ut6vut6vut6vut6vut6vuv6/vOpapyYL3qp15ATkMd4p1HcJT0douX30vfrjj3/91/8C6OH/5flzAAA="""


def fail(message):
    print('STOP: ' + message, file=sys.stderr)
    sys.exit(1)


def digest(data):
    return hashlib.sha256(data).hexdigest()


args = sys.argv[1:]
if not args:
    args = ['--apply']
if len(args) != 1 or args[0] not in ['--check', '--apply', '--verify']:
    fail('Use no argument (apply), --check, --apply or --verify from the repository root.')
mode = args[0]

blob = ''.join(PAYLOAD.split())
if hashlib.sha256(blob.encode()).hexdigest() != PAYLOAD_HASH:
    fail('Payload is corrupted (checksum mismatch). Re-download the script.')
entries = json.loads(gzip.decompress(base64.b64decode(blob)))

try:
    root = pathlib.Path(subprocess.check_output(
        ['git', 'rev-parse', '--show-toplevel'], stderr=subprocess.DEVNULL
    ).decode().strip()).resolve()
except Exception:
    fail('Not inside a Git repository.')
if pathlib.Path.cwd().resolve() != root:
    fail('Run from your existing repository root; no files changed.')

if mode == '--verify':
    bad = [e['path'] for e in entries
           if (digest((root / e['path']).read_bytes()) if (root / e['path']).exists() else None) != e['after']]
    if bad:
        fail('Not in the +88 state:\n  ' + '\n  '.join(bad))
    print('VERIFIED: all %d payload hashes match.' % len(entries))
    sys.exit(0)

todo, problems = [], []
for e in entries:
    p = root / e['path']
    actual = digest(p.read_bytes()) if p.exists() else None
    if actual == e['after']:
        continue  # already patched
    if actual != e['before']:
        problems.append('  ' + e['path'] + ' is neither the +87 copy nor the patched copy')
        continue
    todo.append(e)
if problems:
    fail('These files are unexpected:\n' + '\n'.join(problems))

print('Privacy copy sync: %d file(s) need updates.' % len(todo))
if mode == '--check':
    for e in todo:
        print('  write   ' + e['path'])
    print('CHECK PASSED. No files written.')
    sys.exit(0)

for e in todo:
    p = root / e['path']
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(base64.b64decode(e['data']))
    print('  wrote   ' + e['path'])
print('')
print('Now: flutter test  (ad_free_review77_test + ui_theme82_test must pass)')
print('     git add -A && git commit -m "1.0.1+88: sync public privacy copies with in-app disclosure"')
ANDPRIV88_PY
