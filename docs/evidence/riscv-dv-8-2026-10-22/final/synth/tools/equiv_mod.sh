#!/usr/bin/env bash
# equiv_mod.sh <defines> <module> <gold rtl> <gate rtl> <outdir>
# sv2v both trees with the defines, take <module> (no child instances) from
# each, Yosys equiv_make / equiv_simple / equiv_induct gold vs gate; unproven
# $equiv cells are listed (as equiv_csr.sh, without port changes).
set -uo pipefail
defs=$1; M=$2; G=$3; T=$4; O=$5; mkdir -p "$O"
here=$(cd "$(dirname "$0")" && pwd)
DD=(); for d in $defs; do DD+=("-D$d"); done
for side in gold gate; do
  root=$G; [ $side = gate ] && root=$T
  (cd "$root" && sv2v "${DD[@]}" -Icore $(ls core/*.sv)) > "$O/$side.all.v" || exit 2
  python3 "$here/split_units.py" "$O/$side.all.v" "$O/$side.units" > "$O/$side.hash"
done
cp "$O/gold.units/$M.sv" "$O/gold_core.v"; cp "$O/gate.units/$M.sv" "$O/gate_core.v"
cat > "$O/eq.ys" <<EOT
read_verilog gold_core.v
rename $M gold
read_verilog gate_core.v
rename $M gate
hierarchy -check
proc
memory -nomap; memory_map
opt_clean
async2sync
equiv_make gold gate equiv
hierarchy -top equiv
equiv_simple -seq 2
equiv_induct -seq 2
equiv_status
EOT
t0=$(date +%s)
(cd "$O" && yosys -l eq.log eq.ys > /dev/null 2>&1); rc=$?
echo "defines=[$defs] module=$M gold=$(basename "$(dirname "$G")") gate=$(basename "$(dirname "$T")")"
grep -E 'Found [0-9]+ .equiv cells in|Of those|ERROR' "$O/eq.log" | tail -3
python3 "$here/name_unproven.py" "$O"
echo "yosys rc=$rc $(( $(date +%s)-t0 ))s ($(yosys -V | cut -d' ' -f1-2), $(sv2v --version))"
