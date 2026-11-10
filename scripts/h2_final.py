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
import collections, csv, re

# The reviewers' category list lacked "rule_too_broad" (a rule that matches more than it should, e.g. dropping
# ida_simple_get's upper bound). A WRONG verdict whose stored explanation describes that mechanism is relabelled
# here; the reviewers' original category is kept in column reviewer_category.
TOO_BROAD = re.compile(r"over-general|overgeneral|too broad|over-broad|drops? (the|any|its)? ?(upper |max )?(bound|argument)|"
                       r"dropped the (upper )?bound|throws away the (non-zero )?(upper )?bound|upper bound .{0,40}is lost", re.I)

rules = list(csv.DictReader(open("results/h2_rules.csv", newline="")))
review = {(r["migration"], r["idx"], r["source"]): r for r in csv.DictReader(open("results/h2_review.csv", newline="", encoding="utf-8"))}
CORRECT = {"exact", "correct_equivalent", "correct_alternative"}

final = []
for r in rules:
    key = (r["migration"], r["idx"], r["source"])
    if r["auto_class"] == "exact":
        v, cat = "exact", "none"
    elif r["auto_class"] == "no_rule":   # the rule learner produced no rule for this migration
        v, cat = "no_migration", "tool_no_rule_inferred"
    elif key in review:
        v, cat = review[key]["final_verdict"], review[key]["failure_category"]
        if v == "wrong" and TOO_BROAD.search(review[key]["explanation"]):
            cat = "rule_too_broad"
    else:
        v, cat = "unreviewed", ""
    reviewer_cat = review[key]["failure_category"] if key in review else ""
    buildable = r["build_original"] == "True"
    final.append({**{k: r[k] for k in ("migration", "idx", "source", "commit", "file", "commit_date", "auto_class",
                                       "build_original", "build_human", "build_rule", "files_in_human_commit")},
                  "final_verdict": v, "failure_category": cat, "reviewer_category": reviewer_cat, "buildable": buildable,
                  "success": buildable and v in CORRECT and r["build_rule"] == "True"})

with open("results/h2_final.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(final[0]), lineterminator="\n"); w.writeheader(); w.writerows(final)

VERDICTS = ["exact", "correct_equivalent", "correct_alternative", "partial", "wrong", "no_migration", "not_a_migration_target", "unreviewed"]
groups = collections.defaultdict(list)
spinfer_rule_migs = {r["migration"] for r in final if r["source"] == "spinfer" and r["auto_class"] != "no_rule"}
for r in final:
    groups[(r["source"], r["migration"])].append(r)
    groups[(r["source"], "ALL")].append(r)
    if r["migration"] in spinfer_rule_migs:   # like-for-like: only migrations where Spinfer produced a rule
        groups[(r["source"], "ALL_where_spinfer_inferred_a_rule")].append(r)
split = list(csv.DictReader(open("data/h2_split.csv", newline="")))
train_commits = {m: len({s["commit"] for s in split if s["migration"] == m and s["role"] == "train"})
                 for m in {s["migration"] for s in split}}
out = []
for (src, mig), rs in sorted(groups.items(), key=lambda x: (x[0][0], x[0][1].startswith("ALL"), x[0][1])):
    b = [r for r in rs if r["buildable"]]
    c = collections.Counter(r["final_verdict"] for r in rs)
    cats = collections.Counter(r["failure_category"] for r in rs if r["failure_category"] not in ("none", ""))
    out.append({"source": src, "migration": mig, "targets": len(rs), "buildable": len(b),
                "training_commits": train_commits.get(mig, ""),
                "success_exact_of_buildable": sum(r["success"] and r["final_verdict"] == "exact" for r in b),
                **{v: c.get(v, 0) for v in VERDICTS},
                "correct_any": sum(r["final_verdict"] in CORRECT for r in rs),
                "success_of_buildable": sum(r["success"] for r in b),
                "rule_compiles_of_buildable": sum(r["build_rule"] == "True" for r in b),
                "human_compiles_of_buildable": sum(r["build_human"] == "True" for r in b),
                "wrong_but_compiles": sum(r["final_verdict"] == "wrong" and r["build_rule"] == "True" for r in rs),
                "failure_categories": "; ".join(f"{k}={n}" for k, n in cats.most_common())})
with open("results/h2_final_summary.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(out[0]), lineterminator="\n"); w.writeheader(); w.writerows(out)
# chart: one stacked bar per (source, migration); palette validated with the dataviz skill's validator
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

SURF, INK, INK2, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#e4e3df"
SEG = [("correct (exact / equivalent / alternative)", ["exact", "correct_equivalent", "correct_alternative"], "#2a78d6"),
       ("partial", ["partial"], "#eda100"),
       ("wrong", ["wrong"], "#e34948"),
       ("no migration / no rule", ["no_migration", "not_a_migration_target", "unreviewed"], "#6250d6")]
rows_plot = [o for o in out if o["migration"] != "ALL_where_spinfer_inferred_a_rule"]
labels = [f"{o['source']}: {o['migration']}" for o in rows_plot]
fig, ax = plt.subplots(figsize=(10, 0.42 * len(rows_plot) + 1.6), facecolor=SURF)
ax.set_facecolor(SURF)
for y, o in enumerate(rows_plot):
    left = 0
    for name, keys, col in SEG:
        n = sum(o[k] for k in keys)
        if n:
            ax.barh(y, n, left=left, height=0.62, color=col, edgecolor=SURF, linewidth=2)
            if n >= 2:
                ax.text(left + n / 2, y, str(n), ha="center", va="center", fontsize=7.5, color="#ffffff" if col != "#eda100" else INK)
        left += n
    ax.text(left + 1, y, f"compiles & correct {o['success_of_buildable']}/{o['buildable']}", va="center", fontsize=7.5, color=INK2)
ax.set_yticks(range(len(rows_plot)), labels)
ax.invert_yaxis()
ax.set_xlim(0, max(o["targets"] for o in rows_plot) * 1.45)
for side in ("top", "right", "left"):
    ax.spines[side].set_visible(False)
ax.spines["bottom"].set_color(GRID)
ax.tick_params(colors=INK2, labelsize=8, length=0)
ax.set_xlabel("held-out target conversions (20 per migration)", color=INK2, fontsize=8.5)
from matplotlib.patches import Patch
ax.legend(handles=[Patch(color=c, label=n) for n, _, c in SEG], loc="upper center", bbox_to_anchor=(0.45, -0.09), fontsize=7.5, frameon=False, ncol=4)
ax.set_title("H2 - Coccinelle rules derived only from 20 earlier sibling migrations, applied to held-out drivers",
             color=INK, fontsize=10, loc="left")
fig.tight_layout()
fig.savefig("results/h2_rules.png", dpi=150, facecolor=SURF)

for o in out:
    print(f"{o['source']:8} {o['migration']:20} correct {o['correct_any']}/{o['targets']}  success {o['success_of_buildable']}/{o['buildable']} buildable  "
          f"(exact {o['exact']}, equiv {o['correct_equivalent']}, alt {o['correct_alternative']}, partial {o['partial']}, wrong {o['wrong']}, "
          f"none {o['no_migration']}, unreviewed {o['unreviewed']})  {o['failure_categories']}")
