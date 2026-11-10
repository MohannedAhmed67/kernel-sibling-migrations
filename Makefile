# Run every target inside the container:  docker compose run --rm dev make <target>
LINUX ?= /linux/linux

.PHONY: env clone blob-probe prefetch mine candidates api-events select h1 verify-h1 h2 h2-final

env:            ## Phase 0: record toolchain + kernel-clone facts to results/env.txt
	mkdir -p results && bash scripts/env_check.sh | tee results/env.txt

clone:          ## Blobless clone of torvalds/linux (full commit history, file contents on demand)
	bash scripts/clone_linux.sh

blob-probe:     ## Count blobs for drivers/ + include/ in v5.10..v6.10 not yet downloaded
	mkdir -p results && bash scripts/blob_probe.sh | tee results/blob_probe.txt

prefetch:       ## Batch-download v5.10..v6.10 file contents (drivers/include first), 5 GB growth cap
	bash scripts/prefetch_blobs.sh

mine:           ## Phase 1: one pass over v5.10..v6.10 history -> data/mined_hits.csv (candidates only)
	python3 scripts/mine_history.py

candidates:     ## Phase 1: candidate conversions + per-migration summary from data/mined_hits.csv
	python3 scripts/build_cases.py
	python3 scripts/sample_for_verification.py

select:         ## Phase 1: apply pre-registered rule to stored verdicts -> data/cases.csv, data/conversions.csv
	python3 scripts/select_cases.py

h1:             ## Phase 2: sibling coverage -> results/h1_coverage.csv, h1_summary.csv, h1_coverage.png
	python3 scripts/h1_coverage.py

verify-h1:      ## Phase 2 check: git merge-base recount + recall spot check -> results/h1_verify.txt
	python3 scripts/verify_h1.py

h2:             ## Phase 3: split, apply rules/{manual,spinfer}, compare, compile, merge stored reviews -> results/h2_*
	python3 scripts/h2_split.py
	python3 scripts/h2_eval.py
	python3 scripts/h2_final.py

h2-final:       ## Phase 3: rebuild final tables/chart from results/h2_rules.csv + results/h2_review.csv only
	python3 scripts/h2_final.py

api-events:     ## Phase 1: when each new API appeared / old API was removed (include/ history)
	python3 scripts/api_events.py
