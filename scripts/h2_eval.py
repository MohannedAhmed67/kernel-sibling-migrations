#!/usr/bin/env python3
"""H2 evaluation: apply sibling-derived Coccinelle rules to held-out targets, compare with the human fix, compile.

For each sampled target (data/h2_split.csv, role=target) and each rule source (rules/<source>/<migration>.cocci):
  before = file at the target commit's parent (T^), human = file at T
  rule   = spatch(rule, before)
Line comparison (whitespace-normalised; multisets of removed '-' and added '+' lines vs `before`):
  H = changes made by the human, R = changes made by the rule
  exact             rule output == human output
  subset_complete   R is contained in H, and the rule output has no more OLD-API uses than the human output
                    (the human made extra edits the rule did not; reviewed later to check they are unrelated)
  subset_incomplete R is contained in H, but more OLD-API uses remain than in the human output
  divergent         the rule made a change the human did not (reviewed later: equivalent alternative or wrong)
  no_change         the rule changed nothing
  spatch_error      spatch failed
Compile: in a worktree at T^ (x86_64 allmodconfig with CONFIG_WERROR off) build the file's object with
  original, human and rule versions. If the ORIGINAL does not compile, the target is "not buildable".

Outputs: results/<H2_OUT>_rules.csv (one row per target x source), results/<H2_OUT>_summary.csv (H2_OUT=h2),
         work/h2/eval/<migration>/<idx>/ (all versions and build logs; git-ignored)
"""
import collections, csv, difflib, json, os, re, shutil, subprocess, sys
from multiprocessing import Pool

LINUX = os.environ.get("LINUX", "/linux/linux")
# H2_SOURCES (comma-separated rules/ folders) and H2_OUT (output prefix) let later rule sources be evaluated
# with the same harness without overwriting the Phase-3 tables; the defaults reproduce Phase 3 exactly.
SOURCES = [s for s in os.environ.get("H2_SOURCES", "manual,spinfer").split(",") if os.path.isdir(f"rules/{s}")]
OUT = os.environ.get("H2_OUT", "h2")
JOBS = int(os.environ.get("H2_JOBS", "4"))
MIGS = {m["id"]: m for m in json.load(open("data/migrations.json"))["migrations"]}


def sh(cmd, cwd=None, timeout=1800):
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, errors="replace", timeout=timeout)
    return p.returncode, p.stdout, p.stderr


def norm_lines(text):
    return [re.sub(r"\s+", " ", l).strip() for l in text.splitlines() if l.strip()]


def changes(a, b):
    c = collections.Counter()
    for l in difflib.unified_diff(norm_lines(a), norm_lines(b), lineterm="", n=0):
        if l.startswith(("---", "+++", "@@")):
            continue
        if l[:1] in "+-":
            c[(l[0], l[1:])] += 1
    return c


def spatch(rule, before_path, out_path):
    if os.path.exists(out_path):
        os.remove(out_path)
    rc, out, err = sh(["spatch", "--very-quiet", "--timeout", "300", "--sp-file", rule, before_path, "-o", out_path], timeout=900)
    if not os.path.exists(out_path):
        if rc == 0 or "no modified files" in err:
            shutil.copy(before_path, out_path)   # spatch writes nothing (and may exit non-zero) when there is no change
        else:
            return rc, err[-2000:], None
    return rc, err[-2000:], open(out_path, errors="replace").read()


def build(wt, bdir, rel, content, log_path):
    src = os.path.join(wt, rel)
    orig = open(src, errors="replace").read()
    open(src, "w").write(content)
    obj = rel[:-2] + ".o"
    try:
        os.remove(os.path.join(bdir, obj))
    except FileNotFoundError:
        pass
    rc, out, err = sh(["make", "-s", f"-j{JOBS}", f"O={bdir}", obj], cwd=wt)
    open(src, "w").write(orig)
    open(log_path, "w").write(out + err)
    ok = rc == 0 and os.path.exists(os.path.join(bdir, obj))
    errs = [l for l in err.splitlines() if " error: " in l or l.startswith("make") and "Error" in l]
    return ok, " | ".join(errs[:3])[:500]


def run_migration(mig):
    targets = [r for r in csv.DictReader(open("data/h2_split.csv")) if r["migration"] == mig and r["role"] == "target"]
    wt, bdir = f"/linux/wt/{mig}", f"/linux/build/{mig}"
    if not os.path.isdir(wt):
        sh(["git", "-C", LINUX, "-c", "gc.auto=0", "worktree", "add", "-q", "--detach", wt, "HEAD"])
    os.makedirs(bdir, exist_ok=True)
    old_rx = re.compile(MIGS[mig]["old"])
    rows = []
    for t in sorted(targets, key=lambda r: (r["commit_date"], int(r["idx"]))):
        T, F, idx = t["commit"], t["file"], t["idx"]
        d = f"work/h2/eval/{mig}/{int(idx):02d}"
        os.makedirs(d, exist_ok=True)
        sh(["git", "-C", wt, "-c", "gc.auto=0", "checkout", "-q", "--detach", "--force", f"{T}^"])
        sh(["git", "-C", wt, "clean", "-q", "-fdx"])
        # Fresh build directory per target: stale dependency files from another kernel version can break
        # host-tool builds (e.g. objtool), which made results depend on run order.
        shutil.rmtree(bdir, ignore_errors=True)
        os.makedirs(bdir, exist_ok=True)
        sh(["make", "-s", f"O={bdir}", "allmodconfig"], cwd=wt)
        sh(["./scripts/config", "--file", f"{bdir}/.config", "-d", "WERROR"], cwd=wt)
        sh(["make", "-s", f"O={bdir}", "olddefconfig"], cwd=wt)
        before = sh(["git", "-C", LINUX, "show", f"{T}^:{F}"])[1]
        human = sh(["git", "-C", LINUX, "show", f"{T}:{F}"])[1]
        n_files = len(sh(["git", "-C", LINUX, "show", "--format=", "--name-only", T])[1].split())
        open(f"{d}/before.c", "w").write(before)
        open(f"{d}/human.c", "w").write(human)
        ok_orig, err_orig = build(wt, bdir, F, before, f"{d}/build_original.log")
        ok_human, err_human = build(wt, bdir, F, human, f"{d}/build_human.log") if ok_orig else (None, "")
        H = changes(before, human)
        for src in SOURCES:
            rule = f"rules/{src}/{mig}.cocci"
            base = {"migration": mig, "idx": idx, "commit": T, "file": F, "commit_date": t["commit_date"], "source": src,
                    "all_train_commits_are_ancestors": t["all_train_commits_are_ancestors"], "files_in_human_commit": n_files,
                    "build_original": ok_orig, "build_human": ok_human}
            if not os.path.exists(rule):
                rows.append({**base, "auto_class": "no_rule"}); continue
            rc, err, out = spatch(rule, f"{d}/before.c", f"{d}/{src}.c")
            if out is None:
                rows.append({**base, "spatch_rc": rc, "auto_class": "spatch_error", "notes": err[-300:]}); continue
            R = changes(before, out)
            inter = sum((H & R).values())
            old_rule, old_human = len(old_rx.findall(out)), len(old_rx.findall(human))
            if norm_lines(out) == norm_lines(human):
                cls = "exact"
            elif not R:
                cls = "no_change"
            elif not (R - H):
                cls = "subset_complete" if old_rule <= old_human else "subset_incomplete"
            else:
                cls = "divergent"
            ok_rule, err_rule = (None, "")
            if ok_orig and R:
                ok_rule, err_rule = build(wt, bdir, F, out, f"{d}/build_{src}.log")
            elif ok_orig:
                ok_rule = ok_orig  # unchanged file: same as original
            rows.append({**base, "spatch_rc": rc, "auto_class": cls,
                         "human_changed_lines": sum(H.values()), "rule_changed_lines": sum(R.values()), "shared_changed_lines": inter,
                         "line_recall": f"{inter / sum(H.values()):.3f}" if H else "",
                         "line_precision": f"{inter / sum(R.values()):.3f}" if R else "",
                         "old_api_left_rule": old_rule, "old_api_left_human": old_human,
                         "build_rule": ok_rule, "build_error": (err_rule or "")[:300]})
        print(f"{mig} #{idx} {F}: orig={ok_orig} human={ok_human} " +
              " ".join(f"{r['source']}={r['auto_class']}/{r.get('build_rule')}" for r in rows if r['idx'] == idx), flush=True)
        sh(["git", "-C", wt, "checkout", "-q", "--force", "--", "."])
    return rows


def main():
    migs = sys.argv[1:] or sorted({r["migration"] for r in csv.DictReader(open("data/h2_split.csv"))})
    with Pool(len(migs)) as p:
        allrows = [r for rows in p.map(run_migration, migs) for r in rows]
    fields = ["migration", "idx", "commit", "file", "commit_date", "source", "auto_class", "build_original", "build_human",
              "build_rule", "build_error", "spatch_rc", "human_changed_lines", "rule_changed_lines", "shared_changed_lines",
              "line_recall", "line_precision", "old_api_left_rule", "old_api_left_human", "files_in_human_commit",
              "all_train_commits_are_ancestors", "notes"]
    os.makedirs("results", exist_ok=True)
    with open(f"results/{OUT}_rules.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, lineterminator="\n", extrasaction="ignore")
        w.writeheader(); w.writerows(sorted(allrows, key=lambda r: (r["migration"], r["source"], int(r["idx"]))))
    summarize(allrows)


def summarize(rows):
    out = []
    groups = collections.defaultdict(list)
    for r in rows:
        groups[(r["migration"], r["source"])].append(r)
        groups[("ALL", r["source"])].append(r)
    for (m, s), rs in sorted(groups.items(), key=lambda x: (x[0][1], x[0][0] == "ALL", x[0][0])):
        n = len(rs)
        buildable = [r for r in rs if r["build_original"] is True]
        c = collections.Counter(r["auto_class"] for r in rs)
        good = [r for r in buildable if r["auto_class"] in ("exact", "subset_complete") and r.get("build_rule") is True]
        out.append({"migration": m, "source": s, "targets": n, "buildable": len(buildable),
                    **{k: c.get(k, 0) for k in ("exact", "subset_complete", "subset_incomplete", "divergent", "no_change", "spatch_error", "no_rule")},
                    "rule_compiles_of_buildable": sum(r.get("build_rule") is True for r in buildable),
                    "human_compiles_of_buildable": sum(r["build_human"] is True for r in buildable),
                    "exact_or_subset_complete_and_compiles": len(good)})
    with open(f"results/{OUT}_summary.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(out[0]), lineterminator="\n")
        w.writeheader(); w.writerows(out)
    for o in out:
        print(o)


if __name__ == "__main__":
    main()
