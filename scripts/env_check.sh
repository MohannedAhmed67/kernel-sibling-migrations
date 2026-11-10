#!/usr/bin/env bash
# Phase 0 environment check. Prints facts only; every line is measured, nothing is assumed.
set -uo pipefail
LINUX="${LINUX:-/linux/linux}"
missing=()

section() { printf '\n== %s ==\n' "$1"; }
ver() {  # ver <label> <command...>
  local label="$1"; shift
  if out="$("$@" 2>&1 | head -1)"; then printf '%-12s %s\n' "$label" "$out"
  else printf '%-12s MISSING\n' "$label"; missing+=("$label"); fi
}

section "Platform"
echo "date (UTC)   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
. /etc/os-release && echo "os           $PRETTY_NAME"
echo "kernel       $(uname -srm)"
echo "cpus         $(nproc)"
echo "memory       $(free -h | awk '/^Mem:/{print $2}')"

section "Toolchain"
ver git     git --version
ver gcc     gcc --version
ver make    make --version
ver flex    flex --version
ver bison   bison --version
ver bc      dpkg-query -W -f='bc ${Version}' bc
ver python3 python3 --version
ver matplotlib python3 -c 'import matplotlib; print("matplotlib", matplotlib.__version__)'
ver spatch  spatch --version
for pkg in libelf-dev libssl-dev; do
  ver "$pkg" dpkg-query -W -f='${Package} ${Version}' "$pkg"
done

section "Kernel tree ($LINUX)"
if [ -d "$LINUX/.git" ]; then
  echo "partial clone filter: $(git -C "$LINUX" config remote.origin.partialclonefilter || echo none)"
  echo "HEAD:        $(git -C "$LINUX" log -1 --format='%h %cd %s' --date=short)"
  for t in v5.10 v6.10; do
    if git -C "$LINUX" rev-parse -q --verify "refs/tags/$t" >/dev/null; then
      echo "tag $t:     $(git -C "$LINUX" log -1 --format='%h %cd' --date=short "$t")"
    else echo "tag $t:     MISSING"; missing+=("tag-$t"); fi
  done
  echo "commits v5.10..v6.10: $(git -C "$LINUX" rev-list --count v5.10..v6.10 2>/dev/null || echo n/a)"
  echo ".git size:   $(du -sh "$LINUX/.git" | cut -f1)"
  echo "tree size:   $(du -sh --exclude=.git "$LINUX" | cut -f1)"
  # Case-sensitivity check on the actual storage holding the tree.
  probe="$(dirname "$LINUX")/.case_probe_$$"; mkdir -p "$probe"
  touch "$probe/A" "$probe/a"
  n=$(ls "$probe" | wc -l); rm -rf "$probe"
  if [ "$n" -eq 2 ]; then echo "case-sensitive: yes"; else echo "case-sensitive: NO"; missing+=("case-sensitive-fs"); fi
  # Same check against real kernel files that differ only by case.
  if [ -f "$LINUX/net/netfilter/xt_TCPMSS.c" ] && [ -f "$LINUX/net/netfilter/xt_tcpmss.c" ]; then
    echo "xt_TCPMSS.c and xt_tcpmss.c both present: yes"
  else echo "xt_TCPMSS.c / xt_tcpmss.c: not both present"; fi
else
  echo "not cloned yet (run: make clone)"; missing+=("linux-clone")
fi
echo "free disk on $(dirname "$LINUX"): $(df -h "$(dirname "$LINUX")" | awk 'NR==2{print $4}')"

section "Summary"
if [ ${#missing[@]} -eq 0 ]; then echo "READY: nothing missing"
else echo "MISSING: ${missing[*]}"; fi
