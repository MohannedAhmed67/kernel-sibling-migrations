# Phase 3 — H2: can a rule derived only from earlier siblings migrate held-out drivers?

Reproduce (all numbers below come from these files):
```sh
docker compose run --rm dev make h2        # split -> apply rules -> compare -> compile -> merge stored reviews
bash scripts/h2_spinfer.sh                 # (host, needs Docker) re-infer rules/spinfer/*.cocci from the training pairs
```
Outputs: `data/h2_split.csv`, `rules/{manual,spinfer}/*.cocci`, `results/h2_rules.csv` (automatic comparison and
compile results), `results/h2_review.csv` (stored semantic reviews), `results/h2_final.csv`,
`results/h2_final_summary.csv`, `results/h2_rules.png`, `results/h2_isolation_audit.txt`, `results/h2_spinfer_runs.txt`.

## Setup
- **Migrations (5):** `ida_simple`, `i2c_probe_new`, `platform_remove_new`, `strlcpy_strscpy`, `pci_dma_wrappers`.
- **Chronological split per migration:** the earliest 20 `.c` conversions (30% capped at 20) are the training
  siblings. Targets are conversions *written* (author time) after the last training commit was committed, in
  different files. 20 targets per migration were sampled evenly over time: **100 targets**. For 75/100 targets every
  training commit is also a git ancestor of the target; the other 25 were written after the training commits but on
  parallel branches.
- **Two rule sources, same 20 training pairs:**
  - `manual`: written by an LLM agent (Claude) that could read only its migration's training folder. A transcript audit
    found 0 accesses outside it (`results/h2_isolation_audit.txt`). The agent may still know these kernel migrations from
    pre-training: one rule comment names `pci-dma-compat.h`, which appears in no training file.
  - `spinfer`: Spinfer (Serrano et al., USENIX ATC 2020), commit c47696a, run on the same pairs.
- **Evaluation per target:** apply the rule with spatch 1.1.1 to the file at the fix commit's parent; compare with the
  human fix; compile the original, the human fix and the rule output in that tree (x86_64 `allmodconfig`, WERROR off,
  fresh build directory per target). Non-exact outputs were judged by two independent LLM reviewers with a tie-break
  (1 tie-break for 56 reviews).

## Results

| Rule source | Correct* | Correct and compiles, of buildable | Partial | Wrong | No migration | Wrong but compiles |
|---|---|---|---|---|---|---|
| manual (sibling-derived) | **86/100** | **81/94** | 8 | 2 | 4 | 1 |
| Spinfer (sibling-derived) | 30/100 | 26/94 | 10 | 11 | 49 | **11** |

\*Correct = identical to the human fix (manual 76, Spinfer 28), equivalent (8 / 2), or a behaviour-preserving
alternative (2 / 0).

Per migration (correct-and-compiles / buildable):

| Migration | manual | Spinfer | Note |
|---|---|---|---|
| `i2c_probe_new` | 19/19 | 0/19 | Spinfer: "no code to learn from" (change is in a struct initializer, outside functions) |
| `platform_remove_new` | 19/20 | 0/20 | same Spinfer limitation; 1 human fix depends on another file |
| `ida_simple` | 20/20 | 9/20 | Spinfer rule over-generalised: 7 outputs drop an upper bound, which compiles but is wrong |
| `strlcpy_strscpy` | 14/15 | 14/15 | both learned the same rule: only `strlcpy(...);` as a statement |
| `pci_dma_wrappers` | 9/20 | 3/20 | many wrapper variants and idioms not covered by the 20 siblings |

**Buildability:** 94/100 targets compile in their original form on x86_64 `allmodconfig`. The 6 that do not:
4 drivers for other architectures (PowerPC, m68k, 2× s390); 1 driver disabled by x86 Kconfig (`qcom_sysmon`);
1 harness limitation (`amd/pm/legacy_dpm.c`, which is built from another directory's Makefile). The human fix
compiles for 93/94; the exception depends on an edit in another file.

## What failed, and why (failure categories)
- **Rule too narrow** (manual 9, Spinfer 17): the training siblings did not show a variant, e.g. a different
  `pci_*` wrapper or a chained assignment.
- **Rule too broad** (Spinfer 8): the rule matches more than it should. Spinfer learned
  `E = ida_simple_get(X, 0, E2, GFP_KERNEL)` → `E = ida_alloc(X, GFP_KERNEL)`, which silently drops E2.
  Example: `ptp_clock.c`, where the minor number can then exceed `MINORMASK`.
- **Needs semantic judgment** (manual 3, Spinfer 3): e.g. `strlcpy` calls whose return value is used (`strscpy`
  returns something else), or a function the human deliberately left for later.
- **Multi-file dependency** (manual 2, Spinfer 1): the correct fix changes a header or another file. Example:
  `xillybus` stores the device as a `void *`, so the mechanical `&dev->dev` rewrite does not compile.
- **Tool produced no rule** (Spinfer 40): both struct-initializer migrations.
- **Human made a different choice** (manual 2, counted as correct): in `slimbus` the rule kept the exact old range,
  while the human deliberately allowed "one more device".

## Plain-language reading
1. When the 20 earlier siblings show the whole pattern, a rule derived only from them reproduced the human fix on
   held-out drivers almost every time: 19/19, 20/20, 19/20 and 14/15 (correct and compiles) on four of five migrations.
2. When the pattern has many variants (`pci_dma_wrappers`), sibling-derived rules stay incomplete (9/20 manual).
   This is the residue where something more flexible, such as an LLM given the siblings as examples, could help (H3).
3. **"It compiles" is not "it is correct".** 11 of Spinfer's outputs and 1 manual output compile but change
   behaviour. Compile success is AUTODRIVER's main metric, so this shows it can over-count.
4. The automatic rule learner (Spinfer) is much weaker here than a hand-written rule from the same examples
   (26/94 vs 81/94). This is partly because two common driver migrations change struct initializers, which are
   outside Spinfer's scope.

## Limitations
- 5 migrations, 20 targets each, chosen by hand to span easy→hard. Not a random sample of driver updates.
- The manual rule author is an LLM that may have seen these migrations during pre-training. Isolation from the
  held-out fixes is enforced and audited, but prior knowledge cannot be ruled out.
- Semantic verdicts for non-exact outputs come from LLM reviewers (same model family), not from kernel maintainers.
  Every verdict and its explanation is stored in `results/h2_review.csv` for audit.
- The category list lacked "rule too broad". 8 reviews were relabelled to it by a fixed text rule in
  `scripts/h2_final.py`; the reviewers' original category is kept in `reviewer_category`.
- Compile checks are per-file on x86_64 only. No linking, boot (QEMU) or runtime test.
- Spinfer ran with its default settings and an old toolchain (Debian 10, OCaml 4.05, Coccinelle 2019). A tuned
  Spinfer, or one learning from more examples, could do better.
- The stored first manual-rule run used per-migration build directories that persisted between targets. The final
  run uses a fresh build directory per target. Both runs gave the same manual classifications for all 100 targets,
  except `pci_dma_wrappers` #5. That row changed from `spatch_error` to `no_change` after the harness learned that
  spatch exits non-zero when it changes nothing.
