#!/usr/bin/env python3
"""Merge the blind human labels (labeling/labels.csv) with the source key and the automatic test results.

Reported separately from the automatic metric. For every source of the labelling packet:
  correct_and_compiles = exact-and-compiles (automatic) + labelled correct_equivalent/correct_alternative whose output
                         compiles (outputs that the automatic harness did not compile are compiled here, same recipe)
Run inside the dev container (it may build).  Output: results/test_human_labels.csv, results/test_human_summary.csv
"""
import collections, csv, hashlib, os, sys

sys.path.insert(0, os.path.dirname(__file__))
from gcg_critic import Builder  # noqa: E402
from make_label_sheet import rule_output, source_name  # noqa: E402  (same item definition)

labels = {r["id"]: r for r in csv.DictReader(open("labeling/labels.csv"))}
key = {r["id"]: r for r in csv.DictReader(open("labeling/key.csv"))}
missing = [i for i, r in labels.items() if not r["label"].strip()]
if missing:
    raise SystemExit(f"{len(missing)} items have no label yet (e.g. {missing[:5]})")
by_target = {(k["migration"], k["idx"], s): (i, labels[i]["label"].strip())
             for i, k in key.items() for s in k["sources"].split()}
rows = [r for r in csv.DictReader(open("results/gcg_heldout_test_rows.csv")) if source_name(r)]
builders, out_rows = {}, []
for r in rows:
    src = source_name(r)
    lab = "exact" if r["auto_class"] == "exact" else by_target.get((r["migration"], r["idx"], src), (None, ""))[1]
    compiles = r["build_rule"]
    if lab in ("correct_equivalent", "correct_alternative") and compiles in ("", None) and r["build_original"] == "True":
        b = builders.setdefault(r["migration"], Builder(r["migration"], tag="eval"))
        compiles = str(b.build(r["commit"], r["file"], rule_output(r))["ok"])
    out_rows.append({"source": src, "migration": r["migration"], "idx": r["idx"], "auto_class": r["auto_class"],
                     "human_label": lab or r["auto_class"], "build_original": r["build_original"],
                     "build_rule": compiles})
with open("results/test_human_labels.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(out_rows[0]), lineterminator="\n")
    w.writeheader(); w.writerows(out_rows)
summ = collections.defaultdict(collections.Counter)
for r in out_rows:
    if r["build_original"] != "True":
        continue
    s = summ[r["source"]]
    s["buildable"] += 1
    s[r["human_label"]] += 1
    if r["human_label"] in ("exact", "correct_equivalent", "correct_alternative") and r["build_rule"] == "True":
        s["correct_and_compiles"] += 1
cols = ["buildable", "correct_and_compiles", "exact", "correct_equivalent", "correct_alternative", "partial", "wrong",
        "no_migration", "no_change", "no_rule", "spatch_error"]
with open("results/test_human_summary.csv", "w", newline="") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(["source"] + cols)
    for s, c in sorted(summ.items()):
        w.writerow([s] + [c.get(k, 0) for k in cols])
        print(s, {k: c.get(k, 0) for k in cols})
