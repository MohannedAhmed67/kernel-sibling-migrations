# Sibling migrations as free supervision for kernel driver updates — a feasibility study

A small, reproducible study extending *LLM-Driven Kernel Evolution: Automating Driver Updates in Linux*
(Kharlamova et al., arXiv:2511.18924; DRIVEBENCH / AUTODRIVER).

**Idea.** When an upstream kernel API changes, developers convert many in-tree drivers to the new API.
Those earlier "sibling" conversions are reviewed, real examples of the correct change. We test:

- **H1 (coverage):** for most API-migration targets, earlier sibling migrations exist in git history.
- **H2 (rule synthesis):** a Coccinelle semantic patch written *only* from earlier siblings migrates
  held-out target drivers correctly and the result compiles.
- **H3 (optional):** LLM + sibling exemplars vs LLM alone on cases rules cannot handle.

**Leakage rule.** A rule used on a target may only be derived from sibling commits that touch
*different* files and were committed *before* the target's own fix.

## Status

| Phase | What | Status |
|---|---|---|
| 0 | Environment (pinned Docker toolchain, kernel clone) | done |
| 1 | Find DRIVEBENCH artifacts / build case list | — |
| 2 | H1 sibling coverage | — |
| 3 | H2 Coccinelle rules from siblings | — |

## Reproduce

Requirements: Docker (Linux, macOS or Windows). Everything runs inside a container pinned to
`ubuntu:22.04` by digest (GCC 11.4, Coccinelle 1.1.1). The kernel tree lives in a Docker volume,
which is case-sensitive even on macOS/Windows hosts.

```sh
docker compose build                       # toolchain image
docker compose run --rm dev make clone     # blobless clone of torvalds/linux into volume drivebench-linux
docker compose run --rm dev make env       # writes results/env.txt
```

## Layout

```
Dockerfile, compose.yaml   pinned toolchain
Makefile                   one target per phase (run inside the container)
scripts/                   all code that produces numbers
results/                   generated outputs (every number in the reports comes from here)
```
