#!/usr/bin/env bash
# Blobless clone: all commits and trees, file contents (blobs) fetched lazily on demand.
# Keeps full history (needed: some API introductions predate v5.10) at a fraction of a full clone's size.
set -euo pipefail
LINUX="${LINUX:-/linux/linux}"
URL="https://github.com/torvalds/linux.git"

if [ -d "$LINUX/.git" ]; then
  echo "Already cloned at $LINUX; fetching updates."
  git -C "$LINUX" fetch --tags origin
else
  mkdir -p "$(dirname "$LINUX")"
  git clone --filter=blob:none "$URL" "$LINUX"
fi
git -C "$LINUX" log -1 --format='HEAD %H %cd' --date=iso
