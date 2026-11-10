#!/usr/bin/env python3
"""Independent checks of H1 (results/h1_verify.txt). Runs inside the container.

1. Ancestry recount: for 3 targets per migration (first, middle, last by commit date), recompute the pre-registered
   earlier-sibling counts WITHOUT the DAG/bitset logic of h1_coverage.py, by asking git directly
   (git merge-base --is-ancestor S T) for every candidate sibling commit S, and compare with results/h1_coverage.csv.
2. Recall spot check for platform_remove_new: files under drivers/ and sound/ that use `.remove_new =` at v6.10,
   versus files recorded as conversions of that migration.
"""
import csv, collections, os, re, subprocess

LINUX = os.environ.get("LINUX", "/linux/linux")
cov = list(csv.DictReader(open("results/h1_coverage.csv", newline="")))
conv = list(csv.DictReader(open("data/conversions.csv", newline=""))) + \
       [r for r in csv.DictReader(open("data/conversions_candidates.csv", newline="")) if r["migration"] in ("class_create_owner", "vm_flags_set")]
by_mig = collections.defaultdict(list)
for r in conv:
    by_mig[r["migration"]].append(r)

out, pairs, mismatches, checked = [], 0, 0, 0
cache = {}
for mig in sorted({r["migration"] for r in cov}):
    ts = sorted((r for r in cov if r["migration"] == mig), key=lambda r: (r["commit_date"], r["file"]))
    for t in {ts[0]["commit"] + t0["file"]: t0 for t0 in (ts[0], ts[len(ts) // 2], ts[-1])}.values():
        T, F = t["commit"], t["file"]
        sib_conv, sib_commits = 0, set()
        for s in by_mig[mig]:
            S = s["commit"]
            if S == T or s["file"] == F:
                continue
            if (S, T) not in cache:
                cache[(S, T)] = subprocess.run(["git", "-C", LINUX, "merge-base", "--is-ancestor", S, T]).returncode == 0
                pairs += 1
            if cache[(S, T)]:
                sib_conv += 1; sib_commits.add(S)
        ok = sib_conv == int(t["earlier_sibling_conversions"]) and len(sib_commits) == int(t["earlier_sibling_commits"])
        checked += 1; mismatches += not ok
        if not ok:
            out.append(f"MISMATCH {mig} {T[:12]} {F}: git {sib_conv}/{len(sib_commits)} vs csv "
                       f"{t['earlier_sibling_conversions']}/{t['earlier_sibling_commits']}")
out.insert(0, f"ancestry recount: {checked} targets, {pairs} distinct (sibling, target) merge-base checks, {mismatches} mismatches")

grep = subprocess.run(["git", "-C", LINUX, "grep", "-l", "-E", r"\.remove_new\s*=", "v6.10", "--", "drivers", "sound"],
                      capture_output=True, text=True).stdout.split()
at_v610 = {g.split(":", 1)[1] for g in grep}
recorded = {r["file"] for r in by_mig["platform_remove_new"]}
missing = sorted(at_v610 - recorded)
out.append(f"recall spot check platform_remove_new: {len(at_v610)} files use .remove_new at v6.10; "
           f"{len(at_v610 & recorded)} are recorded conversions; {len(missing)} are not")
added = 0
for f in missing:
    log = subprocess.run(["git", "-C", LINUX, "log", "--format=%H", "--diff-filter=A", "-M", "v5.10..v6.10", "--", f],
                         capture_output=True, text=True).stdout.split()
    added += bool(log)
out.append(f"  of those {len(missing)}: {added} were added (new or renamed) inside v5.10..v6.10, "
           f"{len(missing) - added} existed before and were missed by the miner")
os.makedirs("results", exist_ok=True)
open("results/h1_verify.txt", "w", newline="\n").write("\n".join(out) + "\n")
print("\n".join(out))
