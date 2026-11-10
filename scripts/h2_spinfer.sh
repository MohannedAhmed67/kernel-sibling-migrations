#!/usr/bin/env bash
# H2: infer one Coccinelle rule per migration with Spinfer, from the SAME 20 training sibling pairs the manual
# rule author saw (work/h2/<migration>/train/NN/{before,after}.c). Runs on the host; needs Docker and the
# image built from docker/spinfer.Dockerfile:  docker build -f docker/spinfer.Dockerfile -t drivebench-spinfer:c47696a docker
set -uo pipefail
IMAGE="${SPINFER_IMAGE:-drivebench-spinfer:c47696a}"
TIMEOUT="${SPINFER_TIMEOUT:-7200}"
mkdir -p rules/spinfer results
: > results/h2_spinfer_runs.txt
# record the toolchain inside the Spinfer image
{ echo "image: $IMAGE"
  MSYS_NO_PATHCONV=1 docker run --rm --entrypoint sh "$IMAGE" -c \
    'echo "os: $(. /etc/os-release; echo $PRETTY_NAME)"; echo "ocaml: $(ocaml -version)"; echo "python3: $(python3 --version)";
     echo "sklearn: $(python3 -c "import sklearn; print(sklearn.__version__)" 2>/dev/null)";
     cd /usr/src/spinfer && echo "spinfer commit: $(git rev-parse HEAD)" && echo "coccinelle submodule: $(git -C coccinelle rev-parse HEAD) ($(git -C coccinelle log -1 --format=%ci))"'
} > results/h2_spinfer_toolchain.txt
run_one() {
  d="$1"; mig=$(basename "$(dirname "$d")")
  (cd "$d" && for x in */; do echo "${x%/}/before.c ${x%/}/after.c"; done > index)
  start=$(date +%s)
  MSYS_NO_PATHCONV=1 timeout "$TIMEOUT" docker run --rm -v "$(pwd)/$d:/data" "$IMAGE" -f index -o spinfer.cocci \
    > "work/h2/$mig/spinfer.log" 2>&1
  rc=$?
  secs=$(( $(date +%s) - start ))
  if [ -s "$d/spinfer.cocci" ]; then mv "$d/spinfer.cocci" "rules/spinfer/$mig.cocci"; status=rule; else status=no_rule; fi
  echo "$mig rc=$rc seconds=$secs $status" | tee -a results/h2_spinfer_runs.txt
}
for d in work/h2/*/train; do run_one "$d" & done   # one container per migration, in parallel
wait
