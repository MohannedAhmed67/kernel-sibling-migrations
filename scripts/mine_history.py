#!/usr/bin/env python3
"""One pass over kernel history v5.10..v6.10 to find candidate API-migration commits.

For every non-merge commit touching the given paths, read its unified=0 diff once and, per file,
count removed/added lines that match each migration's 'old' and 'new' regex.
Output: data/mined_hits.csv, one row per (commit, file, migration) with any nonzero count.

The range is split into consecutive release windows (v5.10..v5.11, ..., v6.9..v6.10), which are
disjoint and together equal v5.10..v6.10, and mined in parallel.
"""
import csv, json, os, re, subprocess, sys
from multiprocessing import Pool

LINUX = os.environ.get("LINUX", "/linux/linux")
PATHS = ["drivers", "sound"]
TAGS = [f"v5.{i}" for i in range(10, 20)] + [f"v6.{i}" for i in range(0, 11)]
OUT = os.environ.get("MINE_OUT", "data/mined_hits.csv")
if os.environ.get("MINE_TAGS"):      # test set: MINE_TAGS="v6.10 v6.11 ... v7.4-rc2"
    TAGS = os.environ["MINE_TAGS"].split()

with open(os.environ.get("MINE_MIGRATIONS", "data/migrations.json")) as f:
    MIGS = json.load(f)["migrations"]
PAT = [(m["id"], re.compile(m["old"]), re.compile(m["new"])) for m in MIGS]
PREFILTER = re.compile("|".join(f"(?:{m['old']})|(?:{m['new']})" for m in MIGS))


def mine(window):
    a, b = window
    cmd = ["git", "-C", LINUX, "-c", "gc.auto=0", "log", "--no-merges", "--no-renames",
           "--format=@@@C\t%H\t%at\t%ct\t%s", "-p", "--unified=0", "--no-color",
           "--diff-algorithm=myers", f"{a}..{b}", "--", *PATHS]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, errors="replace", bufsize=1 << 20)
    rows, commit, path, counts = [], None, None, {}

    def flush():
        for (fp, mid), c in counts.items():
            rows.append([mid, *commit, fp, c[0], c[1], c[2], c[3], b])
        counts.clear()

    for line in p.stdout:
        if line.startswith("@@@C\t"):
            if commit:
                flush()
            _, h, at, ct, subj = line.rstrip("\n").split("\t", 4)
            commit, path = (h, at, ct, subj), None
            continue
        if line.startswith("+++ "):
            path = line[6:].rstrip("\n") if line.startswith("+++ b/") else None
            continue
        if line.startswith("--- ") or line.startswith("diff --git"):
            if line.startswith("diff --git"):
                path = None
            continue
        if not line or line[0] not in "+-":
            continue
        if path is None:  # deleted file: take path from '--- a/' is skipped; we ignore whole-file deletions
            continue
        body = line[1:]
        if not PREFILTER.search(body):
            continue
        sign = line[0]
        for mid, old, new in PAT:
            o, n = old.search(body), new.search(body)
            if not (o or n):
                continue
            c = counts.setdefault((path, mid), [0, 0, 0, 0])  # old_removed, old_added, new_removed, new_added
            if o:
                c[0 if sign == "-" else 1] += 1
            if n:
                c[2 if sign == "-" else 3] += 1
    if commit:
        flush()
    if p.wait() != 0:
        raise SystemExit(f"git log failed for {a}..{b}")
    return a, b, rows


def main():
    windows = list(zip(TAGS, TAGS[1:]))
    os.makedirs("data", exist_ok=True)
    total = 0
    with open(OUT, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["migration", "commit", "author_time", "commit_time", "subject", "file",
                    "old_removed", "old_added", "new_removed", "new_added", "window_end_tag"])
        with Pool(min(len(windows), os.cpu_count() or 4)) as pool:
            for a, b, rows in pool.imap_unordered(mine, windows):
                w.writerows(rows)
                total += len(rows)
                print(f"{a}..{b}: {len(rows)} rows", flush=True)
    print(f"wrote {OUT}: {total} rows")


if __name__ == "__main__":
    sys.exit(main())
