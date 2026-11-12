#!/usr/bin/env python3
"""Replay a saved guided-generation run in the terminal, round by round (read-only; nothing is re-run).

For every task (leaf) of one model x config x migration it shows what the model was told (the task prompt in round 0,
the feedback in later rounds), the rule the model answered with, and how that rule scored on the training siblings.

Usage: python3 scripts/replay_run.py <model_dir> <config> <migration> [--delay 0.01] [--full-prompt]
  e.g. python3 scripts/replay_run.py qwen2.5-coder_7b leaf_gc_r3_s1 iio_claim_direct
Runs: work/gcg/runs/<model_dir>/<config>/<migration>/<task>/round<k>.{prompt.json,response.txt,eval.json}
"""
import argparse, glob, json, os, sys, time

C = {"h": "\033[1;36m", "u": "\033[33m", "a": "\033[32m", "e": "\033[35m", "r": "\033[0m", "bad": "\033[31m"}


def type_out(text, delay, color):
    sys.stdout.write(color)
    for ch in text:
        sys.stdout.write(ch)
        sys.stdout.flush()
        if delay:
            time.sleep(delay)
    sys.stdout.write(C["r"] + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("model"); ap.add_argument("config"); ap.add_argument("migration")
    ap.add_argument("--delay", type=float, default=0.01, help="seconds per character of the model's answer")
    ap.add_argument("--full-prompt", action="store_true", help="show the whole task prompt, not its last part")
    a = ap.parse_args()
    base = f"work/gcg/runs/{a.model}/{a.config}/{a.migration}"
    tasks = sorted(d for d in glob.glob(f"{base}/*") if os.path.isdir(d))
    if not tasks:
        raise SystemExit(f"no run at {base}")
    for t in tasks:
        s = json.load(open(f"{t}/summary.json")) if os.path.exists(f"{t}/summary.json") else {}
        print(f"\n{C['h']}=== {a.migration} task {os.path.basename(t)}  leaves: {' '.join(s.get('leaves', []))}{C['r']}")
        k = 0
        while os.path.exists(f"{t}/round{k}.prompt.json"):
            msgs = json.load(open(f"{t}/round{k}.prompt.json"))
            last = msgs[-1]["content"]
            if k == 0 and not a.full_prompt:
                last = "... " + last[-1500:]
            print(f"\n{C['h']}--- round {k}: {'task prompt' if k == 0 else 'feedback'} sent to the model{C['r']}")
            print(C["u"] + last + C["r"])
            print(f"{C['h']}--- model answer{C['r']}")
            type_out(open(f"{t}/round{k}.response.txt", errors="replace").read().strip(), a.delay, C["a"])
            ev = json.load(open(f"{t}/round{k}.eval.json"))["eval"]
            if ev.get("spatch_error"):
                print(f"{C['bad']}>>> spatch could not parse the rule{C['r']}")
            else:
                print(f"{C['e']}>>> training files passed {ev['pass']}/{ev['files']}, expected changes hit "
                      f"{ev['hit']}/{ev['need']}, extra edits {ev['extra']}, auto-repairs {ev.get('autofixes') or 'none'}, "
                      f"{ev.get('seconds', '?')} s{C['r']}")
            k += 1
        if s:
            print(f"{C['h']}=== task {'PASSED' if s.get('passed') else 'not passed'}; best round {s.get('best_round')}{C['r']}")
    for p in (f"work/gcg/composed/{a.model}/{a.config}/{a.migration}.cocci", f"work/gcg/final/{a.model}/{a.config}/{a.migration}.cocci"):
        if os.path.exists(p):
            body = open(p).read().strip()
            print(f"\n{C['h']}=== {'composed rule (stage 3)' if 'composed' in p else 'final rule after compile critic (stage 4)'}{C['r']}")
            print(C["a"] + (body or "(empty: the framework abstained)") + C["r"])


if __name__ == "__main__":
    main()
