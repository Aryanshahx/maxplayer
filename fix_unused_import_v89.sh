#!/usr/bin/env bash
# RunX Player 1.0.1+89 — one-line analyzer fix.
#
# `flutter analyze` reports:
#   warning • Unused import: 'dart:io' • test/vpn_gestures86_test.dart:1:8
#
# The VPN screen test that used File(...) was removed with the VPN feature in
# update_android_vpn_removal_v89.sh, so the dart:io import in that test file is
# now dead. This script drops only that import line; nothing else changes.
#
# Usage — run from your existing repository root:
#   bash fix_unused_import_v89.sh --check
#   bash fix_unused_import_v89.sh
#   bash fix_unused_import_v89.sh --verify
#
# Then:
#   flutter analyze --no-fatal-infos && flutter test
set -euo pipefail
python3 - "$@" <<'ANDFIX89_PY'
import base64, hashlib, pathlib, subprocess, sys

rel = 'test/vpn_gestures86_test.dart'
PAYLOAD_HASH = '4553302f808f6a3b3e160d829ed43cc8747e15142cce0d74d9c7a27ec711d154'
PAYLOAD = """aW1wb3J0ICdwYWNrYWdlOmZsdXR0ZXIvbWF0ZXJpYWwuZGFydCc7CmltcG9ydCAncGFja2FnZTpmbHV0dGVyX3Rlc3QvZmx1dHRl
cl90ZXN0LmRhcnQnOwppbXBvcnQgJ3BhY2thZ2U6bWF4cGxheWVyL3RoZW1lLmRhcnQnOwppbXBvcnQgJ3BhY2thZ2U6bWF4cGxh
eWVyL3dpZGdldHMvZ2VzdHVyZV9pbGx1c3RyYXRpb25zLmRhcnQnOwoKZG91YmxlIGNvbnRyYXN0KENvbG9yIGEsIENvbG9yIGIp
IHsKICBmaW5hbCB4ID0gYS5jb21wdXRlTHVtaW5hbmNlKCksIHkgPSBiLmNvbXB1dGVMdW1pbmFuY2UoKTsKICByZXR1cm4gKCh4
ID4geSA/IHggOiB5KSArIC4wNSkgLyAoKHggPCB5ID8geCA6IHkpICsgLjA1KTsKfQoKdm9pZCBtYWluKCkgewogIGZvciAoZmlu
YWwgYnJpZ2h0bmVzcyBpbiBCcmlnaHRuZXNzLnZhbHVlcykgewogICAgdGVzdCgnZ2VzdHVyZSBpbmsgYW5kIGJhZGdlcyBjb250
cmFzdCBpbiAkYnJpZ2h0bmVzcycsICgpIHsKICAgICAgZm9yIChmaW5hbCBhY2NlbnQgaW4gWwogICAgICAgIENvbG9ycy53aGl0
ZSwKICAgICAgICBDb2xvcnMuYmxhY2ssCiAgICAgICAgQ29sb3JzLnJlZCwKICAgICAgICBDb2xvcnMuYmx1ZSwKICAgICAgICBD
b2xvcnMuYW1iZXIsCiAgICAgIF0pIHsKICAgICAgICBmaW5hbCBwID0gR2VzdHVyZURpYWdyYW1QYWxldHRlLmZyb21UaGVtZSgK
ICAgICAgICAgIGJ1aWxkQXBwVGhlbWUoYWNjZW50OiBhY2NlbnQsIGJyaWdodG5lc3M6IGJyaWdodG5lc3MpLAogICAgICAgICk7
CiAgICAgICAgZm9yIChmaW5hbCBiZyBpbiBbcC5zY3JlZW5TdGFydCwgcC5zY3JlZW5FbmRdKSB7CiAgICAgICAgICBleHBlY3Qo
Y29udHJhc3QocC5tdXRlZCwgYmcpLCBncmVhdGVyVGhhbk9yRXF1YWxUbyg0LjUpKTsKICAgICAgICAgIGV4cGVjdChjb250cmFz
dChwLmFjY2VudCwgYmcpLCBncmVhdGVyVGhhbk9yRXF1YWxUbyg0LjUpKTsKICAgICAgICB9CiAgICAgICAgZXhwZWN0KGNvbnRy
YXN0KHAub25BY2NlbnQsIHAuYWNjZW50KSwgZ3JlYXRlclRoYW5PckVxdWFsVG8oNC41KSk7CiAgICAgIH0KICAgIH0pOwogICAg
dGVzdFdpZGdldHMoCiAgICAgICdhbGwgZ2VzdHVyZSBpbGx1c3RyYXRpb25zIHJlbmRlciBpbiAkYnJpZ2h0bmVzcyB3aXRob3V0
IGVycm9ycycsCiAgICAgICh0ZXN0ZXIpIGFzeW5jIHsKICAgICAgICBhd2FpdCB0ZXN0ZXIucHVtcFdpZGdldCgKICAgICAgICAg
IE1hdGVyaWFsQXBwKAogICAgICAgICAgICB0aGVtZTogYnVpbGRBcHBUaGVtZShicmlnaHRuZXNzOiBicmlnaHRuZXNzKSwKICAg
ICAgICAgICAgaG9tZTogU2NhZmZvbGQoCiAgICAgICAgICAgICAgYm9keTogTGlzdFZpZXcoCiAgICAgICAgICAgICAgICBjaGls
ZHJlbjogWwogICAgICAgICAgICAgICAgICBmb3IgKGZpbmFsIGtpbmQgaW4gR2VzdHVyZUtpbmQudmFsdWVzKQogICAgICAgICAg
ICAgICAgICAgIEdlc3R1cmVJbGx1c3RyYXRpb24oa2luZDoga2luZCwgaGVpZ2h0OiA1OCksCiAgICAgICAgICAgICAgICBdLAog
ICAgICAgICAgICAgICksCiAgICAgICAgICAgICksCiAgICAgICAgICApLAogICAgICAgICk7CiAgICAgICAgYXdhaXQgdGVzdGVy
LnB1bXAoKTsKICAgICAgICBleHBlY3QodGVzdGVyLnRha2VFeGNlcHRpb24oKSwgaXNOdWxsKTsKICAgICAgfSwKICAgICk7CiAg
fQogIHRlc3RXaWRnZXRzKAogICAgJ3RoZW1lIGNoYW5nZSByZXBhaW50cyB0aGUgc2FtZSBnZXN0dXJlIGV2ZW4gd2l0aCBpZGVu
dGljYWwgZ2xvYmFsIGFjY2VudCcsCiAgICAodGVzdGVyKSBhc3luYyB7CiAgICAgIGNvbnN0IGtleSA9IFZhbHVlS2V5KCdkaWFn
cmFtJyk7CiAgICAgIEZ1dHVyZTxDdXN0b21QYWludGVyPiBzaG93KEJyaWdodG5lc3MgYnJpZ2h0bmVzcykgYXN5bmMgewogICAg
ICAgIGF3YWl0IHRlc3Rlci5wdW1wV2lkZ2V0KAogICAgICAgICAgTWF0ZXJpYWxBcHAoCiAgICAgICAgICAgIHRoZW1lOiBidWls
ZEFwcFRoZW1lKGJyaWdodG5lc3M6IGJyaWdodG5lc3MpLAogICAgICAgICAgICBob21lOiBjb25zdCBTY2FmZm9sZCgKICAgICAg
ICAgICAgICBib2R5OiBHZXN0dXJlSWxsdXN0cmF0aW9uKGtleToga2V5LCBraW5kOiBHZXN0dXJlS2luZC5zd2lwZVNlZWspLAog
ICAgICAgICAgICApLAogICAgICAgICAgKSwKICAgICAgICApOwogICAgICAgIGF3YWl0IHRlc3Rlci5wdW1wQW5kU2V0dGxlKCk7
CiAgICAgICAgcmV0dXJuIHRlc3RlcgogICAgICAgICAgICAud2lkZ2V0PEN1c3RvbVBhaW50PigKICAgICAgICAgICAgICBmaW5k
LmRlc2NlbmRhbnQoCiAgICAgICAgICAgICAgICBvZjogZmluZC5ieUtleShrZXkpLAogICAgICAgICAgICAgICAgbWF0Y2hpbmc6
IGZpbmQuYnlUeXBlKEN1c3RvbVBhaW50KSwKICAgICAgICAgICAgICApLAogICAgICAgICAgICApCiAgICAgICAgICAgIC5wYWlu
dGVyITsKICAgICAgfQoKICAgICAgZmluYWwgZGFyayA9IGF3YWl0IHNob3coQnJpZ2h0bmVzcy5kYXJrKSwKICAgICAgICAgIGxp
Z2h0ID0gYXdhaXQgc2hvdyhCcmlnaHRuZXNzLmxpZ2h0KTsKICAgICAgZXhwZWN0KGxpZ2h0LnNob3VsZFJlcGFpbnQoZGFyayks
IGlzVHJ1ZSk7CiAgICB9LAogICk7Cn0K"""


def fail(m):
    print('STOP: ' + m, file=sys.stderr)
    sys.exit(1)


args = sys.argv[1:] or ['--apply']
if len(args) != 1 or args[0] not in ['--check', '--apply', '--verify']:
    fail('Use no argument (apply), --check or --verify from the repository root.')
mode = args[0]

blob = ''.join(PAYLOAD.split())
if hashlib.sha256(blob.encode()).hexdigest() != PAYLOAD_HASH:
    fail('Payload is corrupted (checksum mismatch). Re-download the script.')
wanted = base64.b64decode(blob)

try:
    root = pathlib.Path(subprocess.check_output(
        ['git', 'rev-parse', '--show-toplevel'], stderr=subprocess.DEVNULL
    ).decode().strip()).resolve()
except Exception:
    fail('Not inside a Git repository.')
if pathlib.Path.cwd().resolve() != root:
    fail('Run from your existing repository root; no files changed.')

p = root / rel
if not p.is_file():
    fail('%s not found — run update_android_vpn_removal_v89.sh first.' % rel)
current = p.read_bytes()
sha = lambda b: hashlib.sha256(b).hexdigest()

if mode == '--verify':
    if sha(current) != sha(wanted):
        fail('%s is not in the fixed state.' % rel)
    print('VERIFIED: %s matches the fixed file.' % rel)
    sys.exit(0)

if sha(current) == sha(wanted):
    print('Already fixed; nothing to do.')
    sys.exit(0)

text = current.decode()
needle = "import 'dart:io';\n"
if text.count(needle) != 1:
    fail('Expected exactly one dart:io import in %s (found %d).' % (rel, text.count(needle)))
if text.replace(needle, '', 1).encode() != wanted:
    fail('%s does not look like the expected +88/+89 file. Do not force this fix.' % rel)

if mode == '--check':
    print('Would remove the unused "import \'dart:io\';" line from ' + rel)
    print('CHECK PASSED. No files written.')
    sys.exit(0)

p.write_bytes(wanted)
print('Fixed: removed the unused dart:io import from ' + rel)
print('Next: flutter analyze --no-fatal-infos && flutter test')
ANDFIX89_PY
