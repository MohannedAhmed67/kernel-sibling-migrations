#!/usr/bin/env python3
"""Turn raw mined hits into candidate conversions and per-migration summaries.

A (commit, file) is a candidate *conversion* for a migration if, in that commit's diff of that file,
>=1 removed line matches the migration's OLD regex and >=1 added line matches its NEW regex.

Outputs
  data/conversions_candidates.csv  one row per (migration, commit, file) candidate conversion
  data/migration_summary.csv       one row per migration with counts used to pick cases

"Same commit" siblings are NOT earlier siblings: a commit that converts many files at once
(a tree-wide change) gives no chronological signal, so we report how concentrated each migration is.
"""
import csv, collections, datetime as dt

HITS = "data/mined_hits.csv"
CONV = "data/conversions_candidates.csv"
SUMM = "data/migration_summary.csv"


def iso(ts):
    return dt.datetime.fromtimestamp(int(ts), dt.timezone.utc).strftime("%Y-%m-%d")


def main():
    conv = []
    with open(HITS, newline="") as f:
        for r in csv.DictReader(f):
            if not r["file"].endswith((".c", ".h")):
                continue
            if int(r["old_removed"]) > 0 and int(r["new_added"]) > 0:
                conv.append(r)

    files_per_commit = collections.Counter((r["migration"], r["commit"]) for r in conv)
    conv.sort(key=lambda r: (r["migration"], int(r["commit_time"]), r["commit"], r["file"]))

    with open(CONV, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["migration", "commit", "author_date", "commit_date", "commit_time", "file",
                    "old_removed", "old_added", "new_added", "files_converted_in_commit", "subject"])
        for r in conv:
            w.writerow([r["migration"], r["commit"], iso(r["author_time"]), iso(r["commit_time"]),
                        r["commit_time"], r["file"], r["old_removed"], r["old_added"], r["new_added"],
                        files_per_commit[(r["migration"], r["commit"])], r["subject"]])

    by_mig = collections.defaultdict(list)
    for r in conv:
        by_mig[r["migration"]].append(r)

    with open(SUMM, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["migration", "conversions", "distinct_files", "distinct_commits",
                    "first_commit_date", "last_commit_date", "max_files_in_one_commit",
                    "share_in_largest_commit", "commits_with_1_file"])
        for mig in sorted(by_mig):
            rows = by_mig[mig]
            commits = collections.Counter(r["commit"] for r in rows)
            biggest = max(commits.values())
            w.writerow([mig, len(rows), len({r["file"] for r in rows}), len(commits),
                        iso(min(int(r["commit_time"]) for r in rows)),
                        iso(max(int(r["commit_time"]) for r in rows)),
                        biggest, f"{biggest / len(rows):.3f}",
                        sum(1 for c in commits.values() if c == 1)])
    print(f"{len(conv)} candidate conversions across {len(by_mig)} migrations -> {CONV}, {SUMM}")


if __name__ == "__main__":
    main()
