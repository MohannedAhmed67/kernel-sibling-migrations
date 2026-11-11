#!/usr/bin/env python3
"""Guided rule generation, stage 2: a small local LLM writes one Coccinelle rule per task, with test feedback.

A task is either one leaf of the variant tree (decomposed mode) or the union of all task leaves of the
migration (whole mode, the no-decomposition ablation). For each task:
  round 0: the model gets a short SmPL primer (a toy migration that is not one of ours) and the task's
           examples (real removed / added statement units from the training siblings) and writes a rule;
  rounds 1..R: the rule is applied with spatch to every training file of the task; if spatch rejects it, or
           it misses an expected change, or it makes an edit the human did not make, the model gets that
           feedback and rewrites the rule. R = 0 is the no-feedback ablation.
The best rule over all rounds is kept (most expected units reproduced, then fewest extra edits, then earliest).

Only training siblings are read. Held-out targets are never opened here.

Scoring a rule on one training file (statement units, whitespace-normalised, see gcg_decompose.py):
  expected = units removed/added by the task's hunks in that file
  produced = units removed/added by the rule's output
  hit      = |expected ∩ produced|      extra = |produced minus every unit the human changed in that file|
  The file passes if hit == |expected| and extra == 0.

Usage: python3 scripts/gcg_leaf.py --model qwen2.5-coder:7b --migration strlcpy_strscpy [--mode leaf|whole]
         [--rounds 3] [--seed 1] [--temperature 0.4] [--num-ctx 8192] [--leaf L00]
Output: work/gcg/runs/<model>/<mode>_r<R>_s<seed>/<migration>/<task>/round<k>.{prompt.json,response.txt,cocci,eval.json}
        and best.cocci, summary.json in each task folder.
"""
import argparse, collections, json, os, re, shutil, subprocess, sys, time, urllib.request

sys.path.insert(0, os.path.dirname(__file__))
from gcg_decompose import core_edit, hunks, signature  # noqa: E402  (same unit splitting as the tree)

OLLAMA = os.environ.get("OLLAMA_URL", "http://host.docker.internal:11434")

PRIMER = r"""You write Coccinelle semantic patches (SmPL) for Linux kernel C code.

SmPL syntax reminder, on a toy example that is NOT the migration you will be asked about
(kmalloc followed by memset to zero becomes kzalloc):

@@
expression E, SIZE, FLAGS;
@@
- E = kmalloc(SIZE, FLAGS);
+ E = kzalloc(SIZE, FLAGS);
  ...
- memset(E, 0, SIZE);

Rules of thumb:
- A rule is "@@ metavariable declarations @@" followed by code lines. Lines starting with "-" are removed,
  lines starting with "+" are added, lines starting with a space are context that must match but is kept.
- Metavariable kinds: expression, identifier, type, constant, statement, declarer, field ...
- Use metavariables for everything that differs between drivers (variable names, sizes, struct names).
  Never hard-code a driver-specific name.
- "..." matches any code in between. Each minus or plus line must be valid C once the prefix is removed.
- "- E = f(A);" only matches statements that assign the result. To convert a call wherever it appears
  (as a statement, inside a condition, as an argument), write the call without the semicolon:
    - f(A, B)
    + g(A, B)
- Keep the arguments in the same order as in the examples, unless the examples reorder them.
- To match a function whose body you do not change, write its header followed by "{ ... }".
- Several rules can be put one after another in one file. A named rule (@name@) can bind a metavariable
  that a later rule reuses: "@b depends on a@ identifier a.f; @@" reuses identifier f from rule a.
- A struct initializer field is matched like this:
@r@
identifier drv, fn;
@@
  struct some_driver drv = {
-   .old_field = fn,
+   .new_field = fn,
  };

Answer with exactly one ```cocci code block containing the complete semantic patch, and nothing else."""


def chat(model, messages, seed, temperature, num_ctx, timeout=600, retries=1):
    body = json.dumps({"model": model, "messages": messages, "stream": False, "keep_alive": "2m",
                       "options": {"seed": seed, "temperature": temperature, "num_ctx": num_ctx,
                                   "num_predict": 1024}}).encode()
    req = urllib.request.Request(f"{OLLAMA}/api/chat", data=body, headers={"Content-Type": "application/json"})
    for attempt in range(retries + 1):
        t0 = time.time()
        try:
            r = json.loads(urllib.request.urlopen(req, timeout=timeout).read())
            break
        except (TimeoutError, OSError) as e:
            if attempt == retries:
                raise
            print(f"  (model call failed: {e!r}; retrying once)", flush=True)
    return r["message"]["content"], {"seconds": round(time.time() - t0, 1), "prompt_tokens": r.get("prompt_eval_count"),
                                     "output_tokens": r.get("eval_count"), "attempts": attempt + 1}


def unload(model):
    """Free the model's GPU and RAM as soon as a run ends (Ollama otherwise keeps several models resident)."""
    body = json.dumps({"model": model, "keep_alive": 0}).encode()
    try:
        urllib.request.urlopen(urllib.request.Request(f"{OLLAMA}/api/generate", data=body,
                                                      headers={"Content-Type": "application/json"}), timeout=60)
    except OSError:
        pass


def extract_rule(text):
    m = re.search(r"```(?:cocci|smpl|coccinelle)?[^\n]*\n(.*?)```", text, re.S)
    rule = m.group(1) if m else text[text.find("@"):] if "@" in text else text
    return rule.strip() + "\n"


def unit_changes(before, after):
    c = collections.Counter()
    for rem, add in hunks(before, after):
        c.update(("-", u) for u in rem)
        c.update(("+", u) for u in add)
    return c


def spatch(rule_path, before_path, out_path):
    if os.path.exists(out_path):
        os.remove(out_path)
    p = subprocess.run(["spatch", "--very-quiet", "--timeout", "60", "--sp-file", rule_path, before_path,
                        "-o", out_path], capture_output=True, text=True, errors="replace", timeout=300)
    if not os.path.exists(out_path):
        if p.returncode == 0 or "no modified files" in p.stderr:
            shutil.copy(before_path, out_path)
        else:
            return None, p.stderr
    return open(out_path, errors="replace").read(), p.stderr


def evaluate(rule_path, mig, task_hunks, scratch):
    """Apply the rule to every training file of the task and score it. Returns (eval dict, per-file details)."""
    by_file = collections.defaultdict(list)
    for h in task_hunks:
        by_file[h["sibling"]].append(h)
    files, total_need, total_hit, total_extra, n_pass = [], 0, 0, 0, 0
    for k, hs in sorted(by_file.items()):
        d = f"work/h2/{mig}/train/{k}"
        before = open(f"{d}/before.c", errors="replace").read()
        human = unit_changes(before, open(f"{d}/after.c", errors="replace").read())
        expected = collections.Counter()
        for h in hs:
            expected.update(("-", u) for u in h["removed"])
            expected.update(("+", u) for u in h["added"])
        out, err = spatch(rule_path, f"{d}/before.c", f"{scratch}/{k}.out.c")
        if out is None:
            return {"spatch_error": err[-3000:], "files": len(by_file), "pass": 0, "need": sum(
                sum(1 for _ in h["removed"]) + sum(1 for _ in h["added"]) for h in task_hunks), "hit": 0,
                "extra": 0}, []
        produced = unit_changes(before, out)
        hit = sum((expected & produced).values())
        extra_c = produced - human
        need = sum(expected.values())
        ok = hit == need and not extra_c
        files.append({"sibling": k, "need": need, "hit": hit, "extra": sum(extra_c.values()), "pass": ok,
                      "missing": sorted(expected - produced), "extra_units": sorted(extra_c),
                      "produced_any": bool(produced)})
        total_need += need; total_hit += hit; total_extra += sum(extra_c.values()); n_pass += ok
    return {"spatch_error": None, "files": len(files), "pass": n_pass, "need": total_need, "hit": total_hit,
            "extra": total_extra}, files


def show_units(units, limit=6):
    out = [f"{s} {u}" for s, u in units[:limit]]
    if len(units) > limit:
        out.append(f"  ... and {len(units) - limit} more")
    return "\n".join(out)


ERROR_HINTS = [  # generic SmPL repair knowledge keyed on spatch's error text; nothing migration-specific
    (r"around = '(\w+)',\s*\n\s*whole content = .*\bstruct \w+ \1 =",
     "In a declaration such as 'struct T x = {{', the name {0} must be declared as an identifier "
     "metavariable ('identifier {0};'), not as an expression."),
    (r"minus: parse error:.*\n.*\n\s*around = '\.',",
     "A struct field initializer such as '.field = value,' cannot stand alone in a rule. Write it inside the "
     "struct declaration it belongs to (see the 'inside:' line of the examples), as in the primer:\n"
     "@r@\nidentifier drv, fn;\n@@\n  struct the_driver_type drv = {{\n-   .old_field = fn,\n+   .new_field = fn,\n  }};"),
    (r"around = '\.\.\.'",
     "'...' cannot be used at that position; use it between statements or inside an argument list only."),
    (r"(?s)minus: parse error.*?around = '([^']+)'",
     "Parsing failed at '{0}': check that every name is declared with the right metavariable kind "
     "(identifier for names of functions, variables and struct fields; expression for values) and that each "
     "line is valid C once the '-'/'+' prefix is removed."),
    (r"plus: parse error", "A '+' line is not valid C. Check brackets, commas and semicolons."),
    (r"metavariable (\w+) not used", "Metavariable '{0}' is declared but never used: remove it or use it."),
    (r"unbound metavariable|is not a metavariable",
     "A metavariable is used without being declared, or it comes from another rule and lacks the "
     "'rulename.' prefix in its declaration."),
]


def error_hint(err):
    for pat, hint in ERROR_HINTS:
        m = re.search(pat, err)
        if m:
            return hint.format(*m.groups())
    return None


def feedback(ev, details, repeated=False, guided=True):
    if ev.get("lint"):
        return (ev["spatch_error"][len("lint: "):] +
                "\n\nFix the semantic patch and answer with the complete corrected version in one ```cocci block.")
    if ev["spatch_error"]:
        err = "\n".join(l for l in ev["spatch_error"].splitlines() if l.strip())[-1500:]
        hint = error_hint(ev["spatch_error"])
        return ("spatch could not use your semantic patch. Its error output was:\n" + err +
                (f"\n\nHint: {hint}" if hint else "") +
                ("\n\nYou returned the same semantic patch as before and it still fails. Change it." if repeated else "")
                + "\n\nFix the semantic patch and answer with the complete corrected version in one ```cocci block.")
    msg = [f"Your semantic patch was applied to {ev['files']} training files. It fully reproduced the human change "
           f"in {ev['pass']} of them (expected changed lines reproduced: {ev['hit']}/{ev['need']}; "
           f"edits the human did not make: {ev['extra']})."]
    for f in [f for f in details if not f["pass"]][:2]:
        msg.append(f"\nFile {f['sibling']}:")
        if not f["produced_any"]:
            msg.append("  Your patch did not match anything in this file. Expected change:")
        elif f["missing"]:
            msg.append("  These expected changes were not made:")
        if f["missing"]:
            msg.append(show_units(f["missing"]))
            if guided:   # the abstracted minimal edit of what was missed, so the model sees where it generalises
                rem = [u for s, u in f["missing"] if s == "-"]
                add = [u for s, u in f["missing"] if s == "+"]
                cr, ca = core_edit(rem, add)
                msg.append(f"  Pattern of the missed edit: {signature([cr], [ca])}\n  Does your rule match this "
                           "pattern? If a position holds different code here than in your rule, use a metavariable "
                           "for that position.")
        if f["extra_units"]:
            msg.append("  Your patch made these changes, which the human did NOT make (the rule is too broad):")
            msg.append(show_units(f["extra_units"]))
    if repeated:
        msg.append("\nYou returned the same semantic patch as in an earlier round, with the result above. "
                   "Write a DIFFERENT patch.")
    msg.append("\nRewrite the semantic patch so that it reproduces the expected changes and makes no other edits. "
               "Answer with the complete corrected version in one ```cocci block.")
    return "\n".join(msg)


MAX_EXAMPLES = 6


def task_prompt(mig, task, tree, guided=True):
    """Round-0 task description: the change groups, real examples and (guided) the abstracted variant patterns,
    plus, for a companion task, the already-working anchor rule it must build on (its interface)."""
    lines = [f"Linux kernel API migration '{mig}'. Earlier drivers were converted by hand as shown below."
             " Write ONE Coccinelle semantic patch that performs this conversion on other drivers."]
    for leaf in task["leaves"]:
        lines.append(f"\nChange group {leaf['leaf']} ({leaf['n_files']} of {tree['n_training_files']} training "
                     f"files): {leaf['api_mapping'].replace('companion: ', '')}")
        if guided:
            # one example per distinct minimal-edit pattern: the enclosing context line, then only the minimal edit
            cores = collections.OrderedDict()
            for s in leaf["shapes"]:
                ex = s["examples"][0]
                c = cores.setdefault(ex["core_shape"], {"ex": ex, "n": 0})
                c["n"] += s["n"]
            for n_ex, c in enumerate(cores.values()):
                if n_ex >= MAX_EXAMPLES:
                    lines.append(f"  ({len(cores) - n_ex} more variants of this group exist.)")
                    break
                ex = c["ex"]
                lines.append(f"  Variant {n_ex + 1} ({c['n']} hunk(s)), from training file {ex['sibling']}:")
                if ex.get("inside"):
                    lines.append(f"    inside:        {ex['inside']}")
                lines += [f"    context:       {u}" for u in ex.get("context_before", [])]
                lines.append(f"    minimal edit:  - {ex['core_removed'] or '(nothing)'}")
                lines.append(f"                   + {ex['core_added'] or '(nothing: the code is deleted)'}")
                lines.append(f"    pattern:       {ex['core_shape']}")
        else:
            for n_ex, s in enumerate(leaf["shapes"]):
                if n_ex >= MAX_EXAMPLES:
                    lines.append(f"  ({len(leaf['shapes']) - n_ex} more variants of this group exist.)")
                    break
                ex = s["examples"][0]
                lines.append(f"  Example (training file {ex['sibling']}):")
                lines += [f"  - {u}" for u in ex["removed"]] + [f"  + {u}" for u in ex["added"]]
    if guided:
        lines.append("\nIn a 'pattern', ID1, ID2, ... stand for names or expressions that differ between drivers and "
                     "are kept by the change (use metavariables for them), NUM for a number, STR for a string. "
                     "'inside' is the function or struct declaration that contains the edit. Write the rule around "
                     "the minimal edit only; do not copy other fields, arguments or statements of the examples.")
    iface = task.get("interface")
    if iface:
        lines.append(f"\nThe change above only happens in code connected to group {iface['leaf']}, which this "
                     "semantic patch already performs correctly:\n```cocci\n" + iface["rule"] + "```\n"
                     "That patch will be placed first automatically; do not repeat it. Write ONE rule that comes "
                     "after it, starting with this header (the metavariables it lists are bound by the patch above; "
                     "use them in code WITHOUT the prefix, e.g. 'ID1', not 'a0.ID1'; you may declare new "
                     "metavariables in the header too):\n```cocci\n" + iface["header"] + "```\n"
                     "Answer with that one rule in one ```cocci block.")
    return "\n".join(lines)


def tasks_for(tree, mode, only_leaf=None):
    task_leaves = [l for l in tree["leaves"] if l["is_task"]]
    if mode == "whole":
        return [{"name": "WHOLE", "leaves": task_leaves}]
    # anchors first, so that a companion leaf can be given its anchor's working rule as interface
    order = sorted(task_leaves, key=lambda l: (l["possibly_unrelated"], l["leaf"]))
    return [{"name": l["leaf"], "leaves": [l]} for l in order if only_leaf in (None, l["leaf"])]


def interface_for(task, tree, done):
    """For a companion leaf: the anchor leaf sharing most training files with it whose rule fully passed."""
    leaf = task["leaves"][0]
    if not leaf["possibly_unrelated"]:
        return None
    cands = [(len(set(l["files"]) & set(leaf["files"])), l["leaf"]) for l in tree["leaves"]
             if l["leaf"] in done and done[l["leaf"]]["passed"]]
    cands = [c for c in cands if c[0] > 0]
    if not cands:
        return None
    best = max(cands)[1]
    anchor_rule, header = make_interface(done[best]["rule"], task["name"])
    return {"leaf": best, "rule": anchor_rule, "header": header,
            "hunks": [h for l in tree["leaves"] if l["leaf"] == best for h in l["hunks"]]}


def make_interface(rule, child):
    """Written by the framework, not the model: name the anchor rule's first rule 'a0' (if anonymous) and build
    the header of a dependent rule that inherits every metavariable of that first rule.
    Returns (anchor_rule_text, dependent_header_text)."""
    name = "a0"
    m = re.match(r"\s*@\s*(\w+)?[^@\n]*@", rule)
    if m and m.group(1):
        name = m.group(1)
    elif m:
        rule = rule[:m.start()] + re.sub(r"^(\s*)@[^@\n]*@", r"\1@a0@", rule[m.start():], count=1)
    meta = re.search(r"@[^@\n]*@\n(.*?)\n\s*@@", rule, re.S)
    decls = []
    for line in (meta.group(1).splitlines() if meta else []):
        dm = re.match(r"\s*(\w+(?:\s+\w+)?)\s+([^;]+);", line)
        if dm and dm.group(1) not in ("fresh identifier",):
            for v in [v.strip() for v in dm.group(2).split(",") if v.strip() and "." not in v]:
                decls.append(f"{dm.group(1)} {name}.{v};")
    header = f"@c_{child.lower()} depends on {name}@\n" + "\n".join(decls) + "\n@@\n"
    return rule, header


def split_rules(text):
    """Split SmPL text into rules: [(header_line or None, declarations, code)]."""
    rules, cur, state = [], None, "code"
    for line in text.splitlines():
        s = line.strip()
        if state == "code" and re.fullmatch(r"@[^@]*@", s) and s != "@@":
            cur = [s, [], []]; rules.append(cur); state = "meta"
        elif state == "code" and s == "@@" and (cur is None or cur[2]):
            cur = ["@@", [], []]; rules.append(cur); state = "meta"
        elif state == "meta" and s == "@@":
            state = "code"
        elif state == "meta":
            cur[1].append(line)
        else:
            if cur is None:
                cur = [None, [], []]; rules.append(cur)
            cur[2].append(line)
    return rules


def assemble(iface, text):
    """Companion task, assembled by the framework: anchor rule + the model's dependent rule.
    Drops any copy of the anchor rule the model repeated, adds the framework header if the model wrote none,
    and rewrites 'a0.X' in code lines to 'X' (inherited metavariables are used without prefix)."""
    anchor_name = re.match(r"\s*@\s*(\w+)", iface["rule"]).group(1)
    kept = []
    for header, decls, code in split_rules(text):
        if header and re.fullmatch(rf"@\s*{anchor_name}\s*@", header):
            continue                                   # a copy of the anchor rule
        code = [re.sub(rf"\b{anchor_name}\.(\w+)", r"\1", l) for l in code]
        if header is None:
            kept.append(iface["header"].rstrip("\n") + "\n" + "\n".join(code))
        else:
            kept.append(header + "\n" + "\n".join(decls) + "\n@@\n" + "\n".join(code))
    return iface["rule"].rstrip("\n") + "\n\n" + "\n\n".join(k.strip("\n") for k in kept) + "\n"


DECL_KINDS = ("expression", "identifier", "type", "constant", "statement", "declarer", "field", "idexpression",
              "binary operator", "assignment operator", "parameter", "position")


def autofix(rule):
    """Deterministic repair of mechanical SmPL mistakes, applied before spatch (no model call is spent on them).
    Returns (rule, list of applied fixes). Only syntax and metavariable kinds are touched, never the code."""
    fixes, lines = [], rule.splitlines()
    first = next((i for i, l in enumerate(lines) if l.strip()), None)
    if first is not None and not lines[first].lstrip().startswith("@") and \
            re.match(rf"\s*({'|'.join(DECL_KINDS)})\b", lines[first]):
        lines.insert(first, "@@"); fixes.append("added the missing opening '@@'")
    # declarations followed directly by code: close the header
    out, in_meta = [], False
    for l in lines:
        s = l.strip()
        if re.fullmatch(r"@[^@]*@", s):
            in_meta = not (in_meta and s == "@@")
            out.append(l); continue
        if in_meta and l[:1] in "-+ " and not re.match(rf"\s*({'|'.join(DECL_KINDS)})\b", l) and s:
            out.append("@@"); in_meta = False; fixes.append("added the missing '@@' after the declarations")
        out.append(l)
    lines = out
    # drop trailing lone '@@' and '@@' that start an empty rule
    while lines and lines[-1].strip() in ("@@", ""):
        if lines[-1].strip() == "@@":
            fixes.append("removed a trailing '@@'")
        lines.pop()
    rule = "\n".join(lines) + "\n"
    # metavariable kinds: names used as struct fields or callees must be identifiers
    new_rules = []
    for header, decls, code in split_rules(rule):
        body = "\n".join(code)
        new_decls = []
        for d in decls:
            m = re.match(r"(\s*)expression\s+([^;]+);(.*)", d)
            if not m:
                new_decls.append(d); continue
            names = [v.strip() for v in m.group(2).split(",") if v.strip()]
            to_id = [v for v in names if re.search(rf"(->|\.)\s*{re.escape(v)}\b|\b{re.escape(v)}\s*\(", body)]
            keep = [v for v in names if v not in to_id]
            if keep:
                new_decls.append(f"{m.group(1)}expression {', '.join(keep)};{m.group(3)}")
            if to_id:
                new_decls.append(f"{m.group(1)}identifier {', '.join(to_id)};")
                fixes.append(f"declared {', '.join(to_id)} as identifier (used as a field or function name)")
        # placeholders of our own prompt notation (ID1.., NUM, STR) used in code but never declared
        if header is not None:
            declared = {v.strip() for d in new_decls for v in re.sub(r"^\s*[\w ]+?\s+(?=\w+\s*(,|;))", "", d)
                        .rstrip(";").split(",")}
            declared |= {re.sub(r".*\.", "", v) for v in declared}
            used = set(re.findall(r"\b(ID\d+|NUM\d*|STR\d*)\b", "\n".join(l for l in code if l[:1] in "-+ ")))
            missing = sorted(used - declared)
            ids = [v for v in missing if re.search(rf"(->|\.)\s*{v}\b|\b{v}\s*\(", body)]
            exprs = [v for v in missing if v not in ids]
            if ids:
                new_decls.append(f"identifier {', '.join(ids)};")
            if exprs:
                new_decls.append(f"expression {', '.join(exprs)};")
            if missing:
                fixes.append(f"declared placeholder(s) {', '.join(missing)} used without declaration")
        if header is None:
            new_rules.append(body)
        else:
            new_rules.append(header + "\n" + "\n".join(new_decls) + "\n@@\n" + body)
    return "\n\n".join(r.strip("\n") for r in new_rules) + "\n", fixes


C_WORDS = set("""auto break case char const continue default do double else enum extern float for goto if inline int
long register restrict return short signed sizeof static struct switch typedef union unsigned void volatile while
bool true false NULL u8 u16 u32 u64 s8 s16 s32 s64 size_t""".split()) | set(DECL_KINDS) | {
    "depends", "on", "when", "exists", "forall", "strict", "any", "fresh", "typeof", "metavariable", "virtual"}
_FILE_IDS = {}


def file_identifiers(mig):
    """For each identifier, the number of the migration's training files (before.c) that contain it."""
    if mig not in _FILE_IDS:
        c = collections.Counter()
        base = f"work/h2/{mig}/train"
        for k in sorted(os.listdir(base)):
            if os.path.isdir(f"{base}/{k}"):
                c.update(set(re.findall(r"\b[A-Za-z_]\w*\b", open(f"{base}/{k}/before.c", errors="replace").read())))
        _FILE_IDS[mig] = c
    return _FILE_IDS[mig]


def is_callee(n, text):
    """True if `n` is called somewhere in `text`; the name of a function DEFINITION ('static int n(...)' at the
    start of a line) is not a call: it is the driver's own function and therefore driver-specific."""
    for line in text.splitlines():
        for m in re.finditer(rf"\b{n}\s*\(", line):
            if not re.fullmatch(r"\s*(?:static\s+|inline\s+|const\s+)*(?:struct\s+)?\w+[\s*]+", line[:m.start()]):
                return True
    return False


def generalize(rule, mig):
    """Generality critic (deterministic, training files only): a name that the rule matches literally but that
    occurs in only ONE training file is driver-specific, so the rule could not apply to unseen drivers. Such
    names on '-' or context lines are declared as metavariables (identifier when used as a field, callee or in
    a declaration; expression when it stands alone as a function argument). Names on '+' lines only are new
    code and are left alone. Returns (rule, list of applied changes)."""
    counts = file_identifiers(mig)
    out, changes = [], []
    for header, decls, code in split_rules(rule):
        if header is None:
            out.append("\n".join(code)); continue
        declared = set()
        for d in decls:
            body = re.sub(r"^\s*(?:" + "|".join(sorted(DECL_KINDS, key=len, reverse=True)) + r")\s+", "", d.strip())
            declared |= {re.sub(r".*\.", "", v.strip()) for v in body.rstrip(";").split(",") if v.strip()}
        matched = "\n".join(l[1:] for l in code if l[:1] in ("-", " "))

        def words(prefixes):
            return set(re.findall(r"\b[A-Za-z_]\w*\b",
                                  re.sub(r'"[^"]*"', "", "\n".join(l[1:] for l in code if l[:1] in prefixes))))
        # only names the change KEEPS (context, or on both a '-' and a '+' line) can be driver-specific; a name
        # that is only removed is the API being migrated, and a callee is a function API, so both stay literal
        kept = words(" ") | (words("-") & words("+"))
        names = sorted({n for n in kept if n not in declared and n not in C_WORDS and counts.get(n, 0) == 1
                        and not is_callee(n, matched)})
        ids, exprs = [], []
        for n in names:
            if re.search(rf"[(,]\s*{n}\s*[,)]", matched) and not re.search(rf"(->|\.)\s*{n}\b|\b{n}\s*\(", matched):
                exprs.append(n)
            else:
                ids.append(n)
        new_decls = list(decls)
        if ids:
            new_decls.append(f"identifier {', '.join(ids)};")
        if exprs:
            new_decls.append(f"expression {', '.join(exprs)};")
        if names:
            changes.append(f"made driver-specific name(s) {', '.join(names)} into metavariables")
        out.append(header + "\n" + "\n".join(new_decls) + "\n@@\n" + "\n".join(code))
    return "\n\n".join(r.strip("\n") for r in out) + "\n", changes


def lint(rule):
    """Cheap checks before spatch runs, on the raw text; returns a message for the model or None."""
    lines = rule.splitlines()
    if not any(l.startswith(("-", "+")) for l in lines):
        return ("Your semantic patch has no line starting with '-' or '+', so it changes nothing. Mark the lines "
                "to remove with '-' and the lines to add with '+'.")
    code = [l for _, _, c in split_rules(rule) for l in c]
    if any(re.search(r"//|/\*", l) for l in code if not l.startswith(("-", "+"))):
        return ("Your semantic patch contains comments in place of code. To match a function body you do not "
                "change, write '{ ... }' (three dots), not a comment.")
    for side in "-+":
        text = " ".join(l[1:] if l[:1] in (side, " ") else "" for l in code)
        if text.count("{") != text.count("}") or text.count("(") != text.count(")"):
            return (f"Brackets are unbalanced in your semantic patch (counting the lines without prefix together "
                    f"with the '{side}' lines). Every '{{' needs its '}}' and every '(' its ')': write complete "
                    "statements, and use '...' for code you do not need to spell out.")
    return None


def run_task(args, mig, tree, task, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    task_hunks = [h for l in task["leaves"] for h in l["hunks"]]
    if task.get("interface"):   # the answer includes the anchor rule, so the anchor's changes are expected too
        task_hunks += task["interface"]["hunks"]
    messages = [{"role": "system", "content": PRIMER},
                {"role": "user", "content": task_prompt(mig, task, tree, guided=args.guided)}]
    best, history, seen_rules = None, [], []
    temperature = args.temperature
    for rnd in range(args.rounds + 1):
        json.dump(messages, open(f"{out_dir}/round{rnd}.prompt.json", "w"), indent=1)
        text, usage = chat(args.model, messages, args.seed + rnd, temperature, args.num_ctx)
        open(f"{out_dir}/round{rnd}.response.txt", "w").write(text)
        raw, fixes = extract_rule(text), []
        if args.guided and args.autofix:
            raw, fixes = autofix(raw)
        if args.guided and args.critic:
            raw, gen = generalize(raw, mig)
            fixes += gen
        rule = assemble(task["interface"], raw) if task.get("interface") else raw
        norm_rule = re.sub(r"\s+", " ", rule).strip()
        repeated = norm_rule in seen_rules
        seen_rules.append(norm_rule)
        usage["temperature"] = temperature
        usage["repeated"] = repeated
        if repeated and args.guided:   # stall: the model ignored the feedback; sample more freely next round
            temperature = min(1.0, temperature + 0.3)
        rule_path = f"{out_dir}/round{rnd}.cocci"
        open(rule_path, "w").write(rule)
        scratch = f"{out_dir}/round{rnd}.out"
        os.makedirs(scratch, exist_ok=True)
        model_part = rule[len(task["interface"]["rule"].rstrip("\n")):] if task.get("interface") else rule
        problem = lint(model_part) if args.guided else None
        if problem:
            ev, details = {"spatch_error": "lint: " + problem, "files": len({h["sibling"] for h in task_hunks}),
                           "pass": 0, "need": sum(len(h["removed"]) + len(h["added"]) for h in task_hunks),
                           "hit": 0, "extra": 0, "lint": True}, []
        else:
            ev, details = evaluate(rule_path, mig, task_hunks, scratch)
        ev.update(round=rnd, autofixes=fixes, **usage)
        json.dump({"eval": ev, "files": details}, open(f"{out_dir}/round{rnd}.eval.json", "w"), indent=1)
        history.append(ev)
        key = (ev["spatch_error"] is None, ev["hit"], -ev["extra"], -rnd)
        if best is None or key > best[0]:
            best = (key, rnd, rule, ev)
        print(f"  {task['name']} round {rnd}: " + ("SPATCH ERROR" if ev["spatch_error"] else
              f"pass {ev['pass']}/{ev['files']} hit {ev['hit']}/{ev['need']} extra {ev['extra']}") +
              f"  ({usage['seconds']}s)", flush=True)
        if ev["spatch_error"] is None and ev["pass"] == ev["files"]:
            break
        if rnd < args.rounds:
            fb = feedback(ev, details, repeated=repeated and args.guided, guided=args.guided)
            messages += [{"role": "assistant", "content": text}, {"role": "user", "content": fb}]
    open(f"{out_dir}/best.cocci", "w").write(best[2])
    b = best[3]
    summary = {"migration": mig, "task": task["name"], "leaves": [l["leaf"] for l in task["leaves"]],
               "interface": (task.get("interface") or {}).get("leaf"), "best_round": best[1], "best": b,
               "passed": b["spatch_error"] is None and b["pass"] == b["files"], "rule": best[2], "rounds": history,
               "config": {k: v for k, v in vars(args).items() if k != "migration"}}
    json.dump(summary, open(f"{out_dir}/summary.json", "w"), indent=1)
    return summary


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--migration", required=True, nargs="+")
    ap.add_argument("--mode", choices=["leaf", "whole"], default="leaf")
    ap.add_argument("--rounds", type=int, default=3)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--temperature", type=float, default=0.4)
    ap.add_argument("--num-ctx", type=int, default=8192)
    ap.add_argument("--leaf")
    ap.add_argument("--unguided", dest="guided", action="store_false",
                    help="ablation: no variant patterns, no anchor interface, no lint, no auto-repair, no stall handling")
    ap.add_argument("--no-autofix", dest="autofix", action="store_false", help="ablation: guided, but no auto-repair")
    ap.add_argument("--critic", action="store_true",
                    help="guided only: apply the generality critic (driver-specific names -> metavariables)")
    args = ap.parse_args()
    variant = ("gc" if args.critic else "g" if args.autofix else "gnofix") if args.guided else "u"
    tag = f"{args.mode}_{variant}_r{args.rounds}_s{args.seed}"
    for mig in args.migration:
        tree = json.load(open(f"work/gcg/{mig}/tree.json"))
        run = f"work/gcg/runs/{args.model.replace(':', '_')}/{tag}/{mig}"
        print(f"{mig} [{args.model}, {tag}]", flush=True)
        done = {}
        for task in tasks_for(tree, args.mode, args.leaf):
            if args.guided:
                task["interface"] = interface_for(task, tree, done)
            s = run_task(args, mig, tree, task, f"{run}/{task['name']}")
            done[task["name"]] = s
    unload(args.model)


if __name__ == "__main__":
    main()
