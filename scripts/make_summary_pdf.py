#!/usr/bin/env python3
"""One-page PDF summary (results/summary.pdf). Every number is read from results/ and data/ files."""
import csv
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.image as mpimg


def rows(p):
    return list(csv.DictReader(open(p, newline="")))


h1 = {r["migration"]: r for r in rows("results/h1_summary.csv")}
h2 = {(r["source"], r["migration"]): r for r in rows("results/h2_final_summary.csv")}
stats = dict(l.split(": ", 1) for l in open("data/cases_stats.txt").read().splitlines())
pooled = next(v for k, v in h1.items() if k.startswith("ALL main"))
forced = h1["ALL forced (old API removed by v6.10)"]
m, s = h2[("manual", "ALL")], h2[("spinfer", "ALL")]
ml, sl = h2[("manual", "ALL_where_spinfer_inferred_a_rule")], h2[("spinfer", "ALL_where_spinfer_inferred_a_rule")]

fig = plt.figure(figsize=(8.27, 11.69))  # A4 portrait
fig.patch.set_facecolor("white")
y = 0.965


import textwrap


def line(text, size=9.5, weight="normal", dy=0.022, color="#0b0b0b"):
    """Draw text wrapped to the page width; each extra wrapped line moves the cursor down."""
    global y
    width = int(98 * 9.5 / size * (0.88 if weight == "bold" else 1.0))   # characters per line at this font size
    parts = textwrap.wrap(text, width=width, subsequent_indent="  " if text.startswith("•") else "")
    step = size / 9.5 * 0.0165
    for i, part in enumerate(parts):
        fig.text(0.07, y - i * step, part, fontsize=size, weight=weight, color=color, va="top")
    y -= dy + (len(parts) - 1) * step


line("Sibling migrations as free supervision for Linux driver updates — pilot results", 13, "bold", 0.03)
line("Mohanned Ahmed · reproducible code and data in the linked repository · related to arXiv:2511.18924 (AUTODRIVER)", 8.5, dy=0.035, color="#52514e")
line("Idea", 11, "bold")
line("When a kernel API changes, many drivers are converted one after another. The earlier conversions ('siblings') are real, reviewed examples of the needed change. Do they exist in time, and can they drive the next driver's update?", dy=0.032)
line("H1 — do earlier siblings exist?  (Linux v5.10–v6.10)", 11, "bold")
line(f"• {stats['included migrations'].split()[0]} verified API migrations, each performed in >= 3 commits; {int(stats['candidate conversions']):,} candidate driver-file conversions.", dy=0.019)
line(f"• Sibling already in a released kernel when the target patch was written: {int(pooled['e2_released_before_written']):,}/{int(pooled['targets']):,} "
     f"({pooled['e2_released_before_written_pct']}%); for migrations whose old API was removed: "
     f"{int(forced['e2_released_before_written']):,}/{int(forced['targets']):,} ({forced['e2_released_before_written_pct']}%).", dy=0.019)
line(f"• Same, but the sibling must also come from a different author: {pooled['e3_released_before_written_other_author_pct']}% "
     f"(many migrations were swept by one person in a burst).", dy=0.032)
line("H2 — can a rule derived only from the 20 earliest siblings migrate held-out drivers?", 11, "bold")
line(f"• 5 migrations, 100 held-out drivers written after the training siblings ({m['buildable']} compile on x86_64 allmodconfig).", dy=0.019)
line(f"• Coccinelle rule written by an LLM agent restricted to the siblings: correct and compiles for {m['success_of_buildable']}/{m['buildable']}.", dy=0.019)
line(f"• Spinfer (USENIX ATC'20) on the same siblings: {s['success_of_buildable']}/{s['buildable']} "
     f"(no rule for 2 struct-initializer migrations; on the other 3: {sl['success_of_buildable']}/{sl['buildable']} vs {ml['success_of_buildable']}/{ml['buildable']}).", dy=0.019)
line(f"• {s['wrong_but_compiles']} Spinfer outputs (and {m['wrong_but_compiles']} LLM-written) compile but change behaviour: compile success needs a semantic check.", dy=0.012)

img = mpimg.imread("results/h2_rules.png")
ax = fig.add_axes([0.05, 0.17, 0.9, y - 0.18])
ax.imshow(img); ax.axis("off")

y = 0.155
line("Limitations (pilot)", 10, "bold", 0.02)
line("Population is widely converted migrations only; siblings found with the migration known (existence, not retrieval); 5 hand-picked migrations in H2; the LLM rule author may know these migrations from pre-training (file access audited); non-exact verdicts by LLM reviewers; per-file x86 compile checks only; AUTODRIVER itself and LLM+exemplar repair (H3) were not run.", 8.5, dy=0.028)
line("Next step: give sibling exemplars to an AUTODRIVER-style LLM pipeline and measure the change in compile and semantic accuracy.", 9, "bold")
fig.savefig("results/summary.pdf")
fig.savefig("work/summary_preview.png", dpi=90)  # git-ignored preview
print("wrote results/summary.pdf")
