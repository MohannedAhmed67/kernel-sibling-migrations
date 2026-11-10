# Phase 1a — Are DRIVEBENCH / AUTODRIVER public? (checked 2026-11-10)

**Answer: no public copy of the paper's DRIVEBENCH case packs or AUTODRIVER code was found.**
We therefore build our own case list from Linux git history (v5.10..v6.10), as planned.

## Where we looked

| Source | Result |
|---|---|
| arXiv:2511.18924 (abstract, PDF, HTML, TeX source) | Only v1 exists. No code/data link, footnote or data-availability URL. The abstract says DRIVEBENCH and tooling are released; Sec. 4.5 ("Dataset Statistics and Release") is a one-sentence stub. |
| github.com/kdrift-dev | 3 public repos: `driver_agent`, `unictags-coccinelle-mode0`, `fleeti`. None contains the paper's v5.10–v6.10 case packs. |
| `kdrift-dev/driver_agent` | "Driver-Agent Workflow": a staged LLM pipeline for driver migration across release pairs ending at v7.0 (e.g. v6.19 → v7.0-rc1). It is never called AUTODRIVER. Kernel-commit info in its case packs is disabled by design (`commit_info_policy: disabled_by_default`). No LICENSE file. Looks like a later system, not the paper's artifact. |
| `kdrift-dev/unictags-coccinelle-mode0` | Reproduces the interface-analysis figures of *Understanding Collateral Evolution in Linux Device Drivers* across many kernel versions. Related to our topic; not a benchmark. |
| kdrift.dev | Advertises a "DRIFTBENCH" dataset. The "Explore dataset" button links to `#`, and no downloadable data was found. |
| github.com/FlashLabAE | Repos unrelated to kernel drivers (e.g. HBFSim, ServeLoop). |
| Hugging Face, Zenodo, GitHub repository search | Nothing for the kernel DRIVEBENCH. (A Zenodo record named "AutoDriver Evaluation Data", records/15560002, is an unrelated name collision.) |

## Facts from the paper that shape our study (arXiv:2511.18924 v1)

- **No retrieval of earlier similar migrations.** Prompts are built from the case's own pre/post code, commit
  message and metadata (Sec. 5.2); context comes from a kernel LSP (Sec. 5.3).
  "Kernel-aware retrieval systems that dynamically extract API changes from version control" is named as
  future work (Sec. 8.2).
- **Stated weaknesses:** missing propagation of related changes across dependent code; multi-file and
  dependency-heavy updates (Sec. 7.2, 7.5, 8.2). Future work: "coordinated dependency tracking and
  hierarchical regeneration" (Sec. 7.5).
- **Coccinelle** is not used or evaluated in the paper's compiled PDF.
- Verbatim from the v1 text (checked against the downloaded PDF):
  - Abstract: "In evaluation across 55 cases, AUTODRIVER achieves 56.4% compilation success".
  - Failure modes: "incomplete structure updates, partial function migrations, and missing propagation of related
    changes across dependent code".
  - Future work: "coupling AUTODRIVER with kernel-aware retrieval systems that dynamically extract API changes from
    version control or symbol databases".
  - Build setup: "Kernel builds require a case-sensitive filesystem, so a dedicated APFS volume was created and
    mounted into Docker containers."
  - Authors: Kharlamova, Liu, Zhang, Yang, Alqasimi, Sun, Xue.
- **Their evaluation unit** is a single driver commit plus its triggering kernel commit. Ours is the same idea,
  restricted to API migrations where many drivers were converted.
