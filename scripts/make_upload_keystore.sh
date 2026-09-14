#!/usr/bin/env bash
# ============================================================
#  make_upload_keystore.sh — create the Play Store UPLOAD keystore
#
#  The upload key signs the .aab you give to Play. With Play App
#  Signing, Google stores the app-signing key, so losing the upload
#  key is recoverable through a key reset. KEEP THIS KEY SAFE ANYWAY.
#
#  Usage (from the repo root):
#    bash scripts/make_upload_keystore.sh
#
#  Optional env overrides (otherwise you are prompted):
#    KEYSTORE_PASSWORD, KEY_PASSWORD, KEY_ALIAS, KEY_DNAME
#
#  Outputs:
#    android/app/upload-keystore.jks   (gitignored - NEVER commit)
#    android/key.properties             (gitignored - NEVER commit)
#    terminal: SHA1/SHA256 fingerprints + base64 for the CI secrets
# ============================================================
set -euo pipefail

cd "$(dirname "$0")/.."   # repo root

JKS="android/app/upload-keystore.jks"
PROPS="android/key.properties"
ALIAS="${KEY_ALIAS:-upload}"
DNAME="${KEY_DNAME:-CN=Max Player, OU=Hyper Tech Labs, O=Hyper Tech Labs, C=IN}"

if ! command -v keytool >/dev/null 2>&1; then
  echo "ERROR: keytool not found. Install a JDK (Java 17) first." >&2
  exit 1
fi

# ---- passwords ----------------------------------------------------------
read_secret() {
  local var="$1" prompt="$2"
  if [[ -n "${!var:-}" ]]; then return 0; fi
  local first second
  read -rsp "$prompt: " first; echo
  read -rsp "  (again): " second; echo
  if [[ "$first" != "$second" ]]; then
    echo "ERROR: entries did not match." >&2
    exit 1
  fi
  export "$var=$first"
}

if [[ -f "$JKS" ]]; then
  echo "ERROR: $JKS already exists - refusing to overwrite." >&2
  echo "Move or back it up first (scripts/backup_keystore.sh)." >&2
  exit 1
fi

read_secret KEYSTORE_PASSWORD "Keystore store password"
read_secret KEY_PASSWORD      "Key password"

# ---- generate -----------------------------------------------------------
mkdir -p android/app
keytool -genkeypair -v \
  -keystore "$JKS" \
  -alias "$ALIAS" \
  -keyalg RSA -keysize 2048 -validity 9125 \
  -storepass "$KEYSTORE_PASSWORD" \
  -keypass "$KEY_PASSWORD" \
  -dname "$DNAME"

cat > "$PROPS" <<EOF
storePassword=$KEYSTORE_PASSWORD
keyPassword=$KEY_PASSWORD
keyAlias=$ALIAS
storeFile=upload-keystore.jks
EOF

chmod 600 "$JKS" "$PROPS"

# ---- fingerprints ---------------------------------------------------------
echo
echo "================================================================"
echo "  KEYSTORE CREATED"
echo "================================================================"
echo "  file : $JKS"
echo "  props: $PROPS   (gitignored)"
echo
echo "  Fingerprints (Play Console 'App signing' may ask for these):"
keytool -list -v -keystore "$JKS" -alias "$ALIAS" \
  -storepass "$KEYSTORE_PASSWORD" 2>/dev/null \
  | grep -E "SHA1:|SHA256:|SHA1withRSA" || true
echo
echo "  GitHub Actions / Codemagic secrets (copy these into repository secrets):"
echo "    CM_KEYSTORE   ="
base64 < "$JKS" | tr -d '\n' | fold -w 120
echo
echo "    CM_KEYSTORE_PASSWORD   = $KEYSTORE_PASSWORD"
echo "    CM_KEY_ALIAS           = $ALIAS"
echo "    CM_KEY_ALIAS_PASSWORD  = $KEY_PASSWORD"
echo
echo "  NEVER commit the .jks or key.properties to git."
echo "  Back them up: bash scripts/backup_keystore.sh"
echo "================================================================"
