#!/usr/bin/env bash
# Revert the pushed v98 commit (voice control, picture quality, gentle
# sleep fade, Cast/Screenshot removal) and return the tree to clean v97.
# Uses `git revert` - safe for pushed history, no force-push needed.
#
# Run from the repo root:  bash revert_v98.sh
set -euo pipefail
cd "$(dirname "$0")"

# 0. Guard: refuse to touch a dirty tree (protects any uncommitted work).
# Untracked files (like this script itself) are ignored - only tracked
# modifications can block or corrupt a revert.
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "STOP: tracked files have uncommitted changes - commit or stash them first:"
  git status --short
  exit 1
fi

# 1. Find the v98 commit (must exist locally - run git pull first if missing).
V98=$(git log --format=%H --grep="v98: voice control" -1 || true)
if [ -z "$V98" ]; then
  echo "STOP: v98 commit not found locally. Run: git pull"
  exit 1
fi
echo "Reverting: $(git log --oneline -1 "$V98")"

# 2. Revert (new commit that undoes v98; history stays intact).
git revert --no-edit "$V98"

echo "--- result ---"
git log --oneline -3
git status --short
echo "Tree vs pre-v98 state (empty output below = perfect restore):"
git diff "$V98^" --stat
echo "DONE - now run: flutter analyze && flutter test"
