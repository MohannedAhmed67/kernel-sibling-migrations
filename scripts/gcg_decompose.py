#!/usr/bin/env python3
"""Guided rule generation, stage 1: decompose a migration's training siblings into a tree of variants.

The tree is built from the human diffs by script, not by the LLM (the LLM-made root split is the failure mode
reported for Guided Code Generation, arXiv:2501.06625).

  migration (root)
    -> level 1, "API mapping": for an anchor hunk, the API names (first identifier of each old/new-pattern
       match) it removes and introduces; for a companion hunk, the C keywords and identifiers recurring in
       >= 2 training files that it removes and introduces. Driver-local names never split a leaf.
       E.g. "-pci_alloc_consistent  +dma_alloc_coherent". One leaf = one task for the rule writer.
    -> level 2, "shape": the hunk with every identifier that survives the edit replaced by a numbered
       metavariable (ID1, ID2, ... in order of first appearance), numbers by NUM and strings by STR.
       Shapes show the rule writer which syntactic variants its leaf rule must cover.

A hunk is one run of changed statement units (whitespace-normalised; a unit ends at ";", "{", "}" or a
full-line comment, so multi-line calls stay whole; preprocessor lines are units) in one training file.
Hunks whose removed and added sides are identical after normalisation are dropped (pure reformatting).
A hunk is an "anchor" if it matches the migration's old- or new-API pattern; other hunks are "companions"
(e.g. a function signature that changes together with a struct initializer). Companions are kept: a leaf
that never contains an anchor is flagged possibly_unrelated (it may be churn in the same commit).
A leaf becomes a task for the rule writer (is_task) if it contains an anchor hunk or occurs in >= 2 training
files; a companion leaf seen in a single file is treated as unrelated churn and is not given to the writer.

Input : work/h2/<migration>/train/<k>/{before.c, after.c, meta.json}  (from scripts/h2_split.py)
Output: work/gcg/<migration>/tree.json, results/gcg_tree_summary.csv
"""
import collections, csv, difflib, json, os, re, sys

MIGRATIONS = sys.argv[1:] or ["ida_simple", "i2c_probe_new", "platform_remove_new", "strlcpy_strscpy",
                              "pci_dma_wrappers"]
MIGS = {m["id"]: m for m in json.load(open("data/migrations.json"))["migrations"]}

C_KEYWORDS = set("""auto break case char const continue default do double else enum extern float for goto if inline
int long register restrict return short signed sizeof static struct switch typedef union unsigned void volatile while
bool true false NULL u8 u16 u32 u64 s8 s16 s32 s64 size_t""".split())
TOKEN = re.compile(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[A-Za-z_]\w*|\d\w*(?:\.\d+)?|->|\+\+|--|<<=|>>=|'
                   r'[-+*/%&|^<>=!]=|&&|\|\||<<|>>|\S')
IDENT = re.compile(r"[A-Za-z_]\w*$")


def norm_lines(text):
    return [re.sub(r"\s+", " ", l).strip() for l in text.splitlines() if l.strip()]


def norm_units(text):
    """Split C source into statement-like units, so a call spread over several lines stays in one unit.
    Preprocessor lines are units of their own; other code is joined and cut after ';', '{' and '}'."""
    units, buf = [], []
    for line in norm_lines(text):
        if line.startswith("#"):
            if buf:
                units.append(" ".join(buf)); buf = []
            units.append(line)
        else:
            buf.append(line)
            if line.endswith((";", "{", "}", "*/")):
                units.append(" ".join(buf)); buf = []
    if buf:
        units.append(" ".join(buf))
    return units


def top_header(units, i):
    """Index of the unit that opens the top-level block (function body or struct initializer) containing unit i,
    found by brace depth; None if unit i is at file level."""
    depth, header = 0, None
    for j in range(i):
        ts = TOKEN.findall(units[j])
        if depth == 0 and "{" in ts:
            header = j
        depth = max(0, depth + ts.count("{") - ts.count("}"))
        if depth == 0:
            header = None
    return header


def hunks(before, after, context=False):
    """Yield (removed_units, added_units) for each run of changed statement units; with context=True also the
    unchanged unit just before and just after the hunk, and the header of the top-level block (function or struct
    initializer, e.g. 'static struct platform_driver x = {') that contains it."""
    a, b = norm_units(before), norm_units(after)
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes():
        if tag != "equal":
            rem, add = a[i1:i2], b[j1:j2]
            if " ".join(rem).replace(" ", "") != " ".join(add).replace(" ", ""):
                if context:
                    top = top_header(a, i1)
                    ctx = [u for u in a[max(0, i1 - 1):i1] if top is None or u != a[top]]
                    yield rem, add, ctx, a[i2:i2 + 1], (a[top] if top is not None else None)
                else:
                    yield rem, add


def tokens(lines):
    return TOKEN.findall(" ".join(lines))


def _expand(ts, lo, hi):
    """Widen token span [lo, hi) to a whole syntactic element: leftwards to the nearest ',', ';', '{', '}', '='
    or unmatched '(' at depth 0; rightwards (after closing every bracket opened inside the span) to the nearest
    ',', ';', '}' or unmatched ')' at depth 0."""
    depth, i = 0, lo
    while i > 0:
        t = ts[i - 1]
        if t in ")]":
            depth += 1
        elif t in "([":
            if depth == 0:
                break
            depth -= 1
        elif depth == 0 and t in (",", ";", "{", "}", "="):
            break
        i -= 1
    depth = sum((t in "([") - (t in ")]") for t in ts[i:hi])
    j = hi
    while j < len(ts):
        t = ts[j]
        if depth == 0 and t in (",", ";", "}", ")", "]"):
            break
        depth += (t in "([") - (t in ")]")
        j += 1
    return i, j


def core_edit(rem, add):
    """Minimal edit inside a hunk: drop the tokens both sides share at the start and at the end, then widen to
    the enclosing element on each side. Returns (removed_core, added_core) as token strings."""
    a, b = tokens(rem), tokens(add)
    p = 0
    while p < min(len(a), len(b)) and a[p] == b[p]:
        p += 1
    q = 0
    while q < min(len(a), len(b)) - p and a[-1 - q] == b[-1 - q]:
        q += 1
    if not a or not b:            # pure insertion or deletion: the whole hunk is the edit
        return " ".join(a), " ".join(b)
    la, ha = _expand(a, p, len(a) - q)
    lb, hb = _expand(b, p, len(b) - q)
    lo, n_suffix = min(la, lb), max(len(a) - ha, 0)
    n_suffix = min(n_suffix, max(len(b) - hb, 0))
    return " ".join(a[lo:len(a) - n_suffix]), " ".join(b[lo:len(b) - n_suffix])


def api_names(lines, pattern):
    """First identifier of every old/new-API pattern match, e.g. 'pci_alloc_consistent', 'probe_new'."""
    return {re.search(r"[A-Za-z_]\w*", mt.group(0)).group(0) for mt in pattern.finditer(" ".join(lines))}


def leaf_key(rem, add, pattern, recurrent):
    """Level-1 grouping key.
    Anchor hunk: the API names it removes and introduces (local names such as error labels are ignored).
    Companion hunk: keywords and identifiers recurring in >= 2 training files that it removes / introduces."""
    ra, aa = api_names(rem, pattern), api_names(add, pattern)
    if ra or aa:
        return True, sorted(ra - aa), sorted(aa - ra)
    rid = {t for t in tokens(rem) if IDENT.match(t)}
    aid = {t for t in tokens(add) if IDENT.match(t)}
    keep = lambda s: sorted(t for t in s if t in C_KEYWORDS or t in recurrent)
    return False, keep(rid - aid), keep(aid - rid)


def signature(rem, add):
    rt, at = tokens(rem), tokens(add)
    rid = {t for t in rt if IDENT.match(t)}
    aid = {t for t in at if IDENT.match(t)}
    shared = (rid & aid) - C_KEYWORDS
    names = {}

    def abstract(ts):
        out = []
        for t in ts:
            if t in shared:
                names.setdefault(t, f"ID{len(names) + 1}")
                out.append(names[t])
            elif t[0] in "\"'":
                out.append("STR")
            elif t[0].isdigit():
                out.append("NUM")
            else:
                out.append(t)
        return " ".join(out)

    return abstract(rt) + "  ==>  " + abstract(at)


def build_tree(mig):
    m = MIGS[mig]
    pattern = re.compile("|".join(p for p in (m["old"], m["new"]) if p))
    base = f"work/h2/{mig}/train"
    file_hunks = []
    for k in sorted(x for x in os.listdir(base) if os.path.isdir(f"{base}/{x}")):
        d = f"{base}/{k}"
        before, after = open(f"{d}/before.c", errors="replace").read(), open(f"{d}/after.c", errors="replace").read()
        file_hunks.append((k, list(hunks(before, after, context=True))))
    # identifiers that a hunk removes or introduces in >= 2 different training files (not driver-local names)
    seen_in = collections.defaultdict(set)
    for k, hs in file_hunks:
        for rem, add, _, _, _ in hs:
            rid = {t for t in tokens(rem) if IDENT.match(t)}
            aid = {t for t in tokens(add) if IDENT.match(t)}
            for t in rid ^ aid:
                seen_in[t].add(k)
    recurrent = {t for t, ks in seen_in.items() if len(ks) >= 2}

    leaves = collections.OrderedDict()
    for k, hs in file_hunks:
        for rem, add, ctx_before, ctx_after, inside in hs:
            is_anchor, removed_ids, added_ids = leaf_key(rem, add, pattern, recurrent)
            shape = signature(rem, add)
            key = ("" if is_anchor else "companion: ") + "-" + " -".join(removed_ids) + "  +" + " +".join(added_ids)
            leaf = leaves.setdefault(key, {"removed_ids": removed_ids, "added_ids": added_ids, "files": set(),
                                           "n_hunks": 0, "n_anchor_hunks": 0, "shapes": collections.OrderedDict(),
                                           "hunks": []})
            leaf["files"].add(k)
            leaf["hunks"].append({"sibling": k, "removed": rem, "added": add})
            leaf["n_hunks"] += 1
            leaf["n_anchor_hunks"] += is_anchor
            s = leaf["shapes"].setdefault(shape, {"shape": shape, "n": 0, "examples": []})
            s["n"] += 1
            if len(s["examples"]) < 2:
                cr, ca = core_edit(rem, add)
                s["examples"].append({"sibling": k, "removed": rem, "added": add,
                                      "inside": inside, "context_before": ctx_before, "context_after": ctx_after,
                                      "core_removed": cr, "core_added": ca, "core_shape": signature([cr], [ca])})
    out = []
    for i, (key, leaf) in enumerate(sorted(leaves.items(), key=lambda kv: (-len(kv[1]["files"]), kv[0]))):
        out.append({"leaf": f"L{i:02d}", "api_mapping": key, "removed_ids": leaf["removed_ids"],
                    "added_ids": leaf["added_ids"], "n_files": len(leaf["files"]),
                    "files": sorted(leaf["files"]), "n_hunks": leaf["n_hunks"],
                    "n_anchor_hunks": leaf["n_anchor_hunks"], "possibly_unrelated": leaf["n_anchor_hunks"] == 0,
                    "is_task": leaf["n_anchor_hunks"] > 0 or len(leaf["files"]) >= 2,
                    "shapes": sorted(leaf["shapes"].values(), key=lambda s: -s["n"]),
                    "hunks": leaf["hunks"]})
    return {"migration": mig, "n_training_files": len(file_hunks), "leaves": out}


def main():
    rows = []
    for mig in MIGRATIONS:
        tree = build_tree(mig)
        os.makedirs(f"work/gcg/{mig}", exist_ok=True)
        json.dump(tree, open(f"work/gcg/{mig}/tree.json", "w"), indent=1)
        L = tree["leaves"]
        rows.append({"migration": mig, "training_files": tree["n_training_files"], "leaves": len(L), "task_leaves": sum(l["is_task"] for l in L),
                     "anchor_leaves": sum(not l["possibly_unrelated"] for l in L),
                     "anchor_leaves_in_2plus_files": sum(not l["possibly_unrelated"] and l["n_files"] >= 2 for l in L),
                     "shapes": sum(len(l["shapes"]) for l in L),
                     "hunks": sum(l["n_hunks"] for l in L)})
    os.makedirs("results", exist_ok=True)
    with open("results/gcg_tree_summary.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    for r in rows:
        print(r)


if __name__ == "__main__":
    main()
