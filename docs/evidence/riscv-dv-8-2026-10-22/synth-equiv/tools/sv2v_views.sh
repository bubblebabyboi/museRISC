#!/usr/bin/env bash
# sv2v_views.sh <rtl-A> <rtl-B> <outdir>: convert each tree to Verilog-2005 with
# sv2v under each synthesis define set, split per module, list differing modules.
set -euo pipefail
A=$1; B=$2; O=$3; mkdir -p "$O"; here=$(cd "$(dirname "$0")" && pwd)
sv2v --version
for defs in "SYNTHESIS" "SYNTHESIS SIGIL_SRAM_FAKERAM45" "SYNTHESIS SIGIL_SRAM_SKY130" \
            "SYNTHESIS SIGIL_SRAM_OREG" "SYNTHESIS SIGIL_VRF_OREG"; do
  tag=$(echo "$defs" | tr ' ' '+'); D=(); for d in $defs; do D+=("-D$d"); done
  for side in A B; do
    root=$A; [ $side = B ] && root=$B
    (cd "$root" && sv2v "${D[@]}" -Icore $(ls core/*.sv crypto/*.sv soc/*.sv fpga/*.sv)) > "$O/$tag.$side.v"
    python3 "$here/split_units.py" "$O/$tag.$side.v" "$O/$tag.$side.units" > "$O/$tag.$side.hash"
  done
  n=$(wc -l < "$O/$tag.B.hash" | tr -d ' ')
  diffs=$(join -a1 -a2 -e MISSING -o 0,1.2,2.2 "$O/$tag.A.hash" "$O/$tag.B.hash" | awk '$2!=$3{print $1}' | tr '\n' ' ')
  echo "defines=[$defs] modules=$n differing: ${diffs:-none}"
done
