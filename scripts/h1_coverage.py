#!/usr/bin/env python3
"""H1 (existence of earlier siblings): for each target conversion, how many EARLIER SIBLING conversions exist?

PRE-REGISTERED view (docs/selection_rule.md):
  target  = one candidate conversion (commit T, file F) of migration M (data/conversions.csv)
  sibling = a conversion (S, F') of the same M with F' != F, in a different commit S that is a git ANCESTOR of T.
  Secondary: S committed before T (committer time; same-second ties count as NOT earlier).

EXPLORATORY views (added after seeing the data; NOT pre-registered). All require S to be an ancestor of T and ask
whether the sibling was already available when the target patch was WRITTEN (T's author time):
  E1 committed_before_written : S's commit time < T's author time
  E2 released_before_written  : the first release containing S was tagged before T's author time
  E3 E2 and a different author: author identity = mailmap name with mailing-list rewrites (" via ...") stripped

Ancestry is exact: a bitset of "conversion commits among my ancestors" propagated over the v5.10..v6.10 DAG in
topological order. Parents outside the range cannot contain conversions (all conversions were mined inside it).

Outputs: results/h1_coverage.csv (per target), results/h1_summary.csv (per migration + aggregate rows),
         results/h1_units.csv (aggregates at the (migration, commit) unit), results/h1_coverage.png
"""
import csv, collections, math, os, re, statistics, subprocess

LINUX = os.environ.get("LINUX", "/linux/linux")
SENSITIVITY = ["class_create_owner", "vm_flags_set"]  # single-commit migrations excluded by the >=3-commit rule
TAGS = [f"v5.{i}" for i in range(10, 20)] + [f"v6.{i}" for i in range(0, 11)]
DAY = 86400.0


def git(*a, inp=None):
    return subprocess.run(["git", "-C", LINUX, *a], input=inp, capture_output=True, text=True, check=True).stdout


def read(p):
    return list(csv.DictReader(open(p, newline="")))


rows = read("data/conversions.csv") + [r for r in read("data/conversions_candidates.csv") if r["migration"] in SENSITIVITY]
cases = {r["migration"]: r for r in read("data/cases.csv")}
ver = {r["migration"]: r for r in read("data/verification_summary.csv")}

ct = {r["commit"]: int(r["commit_time"]) for r in rows}
idx = {c: i for i, c in enumerate(sorted(ct))}

# release window + author time per commit, from the miner's output
release, at = {}, {}
for r in csv.DictReader(open("data/mined_hits.csv", newline="")):
    if r["commit"] in ct:
        release[r["commit"]] = r["window_end_tag"]
        at[r["commit"]] = int(r["author_time"])
assert all(c in release for c in ct)
tag_time = {t: int(git("log", "-1", "--format=%ct", t).strip()) for t in TAGS[1:]}

# author identity: mailmap name, mailing-list rewrites stripped, case-folded
author = {}
for line in git("log", "--no-walk", "--stdin", "--format=%H\t%aN", inp="\n".join(ct)).splitlines():
    h, n = line.split("\t", 1)
    author[h] = re.sub(r"\s+via\s+.*$", "", n).strip().lower()
assert all(c in author for c in ct)

# exact ancestry over the DAG
anc = {}
for line in git("rev-list", "--topo-order", "--reverse", "--parents", "v5.10..v6.10").split("\n"):
    if not line:
        continue
    c, *parents = line.split()
    bits = 0
    for p in parents:
        if p in anc:
            bits |= anc[p]
            if p in idx:
                bits |= 1 << idx[p]
    anc[c] = bits
assert all(c in anc for c in ct), "conversion commit outside v5.10..v6.10"

by_mig = collections.defaultdict(lambda: collections.defaultdict(set))
for r in rows:
    by_mig[r["migration"]][r["commit"]].add(r["file"])

VIEWS = ["e1_committed_before_written", "e2_released_before_written", "e3_released_before_written_other_author"]
targets = []
for r in rows:
    m, T, F = r["migration"], r["commit"], r["file"]
    bitsT, tT, aT = anc[T], ct[T], at[T]
    conv = commits = d_commits = 0
    times, v = [], dict.fromkeys(VIEWS, 0)
    for S, files in by_mig[m].items():
        if S == T or not (files - {F}):
            continue
        n = len(files - {F})
        if ct[S] < tT:
            d_commits += 1
        if not (bitsT >> idx[S]) & 1:
            continue
        conv += n; commits += 1; times.append(ct[S])
        e1 = ct[S] < aT
        e2 = tag_time[release[S]] < aT
        v["e1_committed_before_written"] += e1
        v["e2_released_before_written"] += e2
        v["e3_released_before_written_other_author"] += e2 and author[S] != author[T]
    targets.append({
        "migration": m, "commit": T, "file": F, "commit_date": r["commit_date"],
        "set": "main" if m not in SENSITIVITY else "sensitivity_single_commit",
        "earlier_sibling_conversions": conv, "earlier_sibling_commits": commits, "earlier_by_date_commits": d_commits,
        **{f"{k}_commits": val for k, val in v.items()},
        "days_since_first_sibling": f"{(tT - min(times)) / DAY:.1f}" if times else "",
        "days_since_latest_sibling": f"{(tT - max(times)) / DAY:.1f}" if times else "",
    })

os.makedirs("results", exist_ok=True)
with open("results/h1_coverage.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(targets[0]), lineterminator="\n")
    w.writeheader(); w.writerows(targets)


def wilson_low(k, n, z=1.96):
    if n == 0:
        return float("nan")
    p = k / n
    return (p + z * z / (2 * n) - z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))) / (1 + z * z / n)


COLS = [("ge1", "earlier_sibling_commits", 1), ("ge3_commits", "earlier_sibling_commits", 3),
        ("ge1_by_date", "earlier_by_date_commits", 1)] + [(k, f"{k}_commits", 1) for k in VIEWS]


def summarize(name, ts):
    n = len(ts)
    out = {"migration": name, "targets": n}
    for col, key, thr in COLS:
        k = sum(t[key] >= thr for t in ts)
        out[f"{col}"] = k
        out[f"{col}_pct"] = f"{100 * k / n:.1f}"
    have = [float(t["days_since_latest_sibling"]) for t in ts if t["days_since_latest_sibling"]]
    out["median_days_since_latest_sibling_when_any"] = f"{statistics.median(have):g}" if have else ""
    c, v = cases.get(name), ver.get(name)
    out["old_api_removed_by_v6.10"] = c["old_api_removed_by_v6.10"] if c else ""
    out["candidate_precision"] = f"{v['verified']}/{v['sampled']}" if v else ""
    out["precision_wilson95_low"] = f"{wilson_low(int(v['verified']), int(v['sampled'])):.2f}" if v else ""
    return out


per = collections.defaultdict(list)
for t in targets:
    per[t["migration"]].append(t)
main_migs = sorted(m for m in per if m not in SENSITIVITY)
summary = [summarize(m, per[m]) for m in main_migs]
main_ts = [t for t in targets if t["set"] == "main"]
pooled = summarize(f"ALL main ({len(main_migs)} migrations, pooled)", main_ts)
pct_cols = [k for k in summary[0] if k.endswith("_pct")]
macro = {"migration": f"MEDIAN across the {len(main_migs)} main migrations", "targets": "",
         **{k: f"{statistics.median(float(s[k]) for s in summary):.1f}" for k in pct_cols}}
forced = summarize("ALL forced (old API removed by v6.10)", [t for t in main_ts if cases[t["migration"]]["old_api_removed_by_v6.10"] == "yes"])
other = summarize("ALL other (old API still present or not checked)", [t for t in main_ts if cases[t["migration"]]["old_api_removed_by_v6.10"] != "yes"])
sens_each = [summarize(m, per[m]) for m in SENSITIVITY]
sens = summarize("ALL main + single-commit migrations (sensitivity)", targets)
with open("results/h1_summary.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(summary[0]), lineterminator="\n")
    w.writeheader(); w.writerows(summary + [pooled, macro, forced, other] + sens_each + [sens])

# (migration, commit) unit: a commit is covered if ANY of its target files is (all files of a commit share history)
units = {}
for t in targets:
    u = units.setdefault((t["migration"], t["commit"]), {"set": t["set"], **{c: 0 for c, _, _ in COLS}})
    for col, key, thr in COLS:
        u[col] = max(u[col], int(t[key] >= thr))
with open("results/h1_units.csv", "w", newline="") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(["scope", "units"] + [f"{c}_pct" for c, _, _ in COLS])
    for scope, keep in [("main", lambda s: s == "main"), ("main+single-commit", lambda s: True)]:
        us = [u for u in units.values() if keep(u["set"])]
        w.writerow([scope, len(us)] + [f"{100 * sum(u[c] for u in us) / len(us):.1f}" for c, _, _ in COLS])

# chart: three small multiples, same scale
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

SURF, INK, INK2, GRID, SERIES = "#fcfcfb", "#0b0b0b", "#52514e", "#e4e3df", "#2a78d6"
order = sorted(summary, key=lambda s: (float(s["e3_released_before_written_other_author_pct"]), float(s["e2_released_before_written_pct"]), float(s["ge1_pct"])))
labels = [f"{s['migration']} (n={s['targets']})" for s in order]
panels = [("ge1", "PRE-REGISTERED\nearlier sibling = git ancestor, other file"),
          ("e2_released_before_written", "EXPLORATORY\n...and already in a release when\nthe target patch was written"),
          ("e3_released_before_written_other_author", "EXPLORATORY\n...and also by a different author")]
fig, axes = plt.subplots(1, 3, sharey=True, figsize=(14, 0.3 * len(labels) + 2.4), facecolor=SURF)
for ax, (col, title) in zip(axes, panels):
    ax.set_facecolor(SURF)
    ax.barh(labels, [float(s[f"{col}_pct"]) for s in order], height=0.62, color=SERIES)
    for y, s in enumerate(order):
        ax.text(float(s[f"{col}_pct"]) + 1.5, y, f"{s[col]}/{s['targets']}", va="center", fontsize=7, color=INK2)
    ax.set_xlim(0, 122); ax.set_xticks([0, 25, 50, 75, 100])
    ax.xaxis.grid(True, color=GRID, linewidth=0.8); ax.set_axisbelow(True)
    for side in ("top", "right", "left"):
        ax.spines[side].set_visible(False)
    ax.spines["bottom"].set_color(GRID)
    ax.tick_params(colors=INK2, labelsize=7.5, length=0)
    ax.set_title(f"{title}\nall: {pooled[col]}/{pooled['targets']} ({pooled[col + '_pct']}%), "
                 f"median per migration {macro[col + '_pct']}%", color=INK, fontsize=8.5, loc="left")
    ax.set_xlabel("% of target conversions with >= 1 such sibling", color=INK2, fontsize=8)
fig.suptitle(f"H1 - do earlier sibling migrations exist? {len(main_migs)} migrations, v5.10..v6.10 "
             f"(with the 2 single-commit migrations: {sens['ge1']}/{sens['targets']} = {sens['ge1_pct']}% pre-registered)",
             color=INK, fontsize=10, x=0.01, ha="left")
fig.tight_layout()
fig.savefig("results/h1_coverage.png", dpi=150, facecolor=SURF)

for s in [pooled, macro, forced, other, sens]:
    print(s["migration"], "|", " ".join(f"{c}={s.get(c, '')}{'/' + str(s['targets']) if s['targets'] != '' else ''} ({s[c + '_pct']}%)" for c, _, _ in COLS))
print(open("results/h1_units.csv").read())
