#!/usr/bin/env python3
"""H2 step 1: chronological split per migration into TRAINING siblings and held-out TARGETS.

Training = the earliest conversions by commit time: ceil(30%) of the migration's conversions, capped at
           MAX_TRAIN, one file per conversion, .c files only.
Targets  = .c conversions whose patch was WRITTEN (author time) after the last training commit was committed,
           in a file that is not a training file and a commit that is not a training commit.
           That is the leakage rule: every training sibling is in a different file and existed before the target
           was written. We also record whether every training commit is a git ancestor of the target.
A deterministic sample of up to N_TARGETS targets, spread evenly over time, is evaluated.

Exports (git-ignored, regenerable): work/h2/<migration>/train/<k>/{before.c, after.c, change.diff, meta.json}
Output: data/h2_split.csv (one row per training sibling and per sampled target)
"""
import csv, json, math, os, subprocess

LINUX = os.environ.get("LINUX", "/linux/linux")
MIGRATIONS = ["ida_simple", "i2c_probe_new", "platform_remove_new", "strlcpy_strscpy", "pci_dma_wrappers"]
TRAIN_FRAC, MAX_TRAIN, N_TARGETS = 0.30, 20, 20


def git(*a, check=True):
    return subprocess.run(["git", "-C", LINUX, "-c", "gc.auto=0", *a], capture_output=True, text=True,
                          errors="replace", check=check)


at = {}
for r in csv.DictReader(open("data/mined_hits.csv", newline="")):
    at[r["commit"]] = int(r["author_time"])

rows = [r for r in csv.DictReader(open("data/conversions.csv", newline="")) if r["migration"] in MIGRATIONS]
out = []
for mig in MIGRATIONS:
    conv = sorted((r for r in rows if r["migration"] == mig and r["file"].endswith(".c")),
                  key=lambda r: (int(r["commit_time"]), r["commit"], r["file"]))
    n_train = min(MAX_TRAIN, math.ceil(TRAIN_FRAC * len(conv)))
    train, seen = [], set()
    for r in conv:
        if len(train) == n_train:
            break
        if r["file"] not in seen:
            seen.add(r["file"]); train.append(r)
    cut = max(int(r["commit_time"]) for r in train)
    train_commits = {r["commit"] for r in train}
    eligible = [r for r in conv if at[r["commit"]] > cut and r["file"] not in seen and r["commit"] not in train_commits]
    k = min(N_TARGETS, len(eligible))
    pick = sorted({round(i * (len(eligible) - 1) / max(k - 1, 1)) for i in range(k)})
    targets = [eligible[i] for i in pick]

    base = f"work/h2/{mig}/train"
    for i, r in enumerate(train):
        d = f"{base}/{i:02d}"
        os.makedirs(d, exist_ok=True)
        before = git("show", f"{r['commit']}^:{r['file']}").stdout
        after = git("show", f"{r['commit']}:{r['file']}").stdout
        diff = git("show", "--format=%s%n", r["commit"], "--", r["file"]).stdout
        open(f"{d}/before.c", "w").write(before)
        open(f"{d}/after.c", "w").write(after)
        open(f"{d}/change.diff", "w").write(diff)
        json.dump({"commit": r["commit"], "file": r["file"], "commit_date": r["commit_date"], "subject": r["subject"]},
                  open(f"{d}/meta.json", "w"), indent=1)
        out.append({"migration": mig, "role": "train", "idx": i, "commit": r["commit"], "file": r["file"],
                    "commit_date": r["commit_date"], "all_train_commits_are_ancestors": ""})
    for i, r in enumerate(targets):
        anc_ok = all(git("merge-base", "--is-ancestor", s, r["commit"], check=False).returncode == 0 for s in train_commits)
        out.append({"migration": mig, "role": "target", "idx": i, "commit": r["commit"], "file": r["file"],
                    "commit_date": r["commit_date"], "all_train_commits_are_ancestors": "yes" if anc_ok else "no"})
    print(f"{mig}: {len(conv)} .c conversions, train={len(train)} (cut {train[-1]['commit_date']}), "
          f"eligible targets={len(eligible)}, sampled={len(targets)}", flush=True)

with open("data/h2_split.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(out[0]), lineterminator="\n")
    w.writeheader(); w.writerows(out)
print("wrote data/h2_split.csv")
