# Results: sibling migrations as free supervision for Linux driver updates

A small, reproducible pilot study. Every number here is produced by a script or stored data file in this repository
(see README for one command per phase). Numbers that rest on stored LLM review verdicts are marked as such.

## Summary

When a Linux kernel API changes, many in-tree drivers are converted one after another. We asked whether these earlier
**sibling migrations** could serve as free, reviewed examples for updating the next driver. This relates to the
"kernel-aware retrieval" that the AUTODRIVER paper (arXiv:2511.18924) lists as future work. We mined Linux
v5.10..v6.10 and kept 27 API migrations that were each performed in at least 3 commits (8,818 candidate driver-file
conversions). This is **not** a sample of driver updates in general. Within these migrations, an earlier sibling
existed in the target's git history for **96.9%** of conversions (pre-registered view). It was already in a **released
kernel when the target patch was written** for **71.7%** (exploratory view, defined after seeing the data), and for
**89.5%** in the 7 migrations whose old API was removed. Requiring a different author lowers the share to 48.2%, because
several migrations were swept by one person in a burst. In a chronological hold-out on 5 hand-picked migrations, a
Coccinelle rule written by an **LLM agent whose file access was limited to the 20 earliest sibling conversions** matched
the human fix, or was judged equivalent or an acceptable alternative by LLM reviewers, and compiled for **81 of 94**
buildable held-out drivers. Spinfer, run with default settings on the same examples, managed **26 of 94**. It inferred no
rule for the two migrations that change struct initializers; on the 3 migrations where it did, the comparison is 26/55 vs
43/55. **11** Spinfer outputs and **1** LLM-written output compiled but were judged to change behaviour, which shows that
compile success needs a semantic check alongside it. The residual failures are migrations with many API variants,
decisions that need understanding of the code, and multi-file changes. That is where LLM repair with sibling exemplars
(H3, **not run**) would be tested next.

## Data (Phase 1)
- DRIVEBENCH / AUTODRIVER artifacts are **not public** (`docs/artifact_search.md`), so we built our own case list.
- One pass over all non-merge commits in v5.10..v6.10 touching `drivers/` and `sound/`, with 35 candidate
  migrations defined by old/new-API line patterns. 32 had candidates: **9,779 candidate conversions**.
- Verification: 223 sampled candidates, each judged by two independent LLM reviewers against the real diff
  (1 disagreement, settled by a tie-breaker). Inclusion rule: precision >= 0.85 and >= 3 commits.
- **27 of 32 migrations included: 8,818 candidate conversions, covering 8,542 (migration, file) pairs in 6,241
  distinct files, from 5,175 commits** (`data/cases.csv`, `data/conversions.csv`, `data/cases_stats.txt`).
- Excluded: 2 migrations done in a single tree-wide commit (`class_create_owner`, `vm_flags_set`) and 3 with noisy
  candidates (`napi_weight` 3/8, `i2c_remove_void` 5/8, `timer_delete` 2/3 verified).

## H1 — do earlier siblings exist? (`results/h1_summary.csv`, `results/h1_coverage.png`)

Population: the 27 migrations above, each performed in at least 3 commits. The migration is assumed known.

| View | Targets with >= 1 earlier sibling | Median over 27 migrations |
|---|---|---|
| **Pre-registered:** sibling is a git ancestor, different file | **8,541 / 8,818 (96.9%)** | 97.0% |
| Same, including the 2 single-commit migrations | 8,541 / 9,015 (94.7%) | — |
| >= 3 earlier sibling commits | 7,989 / 8,818 (90.6%) | 87.9% |
| Exploratory E1: committed before the target was written | 7,547 / 8,818 (85.6%) | 94.0% |
| Exploratory E2: in a released kernel when the target was written | 6,325 / 8,818 (71.7%) | 80.0% |
| Exploratory E3: E2 and a different author | 4,249 / 8,818 (48.2%) | 33.3% |
| Forced migrations only (old API removed by v6.10, 7 migrations), E2 | 2,172 / 2,427 (89.5%) | — |
| Forced migrations only, E3 | 874 / 2,427 (36.0%) | — |

Per (migration, commit) unit instead of per file (5,245 units): 98.2% pre-registered, 73.6% E2, 61.0% E3. Four
migrations swept in one burst have E2 = 0% (`eth_hw_addr_set`, `netif_rx_ni`, `kobj_default_groups`, `tasklet_setup`).

**Verification** (`make verify-h1`, `results/h1_verify.txt`): for 86 targets (up to 3 per migration: first, middle and last, with
duplicate picks dropped, across the 29 migrations including the 2 single-commit ones), the sibling counts were recomputed by asking git directly. That took
15,607 `git merge-base --is-ancestor` checks and found 0 mismatches with `results/h1_coverage.csv`. An adversarial
review found three real bugs (author aliasing, release-time definition, file-vs-commit counting); they were fixed
before these numbers were produced.

## H2 — do sibling-derived rules migrate held-out drivers? (`results/h2_final_summary.csv`, `results/h2_rules.png`)

Setup: 5 hand-picked migrations; per migration, the earliest 20 `.c` conversions are training siblings. These come
from 1 to 20 commits per migration (`training_commits`). Held-out targets are 20 conversions written after the last
training commit, in different files. 100 targets; **94 buildable** (the original file compiles on x86_64
`allmodconfig`). Rule sources, both from the same 20 training pairs:
- **LLM-written** (`rules/manual/`): an LLM agent whose file access was limited to the training folder. A transcript
  audit found 0 accesses outside it. It may still know these migrations from pre-training; one rule comment names a
  header that appears in no training file.
- **Spinfer** (USENIX ATC 2020), default settings, original toolchain (`results/h2_spinfer_toolchain.txt`).

| Rule source | Correct (of 100) | **Correct and compiles (of 94 buildable)** | Partial | Wrong | No migration | Wrong but compiles |
|---|---|---|---|---|---|---|
| LLM-written | 86 (76 exact, 8 equivalent, 2 behaviour-preserving alternative) | **81** (71 exact) | 8 | 2 | 4 | 1 |
| Spinfer | 30 (28 exact, 2 equivalent) | **26** (24 exact) | 10 | 11 | 49 (40: no rule inferred) | 11 |
| *Only the 3 migrations where Spinfer inferred a rule* | | LLM-written 43/55, Spinfer 26/55 | | | | |

| Migration (training commits) | LLM-written | Spinfer |
|---|---|---|
| `i2c_probe_new` (4) | 19/19 | 0/19 (no rule: the change is in a struct initializer) |
| `platform_remove_new` (20) | 19/20 | 0/20 (no rule: same reason) |
| `ida_simple` (18) | 20/20 | 9/20 (7 wrong: the rule drops an upper bound, yet compiles) |
| `strlcpy_strscpy` (1) | 14/15 | 14/15 (both rules convert only calls whose return value is unused) |
| `pci_dma_wrappers` (14) | 9/20 | 3/20 |

Failure categories (LLM-written / Spinfer): rule too narrow 9 / 17; rule too broad 0 / 8; needs semantic judgment
3 / 3; multi-file dependency 2 / 1; no rule inferred 0 / 40; other 0 / 1. The human fix itself compiles in the parent
tree for 93/94 buildable targets; the exception depends on an edit in another file.

"Exact" is decided by script (whitespace-normalised equality with the human fix). All other verdicts come from two
independent LLM reviewers plus a tie-break (1 tie-break in 56 reviews). They are stored with explanations in
`results/h2_review.csv`. Eight reviews were relabelled "rule too broad" by a fixed text rule in `scripts/h2_final.py`;
the reviewers' own category is kept.

## Honest limitations
- **Population:** H1 covers only migrations performed in >= 3 commits, selected with commit counts known. It does not
  show that most driver updates in general, e.g. DRIVEBENCH cases, have siblings.
- **Existence, not retrieval:** siblings are found with migration-specific patterns, assuming the migration is known.
  Retrieving them automatically from a triggering kernel commit was not tested.
- **Exploratory views:** E1–E3 were defined after the data was seen.
- **Candidate quality:** precision was checked on <= 8 samples per migration (95% Wilson lower bounds 0.44–0.68).
  Recall was not measured, except one spot check (`results/h1_verify.txt`): of 2,691 files using `.remove_new` at
  v6.10, 2,612 are recorded `platform_remove_new` conversions, 69 were new or renamed files added during the window,
  and 10 pre-existing files were missed by the miner.
- **H2 is a pilot:** 5 hand-picked migrations, 20 targets each. The "20 siblings" are 20 file conversions from 1 to 20
  commits.
- **LLM involvement:** the rule author is an LLM that may have seen these migrations in pre-training. File isolation is
  enforced and audited, but prior knowledge cannot be excluded; Spinfer is a baseline, not a control for this.
  Verification and semantic verdicts come from LLM reviewers of the same model family, not kernel maintainers.
- **Compile checks only:** per file, x86_64 `allmodconfig`, GCC 11.4; no linking, QEMU boot or runtime tests.
  6/100 targets are not buildable on x86 (4 other-architecture drivers, 1 disabled by Kconfig, 1 harness limitation).
- **Spinfer** ran with default settings on its 2019–2020 toolchain and might do better with tuning.
- **AUTODRIVER itself was not run or compared.** H3 (LLM alone vs LLM + sibling exemplars) was not run.

## Connection to the AUTODRIVER paper (arXiv:2511.18924; quotes in `docs/artifact_search.md`)
- **Future work, "kernel-aware retrieval systems that dynamically extract API changes from version control":** for API
  migrations that many drivers performed, H1 shows that examples usually already exist in history (71.7% in a release
  before the target was written; 89.5% for forced migrations). They are absent for burst or single-commit migrations.
  Whether they can be retrieved automatically was not tested.
- **Reported failure mode, "missing propagation of related changes across dependent code" (possible relevance, not
  tested):** a Coccinelle rule rewrites every matching site in a file, so it could complement per-site generation. Our
  rules' own failures were mostly variants not shown by the siblings, plus judgment and multi-file cases (3 and 2 of
  100), the kinds the paper also reports as hard.
- **Headline metric, compilation success:** 11 Spinfer outputs and 1 LLM-written output compiled but were judged to
  change behaviour. This illustrates the need for a semantic check next to compile and boot checks. It is not a
  measurement of AUTODRIVER.
- **Positioning:** learning rules from examples is not new (spdiff 2008, Spinfer 2020), and nor is retrieving porting
  commits (Prequel, ATC 2017); see `docs/related_work.md`. What this pilot adds:
  - a measurement on v5.10–v6.10 of when sibling examples exist;
  - compile validation of sibling-derived rules on a chronological hold-out, with an LLM-written vs Spinfer comparison;
  - the residual cases, as a concrete target for LLM + exemplar repair.
