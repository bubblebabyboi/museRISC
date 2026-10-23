#!/usr/bin/env bash
# unit_diff.sh <rtl-A> <rtl-B> <outdir>: preprocess both trees with each
# synthesis flow's defines (the define sets of scripts/synth_view_diff.sh),
# split into design units, and list every unit whose preprocessed text differs.
set -euo pipefail
A=$1; B=$2; O=$3; mkdir -p "$O"
here=$(cd "$(dirname "$0")" && pwd)
verilator --version
for defs in "SYNTHESIS" "SYNTHESIS SIGIL_SRAM_FAKERAM45" "SYNTHESIS SIGIL_SRAM_SKY130" \
            "SYNTHESIS SIGIL_SRAM_OREG" "SYNTHESIS SIGIL_VRF_OREG" ""; do
  tag=$(echo "${defs:-SIM}" | tr ' ' '+'); D=(); for d in $defs; do D+=("+define+$d"); done
  for side in A B; do
    root=$A; [ $side = B ] && root=$B
    (cd "$root" && verilator -E -P ${D[@]+"${D[@]}"} -Icore $(ls core/*.sv crypto/*.sv soc/*.sv fpga/*.sv)) > "$O/$tag.$side.pp"
    python3 "$here/split_units.py" "$O/$tag.$side.pp" "$O/$tag.$side.units" > "$O/$tag.$side.hash"
  done
  n=$(wc -l < "$O/$tag.A.hash" | tr -d ' ')
  diffs=$(join -a1 -a2 -e MISSING -o 0,1.2,2.2 "$O/$tag.A.hash" "$O/$tag.B.hash" | awk '$2!=$3{print $1}' | tr '\n' ' ')
  echo "defines=[${defs:-none, simulation view}] units=$n differing: ${diffs:-none}"
  diff -u "$O/$tag.A.pp" "$O/$tag.B.pp" > "$O/$tag.diff" || true
done
