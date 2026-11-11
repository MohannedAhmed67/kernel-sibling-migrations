# Test set for guided rule generation (pre-registered)

Written on 2026-11-11, **before** kernel history after v6.10 was mined for these migrations and before any rule was
generated for them. The candidate list is `data/test/migrations.json`. This file and that list are committed before
`data/test/mined_hits.csv` exists; the git history orders the two.

## Why a separate test set
The five Phase-3 migrations (`ida_simple`, `i2c_probe_new`, `platform_remove_new`, `strlcpy_strscpy`,
`pci_dma_wrappers`) are the **development set**: the framework's prompts, hints, auto-repair and critic were designed
while looking at their training siblings, and their held-out targets were evaluated during development. Numbers on
them are development numbers. The headline numbers come from this test set, run once with the frozen framework.

A second reason is contamination. The three local models have training cutoffs well before the new APIs below:
Llama 3.1 8B (December 2023), Qwen2.5-Coder 7B (code from GitHub repositories created before February 2024),
Gemma 3 4B (August 2024). A migration whose new API did not exist before **2024-09-01** cannot be in their training
data, neither as API documentation nor as converted drivers.

## Candidates
Fourteen candidate migrations, chosen from memory of kernel development in 2024–2026 before looking at the mined data,
listed in `data/test/migrations.json` with the same old/new line-regex convention as `data/migrations.json`.
`platform_driver .remove_new -> .remove` (v6.13) was deliberately left out: it reverses a development-set migration.

## Mining
`scripts/mine_history.py` over v6.10..v7.4-rc2 (consecutive release windows), paths `drivers` and `sound`,
writing to `data/test/`. A (commit, file) is a candidate conversion if a removed line matches `old` and an added line
matches `new` (`scripts/build_cases.py`).

## Inclusion rule (all must hold)
1. **New API is new:** the `hdr_new` regex has no match in `include/` at v6.10, and the first commit in
   v6.10..v7.4-rc2 that adds a matching `include/` line is dated on or after 2024-09-01.
2. **At least 3 distinct conversion commits.**
3. **Verified precision >= 0.85:** of up to 8 candidate conversions sampled evenly over time, at least 85% are
   genuine or partial conversions. As in Phase 1 the reviewer is an LLM (here the assistant, reading each real diff),
   and every verdict and reason is stored in `data/test/verification.csv` so a human can audit it.
4. **Enough data after the split:** the chronological split of `scripts/h2_split.py` (earliest 30% capped at 20 are
   training siblings, one per file; targets are written after the last training commit, in other files and other
   commits; up to 20 sampled evenly) gives at least 5 training siblings and at least 10 eligible targets.

Every candidate is reported with the rule that excluded it.

## What is run on the test set, once
- The framework frozen at git tag `gcg-frozen-1` (all prompts, thresholds and code as of that tag), with the same
  six configurations and three seeds as on the development set (`scripts/gcg_ablate.sh`), for the three local models.
- Spinfer on the same training pairs, as in Phase 3.
- Evaluation with the unchanged development harness: the automatic metric (rule output identical to the human fix, or
  a subset of the human's changes that leaves no more old-API uses than the human did, **and** the output compiles on
  x86_64 allmodconfig) over targets whose original file compiles.
- Non-exact outputs are then labelled blind by a human (rule source hidden), and the labels are reported separately
  from the automatic metric.

No prompt, hint, threshold or code is changed after the first test-set run. If a bug forces a change, the change and
both sets of numbers are reported.
