#!/usr/bin/env bash
# equiv_csr.sh <defines> <gold rtl> <gate rtl> <outdir> <tie|free>
# sv2v both trees, take sigil_csr from each, Yosys equiv_make / equiv_simple /
# equiv_induct gold vs gate; unproven $equiv cells are listed. The gate's
# pmp_wide_b_i / pmp_wide_c_i inputs (8-byte PMP check, branch only):
#   tie   become internal wires driven 0 (every access checked as one
#         4-byte word, the old behaviour);
#   free  stay inputs, and the gold gets the same two (unused) inputs, so both
#         sides see the same unconstrained values.
set -uo pipefail
defs=$1; G=$2; T=$3; O=$4; mode=$5; mkdir -p "$O"
here=$(cd "$(dirname "$0")" && pwd)
DD=(); for d in $defs; do DD+=("-D$d"); done
for side in gold gate; do
  root=$G; [ $side = gate ] && root=$T
  (cd "$root" && sv2v "${DD[@]}" -Icore $(ls core/*.sv)) > "$O/$side.all.v" || exit 2
  python3 "$here/split_units.py" "$O/$side.all.v" "$O/$side.units" > "$O/$side.hash"
done
cp "$O/gold.units/sigil_csr.sv" "$O/gold_core.v"; cp "$O/gate.units/sigil_csr.sv" "$O/gate_core.v"
if [ "$mode" = tie ]; then
  pre="delete -port gate/w:pmp_wide_b_i gate/w:pmp_wide_c_i"
  post="cd gate
connect -set pmp_wide_b_i 1'b0
connect -set pmp_wide_c_i 1'b0
cd .."
else
  pre="cd gold
add -input pmp_wide_b_i 1
add -input pmp_wide_c_i 1
cd .."
  post=""
fi
cat > "$O/eq.ys" <<EOT
read_verilog gold_core.v
rename sigil_csr gold
read_verilog gate_core.v
rename sigil_csr gate
$pre
hierarchy -check
proc
$post
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
echo "defines=[$defs] module=sigil_csr gold=$(basename "$(dirname "$G")") gate=$(basename "$(dirname "$T")") mode=$mode"
grep -E 'Found [0-9]+ .equiv cells in|Of those|ERROR' "$O/eq.log" | tail -3
python3 "$here/name_unproven.py" "$O"
echo "yosys rc=$rc $(( $(date +%s)-t0 ))s ($(yosys -V | cut -d' ' -f1-2), $(sv2v --version))"
