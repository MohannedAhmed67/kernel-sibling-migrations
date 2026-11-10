#!/usr/bin/env python3
"""When did each new API appear in include/, and when was each old API removed from include/?

new API: if a header line matching hdr_new already exists at v5.10 -> "before v5.10";
         else the first commit in v5.10..v6.10 that adds such a line (git log -G --reverse).
old API: if a header line matching hdr_old still exists at v6.10 -> "still present at v6.10";
         else the last commit in v5.10..v6.10 whose diff adds/removes such a line (git log -G).
Output: data/api_events.csv
"""
import csv, json, os, subprocess

LINUX = os.environ.get("LINUX", "/linux/linux")


def git(*a):
    return subprocess.run(["git", "-C", LINUX, "-c", "gc.auto=0", *a],
                          capture_output=True, text=True, errors="replace").stdout


def present(tag, rx):
    return subprocess.run(["git", "-C", LINUX, "grep", "-q", "-P", rx, tag, "--", "include"],
                          capture_output=True).returncode == 0


def first_last(rx, first):
    args = ["log", "--no-merges", "--format=%H %cs %s", f"-G{rx}", "v5.10..v6.10", "--", "include"]
    if first:
        args.insert(1, "--reverse")
    out = git(*args).splitlines()
    return out[0] if out else ""


migs = json.load(open("data/migrations.json"))["migrations"]
with open("data/api_events.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["migration", "new_api_status", "new_api_commit", "new_api_date", "new_api_subject",
                "old_api_status", "old_api_commit", "old_api_date", "old_api_subject"])
    for m in migs:
        row = [m["id"]]
        for key, first, at, label_in, label_out in [
            ("hdr_new", True, "v5.10", "before v5.10", "introduced in window"),
            ("hdr_old", False, "v6.10", "still present at v6.10", "removed in window")]:
            rx = m.get(key)
            if not rx:
                row += ["n/a", "", "", ""]
            elif present(at, rx):
                row += [label_in, "", "", ""]
            else:
                hit = first_last(rx, first)
                h, d, s = (hit.split(" ", 2) + ["", "", ""])[:3] if hit else ("", "", "")
                row += [label_out if hit else "not found", h[:12], d, s]
        w.writerow(row)
        print(row[0], row[1], row[2], row[5], row[6], flush=True)
print("wrote data/api_events.csv")
