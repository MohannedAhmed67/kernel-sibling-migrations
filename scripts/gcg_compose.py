#!/usr/bin/env python3
"""Guided rule generation, stage 3: compose the per-leaf rules of one migration into a single semantic patch.

No model call. Only training siblings are read; held-out targets are never opened here.

Input : work/gcg/<mig>/tree.json (stage 1) and work/gcg/runs/<model>/<config>/<mig>/<task>/summary.json (stage 2)
Method: candidates = task rules that spatch accepts and that reproduce at least one expected unit on training.
        Each candidate's rules are renamed with a task prefix so names cannot collide; a companion rule that
        depends on an anchor rule (stage-2 interface) brings that anchor with it and points at it.
        Greedy forward selection on the training siblings: candidates are tried in order of their own
        (hit - extra); one is kept only if the composed patch still parses and its score
        hit - extra over all training files of the migration strictly increases, where
          expected = units of all task leaves in that file (stage-1 tree)
          hit      = |expected ∩ produced|,  extra = |produced minus every unit the human changed in that file|
Output: work/gcg/composed/<model>/<config>/<mig>.cocci and .json (selection log),
        rules/gcg_<model>/<mig>.cocci for the main config (--publish), results/gcg_stage3_compose.csv

Usage: python3 scripts/gcg_compose.py [--config leaf_g_r3_s1] [--publish]
"""
import argparse, collections, csv, glob, json, os, re, sys

sys.path.insert(0, os.path.dirname(__file__))
from gcg_leaf import spatch, split_rules, unit_changes  # noqa: E402

SHORT = {"qwen2.5-coder_7b": "qwen", "llama3.1_8b": "llama", "gemma3_4b": "gemma"}


def rename(text, prefix, extra_map=None):
    """Prefix every rule name in `text`; `extra_map` maps names defined elsewhere (an anchor) to their new names."""
    rules = split_rules(text)
    names = [re.match(r"@\s*(\w+)", h).group(1) for h, _, _ in rules
             if h and h != "@@" and re.match(r"@\s*(\w+)", h) and
             not re.match(r"@\s*(depends|script|initialize|finalize)\b", h)]
    m = {n: f"{prefix}_{n}" for n in names}
    m.update(extra_map or {})
    if not m:
        return text, m
    rx = re.compile(r"\b(" + "|".join(map(re.escape, sorted(m, key=len, reverse=True))) + r")\b")

    def sub_header(h):  # name and 'depends on' expression
        return rx.sub(lambda x: m[x.group(1)], h)

    def sub_ref(line):  # inherited metavariables 'name.var'
        return re.sub(r"\b(\w+)\.(\w+)", lambda x: f"{m.get(x.group(1), x.group(1))}.{x.group(2)}", line)

    out = []
    for h, decls, code in rules:
        parts = [] if h is None else [sub_header(h)]
        if h is not None:
            parts += [sub_ref(d) for d in decls] + ["@@"]
        parts += code   # code lines use inherited metavariables without the rule prefix; left untouched
        out.append("\n".join(parts))
    return "\n\n".join(o.strip("\n") for o in out) + "\n", m


def first_rule_named(text, name):
    """Give the first rule of `text` the name `name` (whatever it was called before)."""
    return re.sub(r"\A(\s*)@[^@\n]*@", lambda x: f"{x.group(1)}@{name}@", text, count=1)


def candidate_text(s, by_task):
    """Rule text contributed by one task, with unique names. Companion tasks carry their anchor rule."""
    task = s["task"].lower()
    rule = s["rule"]
    iface = s.get("interface")
    if not iface:
        return rename(rule, task)[0], [s["task"]]
    anchor = by_task[iface]
    n_anchor = len(split_rules(anchor["rule"]))
    rules = split_rules(rule)
    anchor_name = re.match(r"\s*@\s*(\w+)", rule).group(1)        # name the interface gave the anchor's first rule
    comp = "\n\n".join(("" if h is None else h + "\n" + "\n".join(d) + "\n@@\n") + "\n".join(c)
                       for h, d, c in rules[n_anchor:])
    a_text = first_rule_named(anchor["rule"], f"{iface.lower()}_r0")
    a_text, a_map = rename(a_text, iface.lower())
    c_text, _ = rename(comp, task, {anchor_name: f"{iface.lower()}_r0"})
    return a_text + "\n" + c_text, [iface, s["task"]]


def score(rule_path, mig, expected_by_file, scratch):
    hit = extra = 0
    for k, expected in sorted(expected_by_file.items()):
        d = f"work/h2/{mig}/train/{k}"
        before = open(f"{d}/before.c", errors="replace").read()
        human = unit_changes(before, open(f"{d}/after.c", errors="replace").read())
        out, err = spatch(rule_path, f"{d}/before.c", f"{scratch}/{k}.out.c")
        if out is None:
            return None, err
        produced = unit_changes(before, out)
        hit += sum((expected & produced).values())
        extra += sum((produced - human).values())
    return (hit, extra), ""


def training_expected(mig, tree):
    """Per training file: the units of all task leaves (what a complete rule should change there)."""
    expected = collections.defaultdict(collections.Counter)
    for leaf in tree["leaves"]:
        if leaf["is_task"]:
            for h in leaf["hunks"]:
                expected[h["sibling"]].update(("-", u) for u in h["removed"])
                expected[h["sibling"]].update(("+", u) for u in h["added"])
    files = sorted(k for k in os.listdir(f"work/h2/{mig}/train") if os.path.isdir(f"work/h2/{mig}/train/{k}"))
    return {k: expected.get(k, collections.Counter()) for k in files}


def compose(model, config, mig, tree):
    """Greedy composition for one (model, config, migration); also used by gcg_critic.py for re-scoring."""
    expected = training_expected(mig, tree)
    need = sum(sum(c.values()) for c in expected.values())
    sums = [json.load(open(p)) for p in sorted(glob.glob(f"work/gcg/runs/{model}/{config}/{mig}/*/summary.json"))]
    by_task = {s["task"]: s for s in sums}
    cands = [s for s in sums if not s["best"]["spatch_error"] and s["best"]["hit"] > 0]
    cands.sort(key=lambda s: (-(s["best"]["hit"] - s["best"]["extra"]), s["task"]))
    out_dir = f"work/gcg/composed/{model}/{config}"
    scratch = f"{out_dir}/scratch_{mig}"
    os.makedirs(scratch, exist_ok=True)
    chosen, chosen_tasks, best, log, chunks = [], set(), (0, 0), [], []
    for s in cands:
        text, tasks = candidate_text(s, by_task)
        if set(tasks) <= chosen_tasks:
            continue
        trial = "\n".join(chosen + [text])
        path = f"{scratch}/trial.cocci"
        open(path, "w").write(trial)
        sc, err = score(path, mig, expected, scratch)
        ok = sc is not None and sc[0] - sc[1] > best[0] - best[1]
        log.append({"task": s["task"], "with": tasks, "score": sc, "kept": ok, "error": err[-300:] if sc is None else ""})
        if ok:
            chosen.append(text); chosen_tasks |= set(tasks); best = sc
            chunks.append({"tasks": tasks, "text": text})
    final = "\n".join(chosen)
    open(f"{out_dir}/{mig}.cocci", "w").write(final)
    json.dump({"migration": mig, "model": model, "config": config, "need": need, "hit": best[0], "extra": best[1],
               "tasks": sorted(chosen_tasks), "log": log,
               "chunks": chunks}, open(f"{out_dir}/{mig}.json", "w"), indent=1)
    return final, {"model": model, "config": config, "migration": mig, "candidates": len(cands),
                   "tasks_kept": " ".join(sorted(chosen_tasks)), "train_units_need": need,
                   "train_units_hit": best[0], "train_extra": best[1]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="leaf_g_r3_s1")
    ap.add_argument("--publish", action="store_true", help="also write rules/gcg_<model>/<mig>.cocci")
    args = ap.parse_args()
    rows = []
    for mdir in sorted(glob.glob(f"work/gcg/runs/*/{args.config}")):
        model = os.path.basename(os.path.dirname(mdir))
        for mig in sorted(d for d in os.listdir(mdir) if os.path.isdir(f"{mdir}/{d}")):
            tree = json.load(open(f"work/gcg/{mig}/tree.json"))
            final, row = compose(model, args.config, mig, tree)
            rows.append(row)
            print(f"{model:18} {mig:20} kept [{row['tasks_kept']}]  train {row['train_units_hit']}/"
                  f"{row['train_units_need']} extra {row['train_extra']}", flush=True)
            if args.publish and final.strip():
                d = f"rules/gcg_{SHORT.get(model, model)}"
                os.makedirs(d, exist_ok=True)
                open(f"{d}/{mig}.cocci", "w").write(
                    f"// Composed by scripts/gcg_compose.py from {model} ({args.config}) leaf rules; "
                    f"tasks {row['tasks_kept']}\n" + final)
    os.makedirs("results", exist_ok=True)
    path = "results/gcg_stage3_compose.csv"
    old = [r for r in csv.DictReader(open(path))] if os.path.exists(path) else []
    old = [r for r in old if r["config"] != args.config]
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]), lineterminator="\n")
        w.writeheader(); w.writerows(old + rows)


if __name__ == "__main__":
    main()
