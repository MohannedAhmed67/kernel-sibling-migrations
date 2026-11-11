# Related work and novelty check (checked 2026-11-10)

Metadata was checked against Crossref, OpenAlex, arXiv, HAL and USENIX pages. Quotes are verbatim from the fetched
abstracts or PDFs. **This list decides how we may (and may not) describe our contribution.**

## Prior work that already does part of our idea

| Work | What it does | Overlap with us |
|---|---|---|
| Padioleau, Lawall, Muller. *Understanding Collateral Evolution in Linux Device Drivers.* EuroSys 2006. doi:10.1145/1217935.1217942 | Defines "collateral evolutions" (driver changes forced by kernel API changes) and gives a taxonomy. | Problem definition. Our "sibling migrations" are collateral evolutions. |
| Padioleau, Lawall, Hansen, Muller. *Documenting and automating collateral evolutions in Linux device drivers.* EuroSys 2008. doi:10.1145/1352592.1352618 | Introduces Coccinelle / semantic patches; hand-written rules for 62 past collateral evolutions "update over 93% of the files completely". | Rules there are written by hand by experts, with no held-out-by-time split. |
| Andersen, Lawall. *Generic Patch Inference.* ASE 2008. doi:10.1109/ase.2008.44 (journal version: ASE Journal 17(2), 2010) | "spdiff": infers a generic patch from a few (before, after) file pairs and applies it to other drivers. | **Same core idea as H2** (rule from a few examples, applied to other drivers). Examples are hand-picked, not retrieved. |
| Serrano, Nguyen, Thung, Jiang, Lo, Lawall, Muller. *SPINFER: Inferring Semantic Patches for the Linux Kernel.* USENIX ATC 2020 | Infers Coccinelle rules automatically from example changes. Its "transformation experiment" learns from "the first 10 changed files, as indicated by the commit author date" and evaluates on the rest; "86% precision and 49% recall for the transformation experiment" (node-level, vs. expert patches). Code: gitlab.inria.fr/spinfer/spinfer (GPL-2.0+, last code change 2020). | **Closest prior work to H2, including a chronological held-out split.** No compile or boot check; datasets end around 2018. |
| Lawall, Palinski, Gnirke, Muller. *Fast and Precise Retrieval of Forward and Back Porting Information for Linux Device Drivers.* USENIX ATC 2017 (Prequel + gcc-reduce) | Searches commit history with patch-like queries to find commits that show how to port a driver. | **Retrieval of relevant past commits from git history.** Our H1 measures only whether siblings *exist*, given that the migration is known; it does not test retrieving them. |
| Shariffdeen et al. *Automated patch backporting in Linux (experience paper)* (FixMorph). ISSTA 2021. doi:10.1145/3460319.3464821 | Synthesizes a transformation rule from one mainline patch for backporting. | Rule synthesis, but for backporting rather than API-migration siblings. |
| Li et al. *PortGPT.* IEEE S&P 2026. arXiv:2510.22396; Dang et al. *MigGPT.* NeurIPS 2025. arXiv:2504.09474 | LLM agents for kernel patch backporting / out-of-tree patch migration (PortGPT uses git history and compiler feedback). | LLM + history, but for backporting, not in-tree API-migration siblings. |
| Kharlamova et al. *LLM-Driven Kernel Evolution* (DRIVEBENCH/AUTODRIVER). arXiv:2511.18924 | LLM multi-agent driver co-evolution, with compile and QEMU checks. | Our target system. It retrieves no exemplars and generates no rules; it names "kernel-aware retrieval" as future work. |

## What we must NOT claim
- That learning a migration rule from earlier examples is new (spdiff 2008, Spinfer 2020).
- That retrieving useful past commits from kernel history is new (Prequel, ATC 2017).

## What appears open (nothing found in the searches above)
1. Measuring, on **modern kernels (v5.10–v6.10)**, how often earlier sibling migrations exist for the
   driver-update cases an LLM pipeline like AUTODRIVER targets (**H1**).
2. Validating sibling-derived rules by **compilation**, not only by line or node overlap with the human patch (**H2**).
3. Comparing rule-based and LLM+exemplar repair on the same chronological split, with rules handling the easy
   cases and the LLM the residue (**H3**). Searches of OpenAlex and arXiv abstracts for "Coccinelle", "SmPL" and
   "semantic patch" combined with LLM terms, and of works citing Spinfer and spdiff, found no paper combining LLMs
   with Coccinelle semantic patches for kernel driver migration. This was not an exhaustive survey.

Framing: *"retrieval of sibling migrations as context for LLM driver co-evolution, with rule-based (Coccinelle) application
validated by compilation"*. This builds on Spinfer/Prequel and plugs into AUTODRIVER's stated future work.

## Added 2026-11-11 (before writing the preprint)

| Work | What it does | Overlap with us |
|---|---|---|
| Yusuf, Huang, Lawall, Jiang, Lo, Bui, Li, Wu, Yu. *Deep Learning-Based Automatic Semantic Patch Generation for the Linux Kernel: How Far Are We?* Manuscript (author copy at imamnurby.github.io/assets/files/spatch_emse.pdf; data: github.com/imamnurby/SMPL-How-Far-Are-We; venue not confirmed) | Compares Spinfer with GPT-4 (gpt-4-2024-11-20), Claude-3-7-sonnet-20250219 and DeepSeek-V3 generating SmPL from change examples, on reproducing the examples and on unseen code. Abstract: "Deep learning models generate valid semantic patches with minimal examples but struggle with syntax correctness, while Spinfer ensures syntactic validity but creates overly specific patches"; "both approaches perform poorly on diverse change examples with multiple variants". Proposes as future work "methods for automatically refining abstraction based on feedback from patch application results". | **LLMs writing Coccinelle rules is not new.** Differences we may claim: small local models (7-8B, 4B) instead of frontier APIs; a decomposition + feedback + repair framework rather than one-shot prompting; chronological sibling split; compile validation; a contamination-free post-cutoff test set. |
| Almorsi, Ahmed, Gomaa. *Guided Code Generation with LLMs: A Multi-Agent Framework for Complex Code Tasks.* arXiv:2501.06625 | Hierarchical decomposition, bottom-up generation, critic/testing agents; Llama 3.1 8B int4 on HumanEval. | Our framework adapts this design to semantic-patch generation (author's own prior work). |
| Lin, Mukherjee, Rawat, Zhang, Fonseca. *Learning From Developers: Towards Reliable Patch Validation at Scale for Linux.* arXiv:2603.24825 (2026) | FLINT: patch validation from past developer review discussions plus an LLM. | Kernel + LLM, but patch review, not rule generation. Not essential to cite. |

Revised "must not claim": that LLM generation of SmPL / Coccinelle rules is new (Yusuf et al.).
