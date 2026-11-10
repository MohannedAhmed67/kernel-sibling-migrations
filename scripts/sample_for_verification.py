#!/usr/bin/env python3
"""Deterministic verification sample: per migration, up to N candidate conversions spread evenly over time,
at most one file per commit. Output: data/verify_sample.csv."""
import csv, collections

N = 8
rows = list(csv.DictReader(open("data/conversions_candidates.csv", newline="")))
by = collections.defaultdict(list)
for r in rows:
    by[r["migration"]].append(r)

out = []
for mig in sorted(by):
    seen, uniq = set(), []
    for r in sorted(by[mig], key=lambda r: (int(r["commit_time"]), r["commit"], r["file"])):
        if r["commit"] not in seen:          # one (first, alphabetical) file per commit
            seen.add(r["commit"]); uniq.append(r)
    k = min(N, len(uniq))
    idx = sorted({round(i * (len(uniq) - 1) / max(k - 1, 1)) for i in range(k)})
    for j, i in enumerate(idx):
        r = uniq[i]
        out.append({"sample_id": f"{mig}#{j}", "migration": mig, "commit": r["commit"],
                    "commit_date": r["commit_date"], "file": r["file"], "subject": r["subject"]})

with open("data/verify_sample.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(out[0]))
    w.writeheader(); w.writerows(out)
print(f"{len(out)} samples across {len(by)} migrations -> data/verify_sample.csv")
