# Artifacts

`gcg_prompts_responses.tar.xz`: every prompt sent to the local models, every model response, every candidate rule
(`.cocci`) with its training-set score (`.eval.json`), per-task summaries, compile-critic decisions, and the composed
and final rules of all runs (3 models x 6 configurations x 3 seeds, development and test migrations).
Layout: `runs/<model>/<config>_s<seed>/<migration>/<task>/round<k>.*`, `critic/`, `composed/`, `final/`.
Extract with `tar -xJf gcg_prompts_responses.tar.xz` into `work/gcg/` to replay a run with `scripts/replay_run.py`.
