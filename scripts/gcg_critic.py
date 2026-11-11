#!/usr/bin/env python3
"""Guided rule generation, stage 4: compile critic for a composed migration rule.

Only training siblings are read and built; held-out targets are never opened here.

Input : work/gcg/composed/<model>/<config>/<mig>.{cocci,json} (stage 3)
Check : the rule is applied to the most recent training files it changes (up to --check-files whose human
        version compiles); each output is compiled in a worktree at that training commit's parent
        (x86_64 allmodconfig, CONFIG_WERROR off, the same recipe as scripts/h2_eval.py).
Repair: if an output does not compile, the model gets the compiler errors, the converted code around them and
        the human changes the rule did not make in that file, and rewrites the whole rule (--repair-rounds,
        each repaired rule goes through autofix + generality critic + lint, then spatch on all training files
        and the compile check again).
Decide: among the rules whose checked outputs all compile (the composed rule, repaired rules, and the composed
        rule with whole leaf chunks removed), keep the one with the highest training score hit - extra
        (scripts/gcg_compose.py); if none compiles, ABSTAIN (no rule for the migration).
Output: work/gcg/critic/<model>/<config>/<mig>/ (prompts, responses, rules, compile logs, decision.json)
        work/gcg/final/<model>/<config>/<mig>.cocci (empty = abstain)
        rules/gcg_<model>/<mig>.cocci with --publish; results/gcg_stage4_critic.csv

Usage: python3 scripts/gcg_critic.py --model qwen2.5-coder:7b [--config leaf_gc_r3_s1] [--migration ...] [--publish]
"""
import argparse, csv, difflib, hashlib, json, os, re, shutil, subprocess, sys

sys.path.insert(0, os.path.dirname(__file__))
from gcg_leaf import (PRIMER, assemble, autofix, make_interface, chat, core_edit, extract_rule, generalize, lint, show_units, signature,  # noqa
                      spatch, unit_changes, unload)
from gcg_compose import SHORT, score, training_expected  # noqa: E402

LINUX = os.environ.get("LINUX", "/linux/linux")
JOBS = os.environ.get("H2_JOBS", "6")
CACHE = "work/gcg/compile_cache"


def sh(cmd, cwd=None, timeout=1800):
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, errors="replace", timeout=timeout)
    return p.returncode, p.stdout, p.stderr


class Builder:
    """One worktree + build directory per migration; reconfigured only when the training commit changes."""

    def __init__(self, mig, tag="critic"):
        self.wt, self.bdir, self.at = f"/linux/wt/{tag}_{mig}", f"/linux/build/{tag}_{mig}", None
        if not os.path.isdir(self.wt):
            sh(["git", "-C", LINUX, "-c", "gc.auto=0", "worktree", "add", "-q", "--detach", self.wt, "HEAD"])

    def prepare(self, commit):
        if self.at == commit:
            return
        sh(["git", "-C", self.wt, "-c", "gc.auto=0", "checkout", "-q", "--detach", "--force", f"{commit}^"])
        sh(["git", "-C", self.wt, "clean", "-q", "-fdx"])
        shutil.rmtree(self.bdir, ignore_errors=True)
        os.makedirs(self.bdir, exist_ok=True)
        sh(["make", "-s", f"O={self.bdir}", "allmodconfig"], cwd=self.wt)
        sh(["./scripts/config", "--file", f"{self.bdir}/.config", "-d", "WERROR"], cwd=self.wt)
        sh(["make", "-s", f"O={self.bdir}", "olddefconfig"], cwd=self.wt)
        self.at = commit

    def build(self, commit, rel, content):
        key = hashlib.sha1(f"{commit}\0{rel}\0{content}".encode()).hexdigest()
        path = f"{CACHE}/{key}.json"
        if os.path.exists(path):
            return json.load(open(path))
        self.prepare(commit)
        src = os.path.join(self.wt, rel)
        orig = open(src, errors="replace").read()
        open(src, "w").write(content)
        obj = rel[:-2] + ".o"
        try:
            os.remove(os.path.join(self.bdir, obj))
        except FileNotFoundError:
            pass
        rc, out, err = sh(["make", "-s", f"-j{JOBS}", f"O={self.bdir}", obj], cwd=self.wt)
        open(src, "w").write(orig)
        ok = rc == 0 and os.path.exists(os.path.join(self.bdir, obj))
        errors = [l for l in err.splitlines() if " error: " in l][:8]
        res = {"ok": ok, "errors": errors, "log_tail": (out + err)[-3000:]}
        os.makedirs(CACHE, exist_ok=True)
        json.dump(res, open(path, "w"), indent=1)
        return res


def training_files(mig):
    base = f"work/h2/{mig}/train"
    ks = [k for k in sorted(os.listdir(base)) if os.path.isdir(f"{base}/{k}")]
    metas = {k: json.load(open(f"{base}/{k}/meta.json")) for k in ks}
    return sorted(ks, key=lambda k: (metas[k]["commit_date"], k), reverse=True), metas


def compile_check(builder, mig, rule_path, n_files, scratch):
    """Compile the rule's outputs on up to n_files recent training files that it changes.
    Returns {'parse_error'} or {'checked': [...], 'ok': bool}."""
    ks, metas = training_files(mig)
    checked = []
    for k in ks:
        if len(checked) == n_files:
            break
        d = f"work/h2/{mig}/train/{k}"
        before = open(f"{d}/before.c", errors="replace").read()
        out, err = spatch(rule_path, f"{d}/before.c", f"{scratch}/{k}.c")
        if out is None:
            return {"parse_error": err[-1500:]}
        if out == before:
            continue
        m = metas[k]
        human = builder.build(m["commit"], m["file"], open(f"{d}/after.c", errors="replace").read())
        if not human["ok"]:
            continue                      # this training tree does not build the human version: uninformative
        res = builder.build(m["commit"], m["file"], out)
        checked.append({"sibling": k, "file": m["file"], "ok": res["ok"], "errors": res["errors"],
                        "output": out, "before": before, "after": open(f"{d}/after.c", errors="replace").read()})
    return {"checked": checked, "ok": all(c["ok"] for c in checked)}


def error_context(output, errors, radius=2):
    lines = output.splitlines()
    shown = []
    for e in errors[:3]:
        m = re.search(r":(\d+):\d+: error:", e)
        if not m:
            continue
        n = int(m.group(1))
        shown.append("\n".join(f"{i + 1:5}: {lines[i]}" for i in range(max(0, n - 1 - radius), min(len(lines), n + radius))))
    return "\n...\n".join(shown)


def repair_prompt(mig, rule, c, iface=None):
    produced = unit_changes(c["before"], c["output"])
    human = unit_changes(c["before"], c["after"])
    missing = sorted(human - produced)
    extra = sorted(produced - human)
    errs = "\n".join(re.sub(r"^\S*/(\S+\.c):", r"\1:", e) for e in c["errors"][:5])
    msg = [f"Linux kernel API migration '{mig}'. This Coccinelle semantic patch was written from drivers that were "
           "converted by hand earlier, and it reproduces many of their changes:\n```cocci\n" + rule.strip() + "\n```",
           f"\nBut on training file {c['sibling']} the converted file does NOT compile. Compiler errors:\n{errs}",
           "\nConverted code around the error(s):\n" + error_context(c["output"], c["errors"])]
    if missing or extra:
        # what is still different between the patch's output and the human version of this TRAINING file
        diff = [l for l in difflib.unified_diff(c["output"].splitlines(), c["after"].splitlines(), lineterm="", n=2)
                if not l.startswith(("---", "+++"))]
        msg.append("\nIn that file the human's version still differs from your patch's output as follows "
                   "('-' = your output, '+' = the human's version):\n" + "\n".join(diff[:40]) +
                   ("\n..." if len(diff) > 40 else ""))
    if iface:
        msg.append("\nThe semantic patch above will be kept and placed first automatically; do not repeat it. Write ONE "
                   "additional rule that comes after it and makes the remaining change, so that the converted code "
                   "compiles as the human's version does. Start it with this header (the metavariables it lists are "
                   "bound by the patch above; use them in code WITHOUT the prefix; you may declare new metavariables "
                   "in the header too):\n```cocci\n" + iface["header"] + "```\nAnswer with that one rule in one "
                   "```cocci block.")
    else:
        msg.append("\nExtend or correct the semantic patch so that the converted code compiles, as the human's "
                   "version does. Keep the rules that already work, use metavariables for names that differ between "
                   "drivers, and answer with the complete semantic patch in one ```cocci block.")
    return "\n".join(msg)


def critic(args, model_dir, mig, builder):
    src = f"work/gcg/composed/{model_dir}/{args.config}"
    out_dir = f"work/gcg/critic/{model_dir}/{args.config}/{mig}"
    os.makedirs(out_dir, exist_ok=True)
    tree = json.load(open(f"work/gcg/{mig}/tree.json"))
    expected = training_expected(mig, tree)
    comp = json.load(open(f"{src}/{mig}.json"))
    composed = open(f"{src}/{mig}.cocci").read()
    decision = {"migration": mig, "model": model_dir, "config": args.config, "candidates": []}

    def consider(label, text, n_calls=0):
        path = f"{out_dir}/{label}.cocci"
        open(path, "w").write(text)
        scratch = f"{out_dir}/{label}.out"
        os.makedirs(scratch, exist_ok=True)
        chk = compile_check(builder, mig, path, args.check_files, scratch)
        if "parse_error" in chk:
            cand = {"label": label, "parse_error": chk["parse_error"][-400:], "compiles": False}
        else:
            sc, _ = score(path, mig, expected, scratch)
            cand = {"label": label, "compiles": chk["ok"], "checked": [(c["sibling"], c["ok"]) for c in chk["checked"]],
                    "hit": sc[0], "extra": sc[1], "errors": [e for c in chk["checked"] for e in c["errors"]][:4]}
        decision["candidates"].append(cand)
        print(f"  {mig} {label}: " + ("PARSE ERROR" if "parse_error" in cand else
              f"compiles={cand['compiles']} checked={cand['checked']} train {cand['hit']}-{cand['extra']}"), flush=True)
        return cand, chk

    if not composed.strip():
        decision["final"] = None
    else:
        cand, chk = consider("composed", composed)
        if not cand["compiles"] and "checked" in chk:
            failing = next(c for c in chk["checked"] if not c["ok"])
            # interface (as in stage 2): the working composed rule is kept, its first rule is named and the model
            # writes only a dependent rule that inherits that rule's metavariables
            a_rule, header = make_interface(composed, "fix")
            iface = {"rule": a_rule, "header": header}
            messages = [{"role": "system", "content": PRIMER},
                        {"role": "user", "content": repair_prompt(mig, a_rule, failing, iface)}]
            for rnd in range(args.repair_rounds):
                json.dump(messages, open(f"{out_dir}/repair{rnd}.prompt.json", "w"), indent=1)
                text, usage = chat(args.model, messages, args.seed + 100 + rnd, args.temperature, args.num_ctx)
                open(f"{out_dir}/repair{rnd}.response.txt", "w").write(text)
                part, fixes = autofix(extract_rule(text))
                part, gen = generalize(part, mig)
                problem = lint(part)
                rule = assemble(iface, part)
                if problem:
                    decision["candidates"].append({"label": f"repair{rnd}", "lint": problem, "compiles": False})
                    print(f"  {mig} repair{rnd}: LINT", flush=True)
                    fb = problem + "\n\nAnswer with the corrected rule in one ```cocci block."
                else:
                    c2, chk2 = consider(f"repair{rnd}", rule)
                    c2.update(seconds=usage["seconds"], autofixes=fixes + gen)
                    if c2["compiles"]:
                        break
                    if "parse_error" in chk2:
                        fb = ("spatch could not use your semantic patch:\n" + chk2["parse_error"][-800:] +
                              "\n\nFix it and answer with the complete semantic patch in one ```cocci block.")
                    else:
                        c_fail = next(c for c in chk2["checked"] if not c["ok"])
                        fb = repair_prompt(mig, a_rule, c_fail, iface)
                        if c_fail["output"] == next(c["output"] for c in chk["checked"] if c["sibling"] == c_fail["sibling"]):
                            fb = ("Your additional rule did not match anything in that file, so the output did not "
                                  "change. Do not copy the code of one file: use the metavariables bound by the patch "
                                  "above (for example the function name it binds) and write '...' for statements you "
                                  "do not change.\n\n" + fb)
                messages += [{"role": "assistant", "content": text}, {"role": "user", "content": fb}]
            if not any(c.get("compiles") for c in decision["candidates"]):
                chunks = comp.get("chunks", [])
                for i in range(len(chunks)):      # drop one leaf chunk at a time
                    rest = [ch["text"] for j, ch in enumerate(chunks) if j != i]
                    if rest:
                        consider(f"drop_{'_'.join(chunks[i]['tasks'])}", "\n".join(rest))
        ok = [c for c in decision["candidates"] if c.get("compiles")]
        best = max(ok, key=lambda c: (c["hit"] - c["extra"], c["label"] == "composed")) if ok else None
        decision["final"] = best["label"] if best else None
    final_text = open(f"{out_dir}/{decision['final']}.cocci").read() if decision["final"] else ""
    fdir = f"work/gcg/final/{model_dir}/{args.config}"
    os.makedirs(fdir, exist_ok=True)
    open(f"{fdir}/{mig}.cocci", "w").write(final_text)
    json.dump(decision, open(f"{out_dir}/decision.json", "w"), indent=1)
    fin = next((c for c in decision["candidates"] if c["label"] == decision["final"]), {})
    return final_text, {"model": model_dir, "config": args.config, "migration": mig,
                        "composed_train_hit": comp["hit"], "composed_train_extra": comp["extra"],
                        "composed_compiles": next((c.get("compiles") for c in decision["candidates"]
                                                   if c["label"] == "composed"), ""),
                        "repair_calls": sum(c["label"].startswith("repair") for c in decision["candidates"]),
                        "final": decision["final"] or "abstain", "final_train_hit": fin.get("hit", 0),
                        "final_train_extra": fin.get("extra", 0)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--config", default="leaf_gc_r3_s1")
    ap.add_argument("--migration", nargs="+")
    ap.add_argument("--check-files", type=int, default=3)
    ap.add_argument("--repair-rounds", type=int, default=2)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--temperature", type=float, default=0.4)
    ap.add_argument("--num-ctx", type=int, default=8192)
    ap.add_argument("--publish", action="store_true")
    args = ap.parse_args()
    model_dir = args.model.replace(":", "_")
    migs = args.migration or sorted(f[:-6] for f in os.listdir(f"work/gcg/composed/{model_dir}/{args.config}")
                                    if f.endswith(".cocci"))
    rows = []
    for mig in migs:
        final, row = critic(args, model_dir, mig, Builder(mig))
        rows.append(row)
        print(f"{model_dir} {args.config} {mig}: final={row['final']}", flush=True)
        if args.publish:
            d = f"rules/gcg_{SHORT.get(model_dir, model_dir)}"
            os.makedirs(d, exist_ok=True)
            p = f"{d}/{mig}.cocci"
            if final.strip():
                open(p, "w").write(f"// scripts/gcg_critic.py final rule ({model_dir}, {args.config}, {row['final']})\n"
                                   + final)
            elif os.path.exists(p):
                os.remove(p)              # abstain: no rule is published for this migration
    unload(args.model)
    path = "results/gcg_stage4_critic.csv"
    old = [r for r in csv.DictReader(open(path))] if os.path.exists(path) else []
    keys = {(r["model"], r["config"], r["migration"]) for r in rows}
    old = [r for r in old if (r["model"], r["config"], r["migration"]) not in keys]
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]), lineterminator="\n")
        w.writeheader(); w.writerows(old + rows)


if __name__ == "__main__":
    main()
