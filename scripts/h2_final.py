#!/usr/bin/env python3
"""H2 final table: merge the automatic comparison (results/h2_rules.csv) with the stored semantic reviews of
non-exact outputs (results/h2_review.csv; two independent LLM reviewers + tie-break, see docs/phase3_h2.md).

final verdict per (target, source):
  exact                rule output identical to the human fix (whitespace-normalised)          -> automatic
  correct_equivalent   same migration, same meaning, different text/format                     -> reviewed
  correct_alternative  valid, behaviour-preserving migration that differs from the human's choice -> reviewed
  partial / wrong / no_migration / not_a_migration_target                                     -> reviewed
A non-exact row without a stored review is reported as "unreviewed" (never silently counted as correct).

success = (exact | correct_equivalent | correct_alternative) AND the rule output compiles,
          counted over BUILDABLE targets (the original file compiles on x86_64 allmodconfig).
Outputs: results/h2_final.csv, results/h2_final_summary.csv
"""
import collections, csv

rules = list(csv.DictReader(open("results/h2_rules.csv", newline="")))
review = {(r["migration"], r["idx"], r["source"]): r for r in csv.DictReader(open("results/h2_review.csv", newline="", encoding="utf-8"))}
CORRECT = {"exact", "correct_equivalent", "correct_alternative"}

final = []
for r in rules:
    key = (r["migration"], r["idx"], r["source"])
    if r["auto_class"] == "exact":
        v, cat = "exact", "none"
    elif key in review:
        v, cat = review[key]["final_verdict"], review[key]["failure_category"]
    else:
        v, cat = "unreviewed", ""
    buildable = r["build_original"] == "True"
    final.append({**{k: r[k] for k in ("migration", "idx", "source", "commit", "file", "commit_date", "auto_class",
                                       "build_original", "build_human", "build_rule", "files_in_human_commit")},
                  "final_verdict": v, "failure_category": cat, "buildable": buildable,
                  "success": buildable and v in CORRECT and r["build_rule"] == "True"})

with open("results/h2_final.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(final[0]), lineterminator="\n"); w.writeheader(); w.writerows(final)

VERDICTS = ["exact", "correct_equivalent", "correct_alternative", "partial", "wrong", "no_migration", "not_a_migration_target", "unreviewed"]
groups = collections.defaultdict(list)
for r in final:
    groups[(r["source"], r["migration"])].append(r)
    groups[(r["source"], "ALL")].append(r)
out = []
for (src, mig), rs in sorted(groups.items(), key=lambda x: (x[0][0], x[0][1] == "ALL", x[0][1])):
    b = [r for r in rs if r["buildable"]]
    c = collections.Counter(r["final_verdict"] for r in rs)
    cats = collections.Counter(r["failure_category"] for r in rs if r["failure_category"] not in ("none", ""))
    out.append({"source": src, "migration": mig, "targets": len(rs), "buildable": len(b),
                **{v: c.get(v, 0) for v in VERDICTS},
                "correct_any": sum(r["final_verdict"] in CORRECT for r in rs),
                "success_of_buildable": sum(r["success"] for r in b),
                "rule_compiles_of_buildable": sum(r["build_rule"] == "True" for r in b),
                "human_compiles_of_buildable": sum(r["build_human"] == "True" for r in b),
                "failure_categories": "; ".join(f"{k}={n}" for k, n in cats.most_common())})
with open("results/h2_final_summary.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(out[0]), lineterminator="\n"); w.writeheader(); w.writerows(out)
for o in out:
    print(f"{o['source']:8} {o['migration']:20} correct {o['correct_any']}/{o['targets']}  success {o['success_of_buildable']}/{o['buildable']} buildable  "
          f"(exact {o['exact']}, equiv {o['correct_equivalent']}, alt {o['correct_alternative']}, partial {o['partial']}, wrong {o['wrong']}, "
          f"none {o['no_migration']}, unreviewed {o['unreviewed']})  {o['failure_categories']}")
