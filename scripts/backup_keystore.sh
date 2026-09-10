#!/usr/bin/env bash
# ============================================================
#  backup_keystore.sh — export & back up your Play signing key
#
#  Backs up:
#    • the .jks keystore file
#    • key.properties (contains store/key passwords + alias)
#    • SHA-1 / SHA-256 / MD5 fingerprints (Play Console needs these)
#    • cm_keystore_base64.txt  → paste into Codemagic CM_KEYSTORE
#
#  Run from anywhere:   bash scripts/backup_keystore.sh [path/to.jks]
#  Output: ~/keystore-backup-<timestamp>/  + a tar.gz of it
# ============================================================
set -euo pipefail

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$HOME/keystore-backup-$STAMP"
mkdir -p "$OUT_DIR"

echo "== Keystore backup =="

# ---- 1. Locate the keystore ------------------------------------------
JKS="${1:-}"
KEY_PROPS=""

find_key_properties() {
  local candidates=(
    "android/key.properties"
    "../android/key.properties"
    "$HOME/android/key.properties"
  )
  for c in "${candidates[@]}"; do
    [[ -f "$c" ]] && { KEY_PROPS="$(cd "$(dirname "$c")" && pwd)/$(basename "$c")"; return 0; }
  done
  return 1
}

if [[ -z "$JKS" ]]; then
  if find_key_properties; then
    echo "Found key.properties: $KEY_PROPS"
    STORE_FILE_PROP="$(grep -E '^storeFile=' "$KEY_PROPS" | cut -d= -f2- || true)"
    if [[ -n "${STORE_FILE_PROP:-}" ]]; then
      CAND="$(dirname "$KEY_PROPS")/app/$STORE_FILE_PROP"
      [[ -f "$CAND" ]] && JKS="$CAND"
    fi
  fi
fi

if [[ -z "$JKS" ]]; then
  # last resort: common locations
  for c in android/app/*.jks android/*.jks "$HOME"/*.jks; do
    [[ -f "$c" ]] && { JKS="$c"; break; }
  done
fi

[[ -f "${JKS:-}" ]] || {
  echo "ERROR: no .jks found. Pass it explicitly:"
  echo "  bash scripts/backup_keystore.sh /full/path/upload-keystore.jks"
  exit 1
}
JKS="$(cd "$(dirname "$JKS")" && pwd)/$(basename "$JKS")"
echo "Keystore: $JKS"

# ---- 2. Pull credentials (never echoed) -------------------------------
STORE_PASS=""; KEY_ALIAS=""; KEY_PASS=""
if [[ -n "$KEY_PROPS" ]]; then
  STORE_PASS="$(grep -E '^storePassword=' "$KEY_PROPS" | cut -d= -f2- || true)"
  KEY_ALIAS="$(grep -E '^keyAlias='       "$KEY_PROPS" | cut -d= -f2- || true)"
  KEY_PASS="$(grep -E '^keyPassword='     "$KEY_PROPS" | cut -d= -f2- || true)"
fi
if [[ -z "$STORE_PASS" ]]; then
  read -rsp "Keystore store password: " STORE_PASS; echo
fi
if [[ -z "$KEY_ALIAS" ]]; then
  read -rp  "Key alias: " KEY_ALIAS
fi

# ---- 3. Verify the keystore + capture fingerprints ---------------------
echo "Verifying keystore integrity..."
if command -v keytool >/dev/null 2>&1; then
  keytool -list -v -keystore "$JKS" -storepass "$STORE_PASS" -alias "$KEY_ALIAS" \
    > "$OUT_DIR/keytool_listing.txt" 2>/dev/null || {
      echo "ERROR: keytool rejected the keystore/password/alias — backup aborted."
      exit 1
    }
  grep -E "SHA1:|SHA256:|MD5:" "$OUT_DIR/keytool_listing.txt" \
    > "$OUT_DIR/fingerprints.txt" || true
  echo "Fingerprints saved to fingerprints.txt"
else
  echo "WARNING: keytool not found — skipping verification & fingerprints"
fi

# ---- 4. Copy artifacts -------------------------------------------------
cp "$JKS" "$OUT_DIR/upload-keystore.jks"
[[ -n "$KEY_PROPS" ]] && cp "$KEY_PROPS" "$OUT_DIR/key.properties" || {
  cat > "$OUT_DIR/key.properties" <<EOF
storePassword=$STORE_PASS
keyPassword=$KEY_PASS
keyAlias=$KEY_ALIAS
storeFile=upload-keystore.jks
EOF
}

# base64 for Codemagic CM_KEYSTORE env var
base64 -i "$JKS" > "$OUT_DIR/cm_keystore_base64.txt" 2>/dev/null \
  || base64 "$JKS" > "$OUT_DIR/cm_keystore_base64.txt"
chmod 600 "$OUT_DIR"/*

cat > "$OUT_DIR/README_RESTORE.txt" <<'EOF'
RESTORE INSTRUCTIONS
====================
1. Put upload-keystore.jks into:  <project>/android/app/upload-keystore.jks
2. Put key.properties      into:  <project>/android/key.properties
   (keys: storePassword, keyPassword, keyAlias, storeFile)
3. Codemagic: upload these env vars in group "keystore_credentials":
     CM_KEYSTORE          = contents of cm_keystore_base64.txt
     CM_KEYSTORE_PASSWORD = storePassword
     CM_KEY_ALIAS         = keyAlias
     CM_KEY_ALIAS_PASSWORD= keyPassword
4. Keep fingerprints.txt — Play Console app signing page needs the
   SHA-1 / SHA-256 if you ever re-enroll or add API credentials.
NEVER commit the .jks or key.properties to git. Store this folder
(or the tar.gz) in at least TWO safe places (drive + offline).
EOF

# ---- 5. Pack it ---------------------------------------------------------
TARBALL="$HOME/keystore-backup-$STAMP.tar.gz"
tar -czf "$TARBALL" -C "$HOME" "$(basename "$OUT_DIR")"
chmod 600 "$TARBALL"

echo
echo "DONE."
echo "  Folder : $OUT_DIR"
echo "  Tarball: $TARBALL"
echo
echo "Next:"
echo "  1. Copy cm_keystore_base64.txt content into Codemagic CM_KEYSTORE"
echo "  2. Move the tarball to cloud drive + an offline disk"
echo "  3. Test restore once: keytool -list -keystore <restored.jks>"
