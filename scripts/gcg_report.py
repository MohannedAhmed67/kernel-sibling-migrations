#!/usr/bin/env python3
"""Summarise guided-rule-generation runs (stage 2, training siblings only; no held-out target is read).

Input : work/gcg/runs/<model>/<config>/<migration>/<task>/summary.json  (from scripts/gcg_leaf.py)
Output: results/gcg_stage2_tasks.csv  one row per (model, config, migration, task)
        results/gcg_stage2_summary.csv one row per (model, config, migration):
          tasks, tasks_passed (rule reproduces every expected unit in every training file of the task with
          no extra edit), units_hit / units_need over all tasks, extra edits, model calls and seconds
"""
import collections, csv, glob, json, os, pathlib

rows = []
for p in sorted(glob.glob("work/gcg/runs/*/*/*/*/summary.json")):
    s = json.load(open(p))
    model, config = pathlib.PurePath(p).parts[3:5]
    b = s["best"]
    rows.append({"model": model, "config": config, "migration": s["migration"], "task": s["task"],
                 "leaves": " ".join(s["leaves"]), "interface": s.get("interface") or "",
                 "passed": int(s["passed"]), "best_round": s["best_round"], "files": b["files"],
                 "files_pass": b["pass"], "units_hit": b["hit"], "units_need": b["need"], "extra": b["extra"],
                 "spatch_error": int(bool(b["spatch_error"])), "calls": len(s["rounds"]),
                 "seconds": round(sum(r.get("seconds", 0) for r in s["rounds"]), 1)})
os.makedirs("results", exist_ok=True)
if not rows:
    raise SystemExit("no runs found")
with open("results/gcg_stage2_tasks.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0]))
    w.writeheader()
    w.writerows(rows)

agg = collections.OrderedDict()
for r in rows:
    a = agg.setdefault((r["model"], r["config"], r["migration"]),
                       {"tasks": 0, "tasks_passed": 0, "units_hit": 0, "units_need": 0, "extra": 0, "calls": 0,
                        "seconds": 0.0})
    a["tasks"] += 1
    a["tasks_passed"] += r["passed"]
    for k in ("units_hit", "units_need", "extra", "calls", "seconds"):
        a[k] += r[k]
out = [{"model": m, "config": c, "migration": g, **{k: (round(v, 1) if isinstance(v, float) else v)
                                                     for k, v in a.items()}}
       for (m, c, g), a in agg.items()]
with open("results/gcg_stage2_summary.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(out[0]))
    w.writeheader()
    w.writerows(out)
for o in out:
    print(f"{o['model']:18} {o['config']:14} {o['migration']:20} tasks {o['tasks_passed']}/{o['tasks']}  "
          f"units {o['units_hit']}/{o['units_need']}  extra {o['extra']}  calls {o['calls']}  {o['seconds']}s")
