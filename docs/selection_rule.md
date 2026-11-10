# Case selection rules (pre-registered)

Written on 2026-11-10, **before** any verification verdicts or H1/H2 results were seen. The git history of this
file shows it was committed before `data/verification.csv` existed.

## Which migrations enter the study (`data/cases.csv`)
A candidate migration from `data/migration_summary.csv` is **included** if both hold:
1. **Verified precision >= 0.85:** of its sampled candidate conversions (`data/verify_sample.csv`, up to 8 spread
   over time), the fraction whose final verdict is `genuine` or `partial` is at least 0.85.
2. **At least 3 distinct candidate conversion commits** in v5.10..v6.10.

Migrations whose conversions are concentrated in one tree-wide commit are **not excluded**. They are real
API migrations where earlier siblings may not exist, and dropping them would inflate H1.

## How H1 is reported
- The unit is one target conversion: a (commit, file) pair.
- An **earlier sibling** of a target is a conversion of the same migration that (a) touches a different file and
  (b) is in a *different, earlier* commit. "Earlier" is judged by git ancestry: the sibling commit is an ancestor of
  the target commit. Committer date is reported as a secondary view.
- Conversions in the same commit as the target are never counted as earlier siblings.
- We report per-migration results, the median across migrations (so huge migrations such as `platform_remove_new`
  do not dominate), and pooled results. The verified precision of each migration's candidate list is reported
  next to its H1 numbers.

## Verification protocol
Two independent reviewers (A: judge, B: skeptic) see each sampled commit's real diff and a completeness count.
Agreement gives the final verdict. On disagreement a third reviewer decides by majority, otherwise `unclear`
(counted as not verified). The reviewers are LLM agents; every verdict and its reason is stored in
`data/verification.csv` so a human can audit each one.
