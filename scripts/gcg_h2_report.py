#!/usr/bin/env python3
"""Side-by-side held-out comparison on the AUTOMATIC metric only (no semantic review):
success = rule output is exact or subset_complete (see scripts/h2_eval.py) AND compiles, over buildable targets.

Input : results/h2_summary.csv (Phase 3: manual = frontier-LLM rules, spinfer)
        results/gcg_h2_summary.csv (guided rule generation with small local models, H2_OUT=gcg_h2)
Output: results/gcg_h2_compare.csv  one row per migration (+ ALL), one column per source
"""
import csv

rows = list(csv.DictReader(open("results/h2_summary.csv"))) + list(csv.DictReader(open("results/gcg_h2_summary.csv")))
sources = list(dict.fromkeys(r["source"] for r in rows))
migs = list(dict.fromkeys(r["migration"] for r in rows if r["migration"] != "ALL")) + ["ALL"]
cell = {(r["migration"], r["source"]): r for r in rows}
out = []
for m in migs:
    o = {"migration": m, "buildable": cell[(m, sources[0])]["buildable"]}
    for s in sources:
        r = cell.get((m, s))
        o[s] = r["exact_or_subset_complete_and_compiles"] if r else ""
        o[f"{s}_exact"] = r["exact"] if r else ""
    out.append(o)
with open("results/gcg_h2_compare.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(out[0]), lineterminator="\n")
    w.writeheader(); w.writerows(out)
print("success = exact or subset_complete, and compiles (automatic; over buildable targets)")
print(f"{'migration':20} {'buildable':>9} " + " ".join(f"{s:>9}" for s in sources))
for o in out:
    print(f"{o['migration']:20} {o['buildable']:>9} " + " ".join(f"{o[s]:>9}" for s in sources))
