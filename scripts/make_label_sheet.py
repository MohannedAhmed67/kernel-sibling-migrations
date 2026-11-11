#!/usr/bin/env python3
"""Blind human-labelling packet for non-exact rule outputs on the TEST set (docs/test_set_rule.md).

Items: every (target, source) whose automatic class is subset_complete, subset_incomplete or divergent, for the
sources frontier LLM (rules/manual), Spinfer, and the FULL framework (leaf_gc_r3, stage-4 critic) of each local model
with seed 1 (one seed, declared in advance, keeps the packet small). Identical outputs of different sources on the
same target are merged into one item, so the labeller cannot tell sources apart by repetition.
Order is shuffled with a fixed seed; the source names are written only to labeling/key.csv (do not open it while
labelling).

Output: labeling/items/<id>.txt  the human fix and the rule output, each as a diff against the original file
        labeling/labels.csv      id, migration, file, label (to fill), note (to fill)
        labeling/key.csv         id -> sources (for scripts/merge_labels.py, after labelling)
Labels: correct_equivalent | correct_alternative | partial | wrong | no_migration   (definitions in labeling/README.md)
"""
import csv, difflib, glob, hashlib, os, random

ROWS = "results/gcg_heldout_test_rows.csv"
KEEP = {"subset_complete", "subset_incomplete", "divergent"}


def source_name(r):
    if r["variant"] == "rules":
        return {"manual": "frontier_llm", "spinfer": "spinfer"}.get(r["model"], r["model"])
    if r["config"] == "leaf_gc_r3_s1" and r["variant"] == "critic":
        return f"full_{r['model']}"
    return None


def rule_output(r):
    """The cached spatch output of this source on this target (gcg_heldout.py stores it by rule hash)."""
    if r["variant"] == "rules":
        rule = f"rules/{r['model']}/{r['migration']}.cocci"
    else:
        base = "final" if r["variant"] == "critic" else "composed"
        rule = f"work/gcg/{base}/{r['model']}/{r['config']}/{r['migration']}.cocci"
    rh = hashlib.sha1(open(rule, "rb").read()).hexdigest()[:16]
    return open(f"work/gcg/heldout/{r['migration']}/{int(r['idx']):02d}/{rh}.c", errors="replace").read()


def main():
    if os.path.exists("labeling/labels.csv") and any(r["label"] for r in csv.DictReader(open("labeling/labels.csv"))):
        raise SystemExit("labeling/labels.csv already has labels; not overwriting")
    items = {}
    for r in csv.DictReader(open(ROWS)):
        src = source_name(r)
        if not src or r["auto_class"] not in KEEP:
            continue
        d = f"work/gcg/heldout/{r['migration']}/{int(r['idx']):02d}"
        out = rule_output(r)
        key = (r["migration"], r["idx"], hashlib.sha1(out.encode()).hexdigest())
        it = items.setdefault(key, {"migration": r["migration"], "idx": r["idx"], "file": r["file"], "dir": d,
                                    "output": out, "sources": [], "auto_class": r["auto_class"]})
        it["sources"].append(src)

    order = sorted(items)
    random.Random(20261111).shuffle(order)
    os.makedirs("labeling/items", exist_ok=True)
    for f in glob.glob("labeling/items/*.txt"):
        os.remove(f)
    labels, keyrows = [], []
    for n, k in enumerate(order):
        it = items[k]
        iid = f"L{n:03d}"
        before = open(f"{it['dir']}/before.c", errors="replace").read().splitlines()
        human = open(f"{it['dir']}/human.c", errors="replace").read().splitlines()
        rule = it["output"].splitlines()
        text = [f"Item {iid}   migration: {it['migration']}   file: {it['file']}", "",
                "=== HUMAN FIX (diff original -> human) ==="]
        text += list(difflib.unified_diff(before, human, "original", "human", lineterm="", n=3))
        text += ["", "=== RULE OUTPUT (diff original -> rule) ==="]
        text += list(difflib.unified_diff(before, rule, "original", "rule", lineterm="", n=3))
        open(f"labeling/items/{iid}.txt", "w").write("\n".join(text) + "\n")
        labels.append({"id": iid, "migration": it["migration"], "file": it["file"], "label": "", "note": ""})
        keyrows.append({"id": iid, "migration": it["migration"], "idx": it["idx"], "auto_class": it["auto_class"],
                        "sources": " ".join(sorted(it["sources"]))})
    for name, rows in (("labels", labels), ("key", keyrows)):
        with open(f"labeling/{name}.csv", "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0]), lineterminator="\n")
            w.writeheader(); w.writerows(rows)
    print(f"{len(labels)} items -> labeling/items/, labeling/labels.csv (key in labeling/key.csv)")


if __name__ == "__main__":
    main()
