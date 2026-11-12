#!/usr/bin/env python3
"""Generate every number of the preprint from result files (no number is typed by hand into the paper).

Inputs : results/gcg_heldout_dev_summary.csv, results/gcg_heldout_test_summary.csv (scripts/gcg_heldout.py),
         data/h2_split.csv, data/test/h2_split.csv, data/test/cases.csv, results/gcg_stage2_tasks.csv,
         results/gcg_stage4_critic.csv
Outputs: paper/tables/{data,test_main,ablation,cost}.tex and paper/numbers.tex (\\newcommand macros)
         results/gcg_paper_numbers.csv (the same numbers, machine-readable)
"""
import collections, csv, os, re, statistics

MODELS = [("qwen2.5-coder_7b", "Qwen2.5-Coder 7B"), ("llama3.1_8b", "Llama 3.1 8B"), ("gemma3_4b", "Gemma 3 4B")]
CONFIGS = [("whole_u_r0", "composed", "\\textsc{one-shot}"), ("whole_u_r3", "composed", "+ feedback"),
           ("leaf_u_r3", "composed", "+ decomposition"), ("leaf_gnofix_r3", "composed", "+ guidance"),
           ("leaf_g_r3", "composed", "+ auto-repair"), ("leaf_gc_r3", "composed", "+ generality critic"),
           ("leaf_gc_r3", "critic", "+ compile critic (\\textsc{full})")]
DEV = ["ida_simple", "i2c_probe_new", "platform_remove_new", "strlcpy_strscpy", "pci_dma_wrappers"]
os.makedirs("paper/tables", exist_ok=True)
numbers = collections.OrderedDict()


def macro(name, value):
    numbers[name] = value


def tex(s):
    return s.replace("_", "\\_")


def load(path):
    return list(csv.DictReader(open(path))) if os.path.exists(path) else []


def by_seed(rows):
    """{(model, config_without_seed, variant, migration): {seed: (success, buildable)}}"""
    out = collections.defaultdict(dict)
    for r in rows:
        m = re.match(r"(.*)_s(\d+)$", r["config"])
        cfg, seed = (m.group(1), int(m.group(2))) if m else (r["config"], 0)
        out[(r["model"], cfg, r["variant"], r["migration"])][seed] = (int(r["success"]), int(r["buildable"]))
    return out


def stat(d):
    vals = [v[0] for v in d.values()]
    return (statistics.mean(vals), min(vals), max(vals), len(vals)) if vals else None


def fmt(st, pct_of=None):
    if not st:
        return "--"
    mean, lo, hi, n = st
    s = f"{mean:.1f}" if n > 1 else f"{mean:.0f}"
    if n > 1 and lo != hi:
        s += f" [{lo}--{hi}]"
    return s


sets = {}
for name, path in (("dev", "results/gcg_heldout_dev_summary.csv"), ("test", "results/gcg_heldout_test_summary.csv")):
    rows = load(path)
    sets[name] = {"rows": rows, "seed": by_seed(rows),
                  "migs": [m for m in dict.fromkeys(r["migration"] for r in rows) if m != "ALL"]}

# ---- data table ------------------------------------------------------------------------------------------------
cases = {r["migration"]: r for r in load("data/test/cases.csv")}
lines = []
for name, split in (("dev", "data/h2_split.csv"), ("test", "data/test/h2_split.csv")):
    sp = load(split)
    buildable = {r["migration"]: r["buildable"] for r in sets[name]["rows"]
                 if r["model"] == "spinfer" and r["config"] == "-"}
    total_t = total_b = 0
    for mig in dict.fromkeys(r["migration"] for r in sp):
        tr = [r for r in sp if r["migration"] == mig and r["role"] == "train"]
        tg = [r for r in sp if r["migration"] == mig and r["role"] == "target"]
        newapi = cases.get(mig, {}).get("new_api_date", "") or "before v6.10"
        dates = sorted(r["commit_date"] for r in tg)
        lines.append(f"{name} & \\texttt{{{tex(mig)}}} & {newapi if name == 'test' else '--'} & {len(tr)} & "
                     f"{len(tg)} & {buildable.get(mig, '--')} & {dates[0][:7]}--{dates[-1][:7]} \\\\")
        total_t += len(tg); total_b += int(buildable.get(mig, 0) or 0)
    macro(f"{name}Targets", total_t); macro(f"{name}Buildable", total_b)
    macro(f"{name}Migrations", len(dict.fromkeys(r["migration"] for r in sp)))
    lines.append("\\midrule")
open("paper/tables/data.tex", "w").write(
    "\\begin{tabular}{llrrrrl}\n\\toprule\nSet & Migration & New API & Train & Targets & Buildable & Target dates \\\\\n"
    "\\midrule\n" + "\n".join(lines[:-1]) + "\n\\bottomrule\n\\end{tabular}\n")

# ---- main test table (per migration) -----------------------------------------------------------------------------
for name in ("dev", "test"):
    S, migs = sets[name]["seed"], sets[name]["migs"]
    if not migs:
        continue
    hdr = (" & & Frontier & & " + " & ".join(f"\\multicolumn{{2}}{{c}}{{{lab}}}" for _, lab in MODELS) + " \\\\\n" +
           "".join(f"\\cmidrule(lr){{{5 + 2 * i}-{6 + 2 * i}}}" for i in range(len(MODELS))) + "\n" +
           "Migration & Bld. & LLM$^\\dagger$ & Spinfer & " +
           " & ".join("one-shot & \\textsc{full}" for _ in MODELS) + " \\\\")
    body = []
    for mig in migs + ["ALL"]:
        b = next((r["buildable"] for r in sets[name]["rows"] if r["migration"] == mig), "--")
        cells = [f"\\texttt{{{tex(mig)}}}" if mig != "ALL" else "\\textbf{All}", b]
        for src in ("manual", "spinfer"):
            st = stat(S.get((src, "-", "rules", mig), {}))
            cells.append(fmt(st))
        for m, _ in MODELS:
            cells.append(fmt(stat(S.get((m, "whole_u_r0", "composed", mig), {}))))
            cells.append(fmt(stat(S.get((m, "leaf_gc_r3", "critic", mig), {}))))
        if mig == "ALL":
            body.append("\\midrule")
        body.append(" & ".join(str(c) for c in cells) + " \\\\")
    open(f"paper/tables/{name}_main.tex", "w").write(
        "\\begin{tabular}{lr" + "r" * (2 + 2 * len(MODELS)) + "}\n\\toprule\n" + hdr + "\n\\midrule\n" +
        "\n".join(body) + "\n\\bottomrule\n\\end{tabular}\n")
    for src, key in (("manual", "Frontier"), ("spinfer", "Spinfer")):
        st = stat(S.get((src, "-", "rules", "ALL"), {}))
        if st:
            macro(f"{name}{key}", f"{st[0]:.0f}")
    for m, lab in MODELS:
        key = re.sub(r"[^A-Za-z]", "", lab.split()[0])
        for cfg, var, tag in (("whole_u_r0", "composed", "OneShot"), ("leaf_gc_r3", "critic", "Full")):
            st = stat(S.get((m, cfg, var, "ALL"), {}))
            if st:
                macro(f"{name}{key}{tag}", f"{st[0]:.1f}")
                macro(f"{name}{key}{tag}Min", st[1]); macro(f"{name}{key}{tag}Max", st[2])

# ---- ablation table ---------------------------------------------------------------------------------------------
body = []
ABL = ["OneShot", "Feedback", "Decomp", "Guidance", "Repair", "GenCritic", "Full"]
for (cfg, var, label), ablkey in zip(CONFIGS, ABL):
    cells = [label]
    for name in ("dev", "test"):
        for m, lab in MODELS:
            st = stat(sets[name]["seed"].get((m, cfg, var, "ALL"), {}))
            cells.append(fmt(st))
            if st:
                macro(f"{name}Abl{re.sub(r'[^A-Za-z]', '', lab.split()[0])}{ablkey}", f"{st[0]:.1f}")
    body.append(" & ".join(cells) + " \\\\")
hdr = ("Configuration & " + " & ".join(f"{lab.split()[0]}" for _, lab in MODELS) + " & " +
       " & ".join(f"{lab.split()[0]}" for _, lab in MODELS) + " \\\\")
open("paper/tables/ablation.tex", "w").write(
    "\\begin{tabular}{l" + "r" * 6 + "}\n\\toprule\n & \\multicolumn{3}{c}{Development (of " +
    f"{numbers.get('devBuildable', '?')})" + "} & \\multicolumn{3}{c}{Test (of " +
    f"{numbers.get('testBuildable', '?')})" + "} \\\\\n\\cmidrule(lr){2-4}\\cmidrule(lr){5-7}\n" + hdr +
    "\n\\midrule\n" + "\n".join(body) + "\n\\bottomrule\n\\end{tabular}\n")

# ---- safety of outputs (what the compile critic changes) --------------------------------------------------------
# Over buildable targets: success; divergent (an edit the human did not make); broken (exact/subset output that
# does not compile). Means over seeds for the local models.
def safety(rows_path):
    acc = collections.defaultdict(lambda: collections.defaultdict(collections.Counter))
    for r in load(rows_path):
        if r["build_original"] != "True":
            continue
        m = re.match(r"(.*)_s(\d+)$", r["config"])
        cfg, seed = (m.group(1), m.group(2)) if m else (r["config"], "0")
        c = acc[(r["model"], cfg, r["variant"])][seed]
        c["success"] += r["success"] in ("1", "True")
        c["divergent"] += r["auto_class"] == "divergent"
        c["broken"] += r["auto_class"] in ("exact", "subset_complete") and r["build_rule"] == "False"
        c["changed"] += r["auto_class"] in ("exact", "subset_complete", "subset_incomplete", "divergent")
    return {k: {f: statistics.mean(c[f] for c in v.values()) for f in ("success", "divergent", "broken", "changed")}
            for k, v in acc.items()}


body = []
for name, path in (("dev", "results/gcg_heldout_dev_rows.csv"), ("test", "results/gcg_heldout_test_rows.csv")):
    sf = safety(path)
    if not sf:
        continue
    srcs = [("manual", "-", "rules", "Frontier LLM$^\\dagger$"), ("spinfer", "-", "rules", "Spinfer")]
    for m, lab in MODELS:
        srcs += [(m, "leaf_gc_r3", "composed", f"{lab}, before compile critic"),
                 (m, "leaf_gc_r3", "critic", f"{lab}, \\textsc{{full}}")]
    for model, cfg, var, lab in srcs:
        v = sf.get((model, cfg, var))
        if not v:
            continue
        prec = v["success"] / v["changed"] if v["changed"] else 0
        body.append(f"{name} & {lab} & {v['success']:.1f} & {v['changed']:.1f} & {v['divergent']:.1f} & "
                    f"{v['broken']:.1f} & {prec:.2f} \\\\")
        key = re.sub(r"[^A-Za-z]", "", lab.split(",")[0].split()[0]) + ("Pre" if var == "composed" else "")
        macro(f"{name}Safe{key}Divergent", f"{v['divergent']:.1f}")
        macro(f"{name}Safe{key}Broken", f"{v['broken']:.1f}")
        macro(f"{name}Safe{key}Precision", f"{prec:.2f}")
    body.append("\\midrule")
open("paper/tables/safety.tex", "w").write(
    "\\begin{tabular}{llrrrrr}\n\\toprule\nSet & Source & Success & Changed & Divergent & Broken & Precision \\\\\n"
    "\\midrule\n" + "\n".join(body[:-1]) + "\n\\bottomrule\n\\end{tabular}\n")

# ---- cost ---------------------------------------------------------------------------------------------------------
tasks = load("results/gcg_stage2_tasks.csv")
critic = load("results/gcg_stage4_critic.csv")
# share of leaf tasks whose best rule does not parse, without and with auto-repair (both sets, all seeds)
for m, lab in MODELS:
    key = re.sub(r"[^A-Za-z]", "", lab.split()[0])
    for cfg, tag in (("leaf_gnofix_r3", "NoFix"), ("leaf_g_r3", "Fix")):
        rs = [r for r in tasks if r["model"] == m and re.sub(r"_s\d+$", "", r["config"]) == cfg]
        if rs:
            macro(f"parseFail{key}{tag}", f"{100 * sum(int(r['spatch_error']) for r in rs) / len(rs):.0f}")
            macro(f"parseTasks{key}{tag}", len(rs))

body = []
for m, lab in MODELS:
    cells = [lab]
    key = re.sub(r"[^A-Za-z]", "", lab.split()[0])
    for name in ("dev", "test"):
        migs = set(DEV) if name == "dev" else set(sets["test"]["migs"])
        rs = [r for r in tasks if r["model"] == m and r["config"].startswith("leaf_gc_r3") and r["migration"] in migs]
        if not rs:
            cells += ["--"] * 3
            continue
        runs = {(r["config"], r["migration"]) for r in rs}   # one run = one migration x seed
        calls = sum(int(r["calls"]) for r in rs) / len(runs)
        secs = sum(float(r["seconds"]) for r in rs) / len(runs)
        rep = [int(r["repair_calls"]) for r in critic if r["model"] == m and r["migration"] in migs]
        cells += [f"{calls:.1f}", f"{secs:.0f}", f"{statistics.mean(rep) if rep else 0:.1f}"]
        macro(f"{name}Cost{key}Calls", f"{calls:.1f}"); macro(f"{name}Cost{key}Seconds", f"{secs:.0f}")
    body.append(" & ".join(cells) + " \\\\")
open("paper/tables/cost.tex", "w").write(
    "\\begin{tabular}{lrrrrrr}\n\\toprule\n & \\multicolumn{3}{c}{Development} & \\multicolumn{3}{c}{Test} \\\\\n"
    "\\cmidrule(lr){2-4}\\cmidrule(lr){5-7}\n"
    "Model & Calls & Seconds & Repairs & Calls & Seconds & Repairs \\\\\n"
    "\\midrule\n" + "\n".join(body) + "\n\\bottomrule\n\\end{tabular}\n")

with open("paper/numbers.tex", "w") as f:
    f.write("% generated by scripts/make_paper_tables.py; do not edit\n")
    for k, v in numbers.items():
        f.write(f"\\newcommand{{\\{k}}}{{{v}}}\n")
with open("results/gcg_paper_numbers.csv", "w", newline="") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(["name", "value"]); w.writerows(numbers.items())
print(f"{len(numbers)} numbers -> paper/numbers.tex, tables -> paper/tables/")
