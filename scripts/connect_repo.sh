#!/usr/bin/env bash
# ============================================================
#  connect_repo.sh — connect the fresh MaxPlayer project to git
#
#  Usage:
#    bash scripts/connect_repo.sh <git-remote-url>
#    bash scripts/connect_repo.sh <git-remote-url> --force-overwrite
#
#  --force-overwrite : replaces the remote's ENTIRE old history
#    with this fresh tree (what "fully clean the repo" means).
#    The old code is gone from the remote after this. If you want
#    a safety copy, tag/zip the old repo BEFORE running this.
# ============================================================
set -euo pipefail

REMOTE_URL="${1:-}"
MODE="${2:-}"

[[ -n "$REMOTE_URL" ]] || {
  echo "Usage: bash scripts/connect_repo.sh <git-remote-url> [--force-overwrite]"
  echo "Example: bash scripts/connect_repo.sh https://github.com/you/maxplayer.git"
  exit 1
}

cd "$(dirname "$0")/.."   # project root

# sanity: secrets must never be committed
if git ls-files --others --exclude-standard 2>/dev/null | grep -qE '\.jks$|key\.properties$'; then
  echo "ABORT: a .jks or key.properties is present and not gitignored."
  echo "Check .gitignore before connecting a repo."
  exit 1
fi

[[ -d .git ]] || git init
git add -A
git commit -m "v0.1: fresh start - MPV(libmpv+FFmpeg) engine, dark UI, env-var signing" \
  || echo "(nothing new to commit)"
git branch -M main

if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$REMOTE_URL"
else
  git remote add origin "$REMOTE_URL"
fi

if [[ "$MODE" == "--force-overwrite" ]]; then
  echo ">> Force-pushing: old remote history will be REPLACED."
  git push --force -u origin main
else
  echo ">> Normal push (will fail if remote has old history; then re-run with --force-overwrite)."
  git push -u origin main
fi

echo "Repo connected: $REMOTE_URL (branch: main)"
