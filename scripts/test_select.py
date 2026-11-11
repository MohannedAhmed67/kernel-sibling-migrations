#!/usr/bin/env python3
"""Apply the pre-registered test-set inclusion rule (docs/test_set_rule.md) to the mined candidates.

Inputs : data/test/{migrations.json, mined_hits.csv, conversions_candidates.csv, migration_summary.csv}
         data/test/verification.csv (optional: verdicts for the sampled candidates)
Outputs: data/test/api_events.csv    when each new API first appears in include/ (v6.10..v7.4-rc2)
         data/test/verify_sample.csv up to 8 candidate conversions per migration, spread over time, to review
         data/test/cases.csv         one row per candidate migration: included yes/no and the reasons
         data/test/conversions.csv   candidate conversions of the INCLUDED migrations (input of h2_split.py)
"""
import csv, json, math, os, subprocess

LINUX = os.environ.get("LINUX", "/linux/linux")
RANGE, BASE, CUTOFF = "v6.10..v7.4-rc2", "v6.10", "2024-09-01"
MIN_COMMITS, MIN_TRAIN, MIN_TARGETS, MIN_PRECISION, N_VERIFY = 3, 5, 10, 0.85, 8
TRAIN_FRAC, MAX_TRAIN = 0.30, 20          # as in scripts/h2_split.py


def git(*a):
    return subprocess.run(["git", "-C", LINUX, "-c", "gc.auto=0", *a], capture_output=True, text=True,
                          errors="replace")


def read(p):
    return list(csv.DictReader(open(p, newline=""))) if os.path.exists(p) else []


migs = json.load(open("data/test/migrations.json"))["migrations"]
summ = {r["migration"]: r for r in read("data/test/migration_summary.csv")}
cands = read("data/test/conversions_candidates.csv")
author = {r["commit"]: int(r["author_time"]) for r in read("data/test/mined_hits.csv")}

events = {}
for m in migs:
    if git("grep", "-q", "-P", m["hdr_new"], BASE, "--", "include").returncode == 0:
        events[m["id"]] = ("present at v6.10", "", "")
    else:
        out = git("log", "--no-merges", "--reverse", "--format=%H %cs", f"-G{m['hdr_new']}", RANGE, "--", "include")
        first = out.stdout.split("\n")[0].split()
        events[m["id"]] = ("introduced in window", first[0][:12], first[1]) if first else ("not found", "", "")
with open("data/test/api_events.csv", "w", newline="") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(["migration", "new_api_status", "new_api_commit", "new_api_date"])
    for m in migs:
        w.writerow([m["id"], *events[m["id"]]])


def split_sizes(mig):
    conv = sorted((r for r in cands if r["migration"] == mig and r["file"].endswith(".c")),
                  key=lambda r: (int(r["commit_time"]), r["commit"], r["file"]))
    if not conv:
        return 0, 0
    n_train = min(MAX_TRAIN, math.ceil(TRAIN_FRAC * len(conv)))
    train, seen = [], set()
    for r in conv:
        if len(train) == n_train:
            break
        if r["file"] not in seen:
            seen.add(r["file"]); train.append(r)
    cut = max(int(r["commit_time"]) for r in train)
    tc = {r["commit"] for r in train}
    eligible = [r for r in conv if author[r["commit"]] > cut and r["file"] not in seen and r["commit"] not in tc]
    return len(train), len(eligible)


ver = {}
for r in read("data/test/verification.csv"):
    v = ver.setdefault(r["migration"], [0, 0])
    v[0] += 1
    v[1] += r["verdict"] in ("genuine", "partial")

sample, cases, included = [], [], set()
for m in migs:
    mid, s = m["id"], summ.get(m["id"])
    status, _, date = events[mid]
    n_train, n_elig = split_sizes(mid)
    reasons = []
    if status != "introduced in window" or date < CUTOFF:
        reasons.append(f"new API not new ({status}{' ' + date if date else ''})")
    if not s or int(s["distinct_commits"]) < MIN_COMMITS:
        reasons.append(f"only {s['distinct_commits'] if s else 0} commit(s)")
    if n_train < MIN_TRAIN or n_elig < MIN_TARGETS:
        reasons.append(f"split too small (train {n_train}, eligible targets {n_elig})")
    if not reasons:   # only migrations that pass rules 1, 2 and 4 are sampled for verification
        rows = sorted((r for r in cands if r["migration"] == mid), key=lambda r: (int(r["commit_time"]), r["file"]))
        k = min(N_VERIFY, len(rows))
        for i in sorted({round(j * (len(rows) - 1) / max(k - 1, 1)) for j in range(k)}):
            sample.append({"migration": mid, "commit": rows[i]["commit"], "file": rows[i]["file"],
                           "commit_date": rows[i]["commit_date"], "subject": rows[i]["subject"]})
        v = ver.get(mid)
        if not v:
            reasons.append("not verified yet")
        elif v[1] / v[0] < MIN_PRECISION:
            reasons.append(f"precision {v[1]}/{v[0]} < {MIN_PRECISION}")
    inc = not reasons
    if inc:
        included.add(mid)
    cases.append({"migration": mid, "included": "yes" if inc else "no", "reason": "; ".join(reasons) or "meets rule",
                  "new_api_status": status, "new_api_date": date, "conversions": s["conversions"] if s else 0,
                  "distinct_commits": s["distinct_commits"] if s else 0,
                  "share_in_largest_commit": s["share_in_largest_commit"] if s else "",
                  "train": n_train, "eligible_targets": n_elig,
                  "verified": f"{ver[mid][1]}/{ver[mid][0]}" if mid in ver else ""})

with open("data/test/verify_sample.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(sample[0]), lineterminator="\n")
    w.writeheader(); w.writerows(sample)
with open("data/test/cases.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(cases[0]), lineterminator="\n")
    w.writeheader(); w.writerows(cases)
rows = [r for r in cands if r["migration"] in included]
with open("data/test/conversions.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(cands[0].keys()), lineterminator="\n")
    w.writeheader(); w.writerows(rows)
for c in cases:
    print(f"{c['migration']:26} {c['included']:3} {c['reason']}")
