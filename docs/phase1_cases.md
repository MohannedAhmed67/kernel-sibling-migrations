# Phase 1 — Our case list (because DRIVEBENCH is not public)

Reproduce: `make mine candidates api-events`, then `python3 scripts/select_cases.py`
(the verdicts in `data/verification.csv` are the stored output of the review step below).

## Pipeline
1. **Mine** (`scripts/mine_history.py`): one pass over every non-merge commit in v5.10..v6.10 touching `drivers/` or
   `sound/`. For 35 candidate migrations (`data/migrations.json`), a file in a commit is a *candidate conversion* if
   the commit removes a line matching the OLD-API regex and adds a line matching the NEW-API regex in that file.
   32 migrations had at least one candidate.
2. **Summarise** (`scripts/build_cases.py`): `data/migration_summary.csv` gives counts, date span, and how
   concentrated each migration is in its single largest commit (tree-wide changes).
3. **API events** (`scripts/api_events.py`): when the new API first appears in `include/`, and when the old API
   disappears from it (where a header pattern was defined).
4. **Verify** (`scripts/sample_for_verification.py` -> review -> `data/verification.csv`): up to 8 candidates per
   migration, spread over time. Two independent LLM reviewers (judge + skeptic) read each real diff, plus a third on
   disagreement. 223 samples; reviewers disagreed on 1. Each verdict and its quoted evidence is stored for audit.
5. **Select** (`scripts/select_cases.py`), using the rule pre-registered in `docs/selection_rule.md`:
   verified precision >= 0.85 and >= 3 distinct commits.

## Outputs
- `data/cases.csv`: one row per migration, with the include/exclude decision and reason, verified precision,
  counts, and API intro/removal commits.
- `data/conversions.csv`: all candidate conversions (commit, dates, file) of the included migrations. This is the
  universe for H1 and H2.

## Excluded migrations, and why
- `class_create_owner`, `vm_flags_set`: done in **one tree-wide commit**, so no earlier siblings can exist.
  These are real migrations: evidence that some API changes are converted atomically by the API author.
- `napi_weight`, `i2c_remove_void`, `timer_delete`: the regex candidates were too noisy (verified precision
  3/8, 5/8, 2/3). For example, `napi_weight` hits were mostly calls moved or re-indented with the old API kept.

## Caveats (carried into the final report)
- Candidates come from line regexes. Precision is estimated from a sample of <= 8 per migration, so it is a
  coarse estimate. Recall (conversions the regexes missed) is **not** measured.
- The reviewers are LLM agents of the same model family. Their agreement is not equivalent to two independent
  human experts. During the session, the orchestrating agent also spot-checked the rejections and two acceptances
  against the raw diffs; those spot checks are not stored in the repo.
- "Conversion" is judged per file. A `partial` verdict means old-API uses remain in the file after the commit.
