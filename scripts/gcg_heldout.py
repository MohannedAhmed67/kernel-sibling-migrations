#!/usr/bin/env python3
"""Held-out evaluation of every guided-rule-generation run (all configurations, seeds and models), with caching.

Same comparison as scripts/h2_eval.py (whitespace-normalised line multisets of removed/added lines vs `before`):
  exact | subset_complete | subset_incomplete | divergent | no_change | spatch_error | no_rule
success = (exact or subset_complete) AND the rule output compiles, counted over BUILDABLE targets (the original
file compiles). Compiling is done only where it can change the result: for the original and human versions of every
target and for rule outputs classed exact or subset_complete (a cache keyed on commit, file and content makes an
output identical to the human fix reuse the human build). Build recipe as in h2_eval.py (x86_64 allmodconfig,
CONFIG_WERROR off, fresh build directory per target commit).

Rule sources (one per model x configuration x seed):
  composed : work/gcg/composed/<model>/<config>/<mig>.cocci  (stage 3)
  critic   : work/gcg/final/<model>/<config>/<mig>.cocci     (stage 4; empty file = abstain = no_rule)
  extra rule folders via --rules-dirs (e.g. rules/manual rules/spinfer), evaluated the same way.

Usage: python3 scripts/gcg_heldout.py [--split data/h2_split.csv] [--out results/gcg_heldout] [--migration ...]
Output: <out>_rows.csv (one row per target x source), <out>_summary.csv (per source x migration and ALL)
"""
import argparse, collections, csv, glob, hashlib, json, os, re, subprocess, sys
from multiprocessing import Pool

sys.path.insert(0, os.path.dirname(__file__))
from gcg_critic import Builder  # noqa: E402
from h2_eval import MIGS, changes, norm_lines, spatch  # noqa: E402

LINUX = os.environ.get("LINUX", "/linux/linux")


def git_show(rev, path):
    return subprocess.run(["git", "-C", LINUX, "show", f"{rev}:{path}"], capture_output=True, text=True,
                          errors="replace").stdout


def sources_for(mig, rules_dirs):
    out = []
    for p in sorted(glob.glob(f"work/gcg/composed/*/*/{mig}.cocci")):
        model, config = p.split("/")[-3:-1]
        out.append(({"model": model, "config": config, "variant": "composed"}, p))
    for p in sorted(glob.glob(f"work/gcg/final/*/*/{mig}.cocci")):
        model, config = p.split("/")[-3:-1]
        out.append(({"model": model, "config": config, "variant": "critic"}, p))
    for d in rules_dirs:
        p = f"{d.rstrip('/')}/{mig}.cocci"
        out.append(({"model": os.path.basename(d.rstrip("/")), "config": "-", "variant": "rules"},
                    p if os.path.exists(p) else None))
    return out


def run_migration(job):
    mig, split, rules_dirs = job
    targets = sorted((r for r in csv.DictReader(open(split)) if r["migration"] == mig and r["role"] == "target"),
                     key=lambda r: int(r["idx"]))
    builder = Builder(mig, tag="eval")
    old_rx = re.compile(MIGS[mig]["old"])
    srcs = sources_for(mig, rules_dirs)
    rows = []
    for t in targets:
        T, F, idx = t["commit"], t["file"], int(t["idx"])
        d = f"work/gcg/heldout/{mig}/{idx:02d}"
        os.makedirs(d, exist_ok=True)
        if not os.path.exists(f"{d}/before.c"):
            open(f"{d}/before.c", "w").write(git_show(f"{T}^", F))
            open(f"{d}/human.c", "w").write(git_show(T, F))
        before, human = open(f"{d}/before.c").read(), open(f"{d}/human.c").read()
        b_orig = builder.build(T, F, before)
        b_human = builder.build(T, F, human) if b_orig["ok"] else {"ok": None}
        H = changes(before, human)
        for meta, rule in srcs:
            base = {**meta, "migration": mig, "idx": idx, "commit": T, "file": F,
                    "build_original": b_orig["ok"], "build_human": b_human["ok"]}
            if rule is None or not open(rule).read().strip():
                rows.append({**base, "auto_class": "no_rule"}); continue
            rh = hashlib.sha1(open(rule, "rb").read()).hexdigest()[:16]
            out_path = f"{d}/{rh}.c"
            if os.path.exists(out_path):
                out = open(out_path, errors="replace").read()
            elif os.path.exists(f"{d}/{rh}.err"):
                out = None
            else:
                rc, err, out = spatch(rule, f"{d}/before.c", out_path)
                if out is None:
                    open(f"{d}/{rh}.err", "w").write(err)
            if out is None:
                rows.append({**base, "auto_class": "spatch_error"}); continue
            R = changes(before, out)
            if norm_lines(out) == norm_lines(human):
                cls = "exact"
            elif not R:
                cls = "no_change"
            elif not (R - H):
                cls = "subset_complete" if len(old_rx.findall(out)) <= len(old_rx.findall(human)) else "subset_incomplete"
            else:
                cls = "divergent"
            ok_rule = ""
            if b_orig["ok"] and cls in ("exact", "subset_complete"):
                ok_rule = builder.build(T, F, out)["ok"]
            rows.append({**base, "auto_class": cls, "build_rule": ok_rule,
                         "success": int(bool(b_orig["ok"]) and cls in ("exact", "subset_complete") and ok_rule is True),
                         "human_changed_lines": sum(H.values()), "rule_changed_lines": sum(R.values()),
                         "shared_changed_lines": sum((H & R).values())})
        print(f"{mig} #{idx}: orig={b_orig['ok']} " +
              " ".join(f"{r['model'][:5]}/{r['config']}/{r['variant'][0]}={r['auto_class'][:5]}"
                       for r in rows if r["idx"] == idx and r.get("success")), flush=True)
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--split", default="data/h2_split.csv")
    ap.add_argument("--out", default="results/gcg_heldout")
    ap.add_argument("--migration", nargs="+")
    ap.add_argument("--rules-dirs", nargs="*", default=[])
    args = ap.parse_args()
    migs = args.migration or sorted({r["migration"] for r in csv.DictReader(open(args.split))})
    with Pool(len(migs)) as p:
        rows = [r for rs in p.map(run_migration, [(m, args.split, args.rules_dirs) for m in migs]) for r in rs]
    fields = ["model", "config", "variant", "migration", "idx", "commit", "file", "auto_class", "success",
              "build_original", "build_human", "build_rule", "human_changed_lines", "rule_changed_lines",
              "shared_changed_lines"]
    with open(f"{args.out}_rows.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, lineterminator="\n", extrasaction="ignore")
        w.writeheader(); w.writerows(rows)
    groups = collections.defaultdict(list)
    for r in rows:
        k = (r["model"], r["config"], r["variant"])
        groups[k + (r["migration"],)].append(r)
        groups[k + ("ALL",)].append(r)
    out = []
    for (m, c, v, g), rs in sorted(groups.items()):
        buildable = [r for r in rs if r["build_original"] is True]
        cnt = collections.Counter(r["auto_class"] for r in rs)
        out.append({"model": m, "config": c, "variant": v, "migration": g, "targets": len(rs),
                    "buildable": len(buildable), "success": sum(r.get("success", 0) for r in buildable),
                    **{k: cnt.get(k, 0) for k in ("exact", "subset_complete", "subset_incomplete", "divergent",
                                                  "no_change", "spatch_error", "no_rule")},
                    "subset_or_exact_not_compiling": sum(r["auto_class"] in ("exact", "subset_complete") and
                                                         r.get("build_rule") is False for r in buildable)})
    with open(f"{args.out}_summary.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(out[0]), lineterminator="\n")
        w.writeheader(); w.writerows(out)
    for o in out:
        if o["migration"] == "ALL":
            print(f"{o['model']:18} {o['config']:18} {o['variant']:8} success {o['success']}/{o['buildable']}")


if __name__ == "__main__":
    main()
