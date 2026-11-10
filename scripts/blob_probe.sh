#!/usr/bin/env bash
# How many file-content objects (blobs) for drivers/ and include/ in v5.10..v6.10 are NOT yet
# downloaded in the blobless clone? Local only: --missing=print lists them without fetching.
set -euo pipefail
cd "${LINUX:-/linux/linux}"
git rev-list --objects --missing=print v5.10..v6.10 -- drivers include > /tmp/objs.txt
echo "range: v5.10..v6.10, paths: drivers include"
echo "objects already present: $(grep -vc '^?' /tmp/objs.txt)"
echo "objects missing (not downloaded): $(grep -c '^?' /tmp/objs.txt)"
