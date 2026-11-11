#!/usr/bin/env python3
"""Merge the two independent LLM reviews of the sampled test-set candidates (docs/test_set_rule.md, rule 3).

Inputs : data/test/verify_sample.csv (row i = sample i), work/test_verify/review_A.csv (judge),
         work/test_verify/review_B.csv (skeptic), optional work/test_verify/review_C.csv (tie-break)
Final verdict: A and B agree on verified (genuine|partial) vs not -> A's verdict if both verified, else B's;
               otherwise the tie-break reviewer C decides; without C the sample is 'unclear' (not verified).
Output : data/test/verification.csv (every reviewer's verdict and reason is kept for a human audit)
"""
import csv, os

OK = {"genuine", "partial"}
sample = list(csv.DictReader(open("data/test/verify_sample.csv")))


def load(p):
    return {int(r["sample"]): r for r in csv.DictReader(open(p, encoding="utf-8"))} if os.path.exists(p) else {}


A, B, C = (load(f"work/test_verify/review_{x}.csv") for x in "ABC")
rows = []
for i, s in enumerate(sample):
    a, b, c = A.get(i, {}), B.get(i, {}), C.get(i, {})
    va, vb, vc = a.get("verdict", "").strip(), b.get("verdict", "").strip(), c.get("verdict", "").strip()
    disputed = (va in OK) != (vb in OK)
    if not disputed:
        final = va if va in OK else vb
    else:
        final = vc or "unclear"
    rows.append({"sample": f"{i:02d}", **s, "verdict_A": va, "reason_A": a.get("reason", ""), "verdict_B": vb,
                 "reason_B": b.get("reason", ""), "disputed": "yes" if disputed else "no", "verdict_C": vc,
                 "reason_C": c.get("reason", ""), "verdict": final})
with open("data/test/verification.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0]), lineterminator="\n")
    w.writeheader(); w.writerows(rows)
print(f"{len(rows)} samples, disputed {sum(r['disputed'] == 'yes' for r in rows)}, "
      f"need tie-break {sum(r['disputed'] == 'yes' and not r['verdict_C'] for r in rows)}")
