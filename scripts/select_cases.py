#!/usr/bin/env python3
"""Apply the pre-registered selection rule (docs/selection_rule.md).

Inputs : data/verification.csv, data/migration_summary.csv, data/api_events.csv, data/conversions_candidates.csv
Outputs: data/verification_summary.csv  per-migration verified precision
         data/cases.csv                  one row per migration with the decision and key facts
         data/conversions.csv            candidate conversions of the INCLUDED migrations (the H1/H2 universe)
"""
import csv

MIN_PRECISION = 0.85
MIN_COMMITS = 3


def read(p):
    return list(csv.DictReader(open(p, newline="")))


ver = read("data/verification.csv")
summ = {r["migration"]: r for r in read("data/migration_summary.csv")}
events = {r["migration"]: r for r in read("data/api_events.csv")}

vs = {}
for r in ver:
    v = vs.setdefault(r["migration"], {"n": 0, "genuine": 0, "partial": 0, "not_migration": 0, "unclear": 0, "disputed": 0})
    v["n"] += 1
    v[r["final_verdict"]] += 1
    v["disputed"] += r["disputed"] == "yes"

with open("data/verification_summary.csv", "w", newline="") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(["migration", "sampled", "genuine", "partial", "not_migration", "unclear", "disputed_A_vs_B", "verified", "precision"])
    for m in sorted(vs):
        v = vs[m]; ok = v["genuine"] + v["partial"]
        w.writerow([m, v["n"], v["genuine"], v["partial"], v["not_migration"], v["unclear"], v["disputed"], ok, f"{ok / v['n']:.3f}"])

included = set()
with open("data/cases.csv", "w", newline="") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(["migration", "included", "reason", "verified", "sampled", "precision",
                "candidate_conversions", "distinct_files", "distinct_commits", "first_commit_date", "last_commit_date",
                "share_in_largest_commit", "new_api_status", "new_api_commit", "new_api_date",
                "old_api_status", "old_api_commit", "old_api_date", "old_api_removed_by_v6.10"])
    for m in sorted(summ):
        s, e, v = summ[m], events.get(m, {}), vs.get(m)
        ok = (v["genuine"] + v["partial"]) if v else 0
        prec = ok / v["n"] if v else 0.0
        reasons = []
        if not v:
            reasons.append("not verified")
        elif prec < MIN_PRECISION:
            reasons.append(f"precision {ok}/{v['n']} < {MIN_PRECISION}")
        if int(s["distinct_commits"]) < MIN_COMMITS:
            reasons.append(f"only {s['distinct_commits']} commit(s)")
        inc = not reasons
        if inc:
            included.add(m)
        w.writerow([m, "yes" if inc else "no", "; ".join(reasons) or "meets rule", ok, v["n"] if v else 0, f"{prec:.3f}",
                    s["conversions"], s["distinct_files"], s["distinct_commits"], s["first_commit_date"], s["last_commit_date"],
                    s["share_in_largest_commit"], e.get("new_api_status", ""), e.get("new_api_commit", ""), e.get("new_api_date", ""),
                    e.get("old_api_status", ""), e.get("old_api_commit", ""), e.get("old_api_date", ""),
                    {"removed in window": "yes", "still present at v6.10": "no"}.get(e.get("old_api_status", ""), "not checked")])

rows = [r for r in read("data/conversions_candidates.csv") if r["migration"] in included]
with open("data/conversions.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0]), lineterminator="\n")
    w.writeheader(); w.writerows(rows)
pairs = {(r["migration"], r["file"]) for r in rows}
stats = (f"included migrations: {len(included)} of {len(summ)}\ncandidate conversions: {len(rows)}\n"
         f"distinct (migration, file) pairs: {len(pairs)}\ndistinct files: {len({r['file'] for r in rows})}\n"
         f"distinct commits: {len({r['commit'] for r in rows})}\n")
open("data/cases_stats.txt", "w", newline="\n").write(stats)
print(stats + "-> data/cases.csv, data/conversions.csv, data/cases_stats.txt")
