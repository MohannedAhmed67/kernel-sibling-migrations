# Sibling migrations as free supervision for Linux driver updates — a reproducible pilot

A small, reproducible study related to *LLM-Driven Kernel Evolution: Automating Driver Updates in Linux*
(Kharlamova et al., arXiv:2511.18924; DRIVEBENCH / AUTODRIVER).

**Results:** see [`RESULTS.md`](RESULTS.md) (tables, limitations, connection to the paper). Charts:
`results/h1_coverage.png`, `results/h2_rules.png`.

**Idea.** When an upstream kernel API changes, developers convert many in-tree drivers to the new API. Those earlier
"sibling" conversions are real, reviewed examples of the correct change. We test:

- **H1 (existence):** for API-migration targets, earlier sibling migrations exist in git history.
- **H2 (rule synthesis):** a Coccinelle semantic patch derived *only* from earlier siblings migrates held-out target
  drivers correctly, and the result compiles. Rules are written by an LLM agent with access limited to the siblings,
  and inferred by Spinfer (USENIX ATC 2020).
- **H3 (not run):** LLM + sibling exemplars vs LLM alone on the cases rules cannot handle.

**Leakage rule.** A rule used on a target may only be derived from sibling conversions in *different* files that were
committed *before* the target patch was written.

## Status

| Phase | What | Status |
|---|---|---|
| 0 | Environment (pinned Docker toolchain, kernel clone) | done |
| 1 | DRIVEBENCH artifacts are not public (`docs/artifact_search.md`); our own case list (`docs/phase1_cases.md`) | done |
| 2 | H1 sibling existence (`docs/phase2_h1.md`) | done |
| 3 | H2 Coccinelle rules from siblings (`docs/phase3_h2.md`) | done |
| 4 | H3 LLM with/without sibling exemplars | not run |

## Reproduce

Requirements: Docker (Linux, macOS or Windows). Everything runs inside a container pinned to `ubuntu:22.04` by digest
(GCC 11.4, Coccinelle 1.1.1; `results/env.txt`). The kernel tree lives in a Docker volume, which is case-sensitive even
on macOS/Windows hosts.

```sh
docker compose build                       # toolchain image
docker compose run --rm dev make clone     # blobless clone of torvalds/linux into volume drivebench-linux
docker compose run --rm dev make env       # writes results/env.txt
docker compose run --rm dev make prefetch  # batch-download the v5.10..v6.10 file contents (results/blob_probe.txt), 5 GB cap

# Phase 1: candidate migrations -> verified case list
docker compose run --rm dev make mine candidates api-events   # data/mined_hits.csv, migration_summary.csv, verify_sample.csv, api_events.csv
docker compose run --rm dev make select                       # applies docs/selection_rule.md to data/verification.csv

# Phase 2: H1
docker compose run --rm dev make h1 verify-h1                 # results/h1_*.csv, h1_coverage.png, h1_verify.txt

# Phase 3: H2
docker build -f docker/spinfer.Dockerfile -t drivebench-spinfer:c47696a docker   # Spinfer (pinned)
bash scripts/h2_spinfer.sh                                    # host: infer rules/spinfer/*.cocci (+ toolchain record)
docker compose run --rm dev make h2                           # results/h2_*.csv, results/h2_rules.png
```

Two steps used LLM reviewers, and their verdicts are stored so that the rest reproduces exactly without them:
`data/verification.csv` (candidate verification, Phase 1; `make select` rebuilds `data/cases.csv`) and
`results/h2_review.csv` (semantic review of non-exact H2 outputs; `make h2-final` rebuilds the final H2 tables).
The H2 rule-writing agents' isolation audit is in `results/h2_isolation_audit.txt`.

## Layout

```
Dockerfile, compose.yaml   pinned toolchain           docker/spinfer.Dockerfile  pinned Spinfer
Makefile                   one target per phase (run inside the container)
scripts/                   all code that produces numbers
data/                      mined candidates, verified case list, H2 split
rules/manual/, rules/spinfer/   sibling-derived Coccinelle rules (manual = written by an isolated LLM agent)
results/                   generated outputs (every number in the reports comes from here)
docs/                      method, caveats and related work per phase
```

## License
Code, rules and documentation: MIT (see `LICENSE`). Data files contain Linux commit identifiers, subjects and file
paths taken from the public Linux kernel history.
