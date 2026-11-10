# Run every target inside the container:  docker compose run --rm dev make <target>
LINUX ?= /linux/linux

.PHONY: env clone blob-probe

env:            ## Phase 0: record toolchain + kernel-clone facts to results/env.txt
	mkdir -p results && bash scripts/env_check.sh | tee results/env.txt

clone:          ## Blobless clone of torvalds/linux (full commit history, file contents on demand)
	bash scripts/clone_linux.sh

blob-probe:     ## Count blobs for drivers/ + include/ in v5.10..v6.10 not yet downloaded
	mkdir -p results && bash scripts/blob_probe.sh | tee results/blob_probe.txt
