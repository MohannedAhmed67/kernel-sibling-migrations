#!/usr/bin/env bash
# Ablation grid for guided rule generation (run inside the dev container; Ollama on the host).
# For each model (one at a time, the script unloads it when done) and seed, runs stage 2 for six configurations,
# then stage 3 (composition) for every configuration and stage 4 (compile critic) for the full framework.
#   whole_u_r0     one rule for the whole migration, plain prompt, no feedback        (baseline)
#   whole_u_r3     + spatch/test feedback, 3 rounds
#   leaf_u_r3      + decomposition into leaves (variant tree), unguided prompts
#   leaf_gnofix_r3 + guidance: minimal-edit patterns, context, interface, error hints, lint, stall handling
#   leaf_g_r3      + deterministic auto-repair
#   leaf_gc_r3     + generality critic (stage 2) and compile critic with repair (stage 4)  = full framework
# Usage: MODELS="qwen2.5-coder:7b" SEEDS="1 2 3" MIGS="..." bash scripts/gcg_ablate.sh
set -uo pipefail
MODELS="${MODELS:-qwen2.5-coder:7b llama3.1:8b gemma3:4b}"
SEEDS="${SEEDS:-1 2 3}"
MIGS="${MIGS:-ida_simple i2c_probe_new platform_remove_new strlcpy_strscpy pci_dma_wrappers}"
declare -A CFG=(
  [whole_u_r0]="--mode whole --unguided --rounds 0"
  [whole_u_r3]="--mode whole --unguided --rounds 3"
  [leaf_u_r3]="--mode leaf --unguided --rounds 3"
  [leaf_gnofix_r3]="--mode leaf --no-autofix --rounds 3"
  [leaf_g_r3]="--mode leaf --rounds 3"
  [leaf_gc_r3]="--mode leaf --critic --rounds 3"
)
ORDER="whole_u_r0 whole_u_r3 leaf_u_r3 leaf_gnofix_r3 leaf_g_r3 leaf_gc_r3"
for model in $MODELS; do
  mdir="${model//:/_}"
  for seed in $SEEDS; do
    for c in $ORDER; do
      run="work/gcg/runs/$mdir/${c}_s$seed"
      if [ -f "$run/DONE" ] && [ "$(cat "$run/DONE")" = "$MIGS" ]; then echo "skip $run"; continue; fi
      echo "=== $model $c seed $seed  $(date -u +%FT%TZ)"
      rm -rf "$run"
      python3 scripts/gcg_leaf.py --model "$model" --seed "$seed" ${CFG[$c]} --migration $MIGS > "work/gcg/logs_${mdir}_${c}_s$seed.txt" 2>&1 \
        && echo "$MIGS" > "$run/DONE" || echo "FAILED $run (see work/gcg/logs_${mdir}_${c}_s$seed.txt)"
    done
    for c in $ORDER; do python3 scripts/gcg_compose.py --config "${c}_s$seed" > /dev/null || echo "compose failed ${c}_s$seed"; done
    python3 scripts/gcg_critic.py --model "$model" --config "leaf_gc_r3_s$seed" --migration $MIGS \
      > "work/gcg/logs_${mdir}_critic_s$seed.txt" 2>&1 || echo "critic failed $model seed $seed"
    grep "final=" "work/gcg/logs_${mdir}_critic_s$seed.txt"
  done
done
python3 scripts/gcg_report.py > /dev/null
echo "ALL DONE $(date -u +%FT%TZ)"
