#!/usr/bin/env bash
# Batch-download the file contents (blobs) missing from the blobless clone for v5.10..v6.10,
# so history searches (git log -S/-G) run locally instead of fetching one object at a time.
# Priority: drivers/ + include/ first, then the rest of the tree. Hard stop at CAP_MB of growth.
set -euo pipefail
cd "${LINUX:-/linux/linux}"
RANGE="${RANGE:-v5.10..v6.10}"
CAP_MB="${CAP_MB:-5120}"
CHUNK="${CHUNK:-40000}"
G="git -c gc.auto=0 -c maintenance.auto=false -c fetch.negotiationAlgorithm=noop"

start_mb=$(du -sm .git | cut -f1)
echo "start .git MB=$start_mb cap_growth_MB=$CAP_MB range=$RANGE"

fetch_list() {  # fetch_list <label> <pathspec...>   (label "boundary" = trees of the range's base commits)
  local label="$1"; shift
  if [ "$label" = boundary ]; then
    # Files unchanged since the range's base commits (e.g. v5.10 itself) are not "in" the range,
    # but diffs need them the first time a commit in the range touches them.
    git rev-list --boundary "$RANGE" | sed -n 's/^-//p' \
      | git rev-list --objects --missing=print --no-walk --stdin -- "$@" | sed -n 's/^?//p' | sort -u > /tmp/missing.txt
  else
    git rev-list --objects --missing=print "$RANGE" -- "$@" | sed -n 's/^?//p' | sort -u > /tmp/missing.txt
  fi
  local n; n=$(wc -l < /tmp/missing.txt)
  echo "[$label] missing blobs: $n"
  [ "$n" -eq 0 ] && return 0
  split -l "$CHUNK" /tmp/missing.txt /tmp/chunk_
  for f in /tmp/chunk_*; do
    $G fetch --no-tags --no-write-fetch-head --recurse-submodules=no --filter=blob:none --quiet --stdin origin < "$f"
    rm -f "$f"
    local grown=$(( $(du -sm .git | cut -f1) - start_mb ))
    echo "[$label] chunk done, growth MB=$grown"
    if [ "$grown" -ge "$CAP_MB" ]; then echo "CAP REACHED: stopping"; rm -f /tmp/chunk_*; exit 3; fi
  done
}

fetch_list priority drivers include
fetch_list rest .
fetch_list boundary drivers sound include
echo "remaining missing in range (whole tree): $(git rev-list --objects --missing=print "$RANGE" | grep -c '^?' || true)"
echo "end .git MB=$(du -sm .git | cut -f1)"
echo "DONE"
