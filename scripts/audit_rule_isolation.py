#!/usr/bin/env python3
"""Audit that each rule-writing agent only touched its own training folder (H2 data isolation).

Usage: python3 scripts/audit_rule_isolation.py <workflow transcript dir>
Scans every tool call in each agent transcript (agent-*.jsonl) and flags any reference to forbidden locations:
data/, results/, docs/, scripts/, the kernel repo (/linux), git commands, web tools, or another migration's folder.
Writes results/h2_isolation_audit.txt.
"""
import glob, json, os, re, sys

MIGS = ["ida_simple", "i2c_probe_new", "platform_remove_new", "strlcpy_strscpy", "pci_dma_wrappers"]
FORBID = [r"DRIVEBENCH/data/", r"/work/data/", r"\bdata/(conversions|h2_split|cases|verification|mined)",
          r"DRIVEBENCH/results/", r"/work/results/", r"DRIVEBENCH/docs/", r"/work/docs/", r"DRIVEBENCH/scripts/", r"/work/scripts/",
          r"/linux/", r"\bgit\s", r"WebFetch|WebSearch"]
tdir = sys.argv[1]
lines, bad_total = [], 0
for path in sorted(glob.glob(os.path.join(tdir, "agent-*.jsonl"))):
    meta = path.replace(".jsonl", ".meta.json")
    calls = []
    for l in open(path, encoding="utf-8"):
        try:
            ev = json.loads(l)
        except json.JSONDecodeError:
            continue
        msg = ev.get("message") or {}
        for block in msg.get("content") or []:
            if isinstance(block, dict) and block.get("type") == "tool_use":
                inp = block.get("input") or {}
                if block.get("name") in ("Write", "Edit"):   # check where it writes, not the text it writes
                    inp = {"file_path": inp.get("file_path")}
                calls.append((block.get("name"), json.dumps(inp, ensure_ascii=False)))
    text = " ".join(c[1] for c in calls)
    mig = next((m for m in MIGS if f"work/h2/{m}/" in text or f"rules/manual/{m}" in text), "?")
    bad = []
    for name, inp in calls:
        hits = [p for p in FORBID if re.search(p, inp) or re.search(p, name or "")]
        others = [m for m in MIGS if m != mig and (f"work/h2/{m}/" in inp or f"rules/manual/{m}" in inp)]
        if hits or others:
            bad.append(f"    {name}: {inp[:200]}  <- {hits + others}")
    bad_total += len(bad)
    lines.append(f"{os.path.basename(path)} migration={mig} tool_calls={len(calls)} violations={len(bad)}")
    lines.extend(bad)
lines.append(f"TOTAL violations: {bad_total}")
os.makedirs("results", exist_ok=True)
open("results/h2_isolation_audit.txt", "w", newline="\n").write("\n".join(lines) + "\n")
print("\n".join(lines))
