# Phase 2 — H1: do earlier sibling migrations exist?

Reproduce: `docker compose run --rm dev make h1`, which writes `results/h1_coverage.csv` (one row per target),
`results/h1_summary.csv`, `results/h1_units.csv` and `results/h1_coverage.png`. Every number below is copied
from those files.

## Question and definitions
- **Target:** one candidate conversion (commit T, file F) of one of the 27 included migrations (8,818 targets).
- **Earlier sibling (pre-registered):** a conversion of the same migration, in a different file, in a different
  commit that is a **git ancestor** of T (it was already in the history T was built on).
- **Exploratory views (added after seeing the data, NOT pre-registered):** the sibling must also be
  - E1: committed before T's patch was *written* (T's author time);
  - E2: already in a *released* kernel when T was written;
  - E3: E2, and by a *different author* (mailmap name; mailing-list "via ..." rewrites stripped).

## Results

| View | Targets with >= 1 such sibling | Median across 27 migrations |
|---|---|---|
| Pre-registered (ancestor, other file) | **8541/8818 (96.9%)** | 97.0% |
| + the 2 single-commit migrations (sensitivity) | 8541/9015 (94.7%) | — |
| >= 3 earlier sibling *commits* | 7989/8818 (90.6%) | 87.9% |
| E1 committed before the target was written | 7547/8818 (85.6%) | 94.0% |
| E2 released before the target was written | 6325/8818 (71.7%) | 80.0% |
| E3 released before, and by a different author | 4249/8818 (48.2%) | 33.3% |

**Forced migrations** (old API removed from `include/` by v6.10; 7 migrations, 2,427 targets):
pre-registered 2327/2427 (95.9%); E2 released before written 2172/2427 (89.5%); E3 874/2427 (36.0%).

**Per commit** instead of per file (5,245 (migration, commit) units): pre-registered 98.2%, E2 73.6%, E3 61.0%.

## What this means, in plain words
1. Inside migrations that many drivers went through, almost every conversion after the first had an earlier
   sibling in its git history (96.9%).
2. "Earlier" is often only minutes earlier. Many conversions come from one person converting dozens of drivers in a
   single patch series, so those siblings were not public, reviewed examples. When we require the sibling to have
   been in a **released kernel** before the target patch was written, the share falls to 71.7%. If it must also
   come from a **different author**, it falls to 48.2%.
3. The migrations differ sharply. `ida_simple`, `strncpy_strscpy`, `gpiod_from_of_gpio` and `dev_err_probe` were
   converted gradually by many people, so released siblings by other authors existed for over 90% of targets.
   `eth_hw_addr_set`, `netif_rx_ni`, `kobj_default_groups` and `tasklet_setup` were swept in one burst
   (E2 = 0%). `class_create_owner` and `vm_flags_set` were converted in a single commit, so they have no siblings at all.
4. For **forced** migrations (drivers *had* to change, as in AUTODRIVER's setting), a released sibling existed
   for 89.5% of targets.

## Verified checks (adversarial review, 2026-11-10)
- `make verify-h1` (`results/h1_verify.txt`): for 86 targets (up to 3 per migration: first, middle, last; duplicates dropped) the counts
  were recomputed with 15,607 direct `git merge-base --is-ancestor` checks: 0 mismatches.
- Bugs found and fixed before this write-up: the author check did not merge mailing-list-rewritten names
  (this inflated `spi_get_chipselect`'s different-author share; it is 1.9% after the fix); the earlier "strict" view compared release windows instead
  of the target's writing time; "≥3 siblings" counted files rather than commits.

## Limitations (must accompany any H1 number)
- **Selection bias:** we studied only migrations that many drivers performed (>= 3 commits, chosen with commit
  counts known). H1 does **not** show that most driver updates in general, e.g. the paper's DRIVEBENCH cases,
  have siblings. DRIVEBENCH is not public, so this could not be tested.
- **Existence, not findability:** siblings are defined with migration-specific regexes, i.e. the migration's
  identity is assumed known. Whether a retrieval system could *find* them from a triggering kernel commit is untested.
- **Candidate precision:** a sample of <= 8 per migration was verified; 95% Wilson lower bounds on precision are
  0.44–0.68 (column `precision_wilson95_low`). Regex noise among siblings could inflate counts.
- **Recall** is unmeasured except one spot check (`results/h1_verify.txt`): of 2,691 files using `.remove_new` at
  v6.10, 2,612 are recorded conversions, 69 were added during the window, and 10 pre-existing files were missed.
- **Small migrations** (`kstrto` n=3, `in_hardirq` n=4, `pci_alloc_irq_vectors` n=5) weigh as much as large ones in the median.
- The date view treats commits made in the same second as not earlier (one patch series is often applied within
  seconds). The ancestry view is unaffected.
