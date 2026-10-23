#!/usr/bin/env bash
# equiv_core.sh <defines> <gold rtl> <gate rtl> <outdir>
# sv2v both trees with the defines, take sigil_core from each, read every
# child module of sigil_core as a port-only blackbox, and run Yosys
# equiv_make / equiv_simple / equiv_induct gold vs gate. equiv_make merges
# the instances of the same blackbox with the same name; their inputs become
# $equiv points, so the proof covers sigil_core's own logic and every signal
# it hands to a child module. Unproven $equiv cells are listed.
#   KIDS_FROM=gate  take the stubs from the gate tree (default: gold)
#   GOLD_TIE="<cell> <port> <value>;..."  connect gold-only-missing cell ports
set -uo pipefail
defs=$1; G=$2; T=$3; O=$4; mkdir -p "$O"
here=$(cd "$(dirname "$0")" && pwd)
DD=(); for d in $defs; do DD+=("-D$d"); done
for side in gold gate; do
  root=$G; [ $side = gate ] && root=$T
  (cd "$root" && sv2v "${DD[@]}" -Icore $(ls core/*.sv)) > "$O/$side.all.v" || exit 2
  python3 "$here/split_units.py" "$O/$side.all.v" "$O/$side.units" > "$O/$side.hash"
done
kids=$(grep -oE '^\s*sigil_\w+ (#\(.*\) )?u_\w+\(' "$O/gold.units/sigil_core.sv" | awk '{print $1}' | sort -u)
python3 "$here/bb_stub.py" $(for k in $kids; do echo "$O/${KIDS_FROM:-gold}.units/$k.sv"; done) > "$O/kids.v" || exit 2
tie=""
if [ -n "${GOLD_TIE:-}" ]; then
  tie="cd gold"; IFS=';' read -ra TT <<< "$GOLD_TIE"
  for x in "${TT[@]}"; do tie="$tie
connect -port $x"; done; tie="$tie
cd .."
fi
cp "$O/gold.units/sigil_core.sv" "$O/gold_core.v"; cp "$O/gate.units/sigil_core.sv" "$O/gate_core.v"
cat > "$O/eq.ys" <<EOT
read_verilog kids.v
read_verilog gold_core.v
rename sigil_core gold
read_verilog gate_core.v
rename sigil_core gate
hierarchy -check
proc
$tie
memory -nomap; memory_map
opt_clean
async2sync
equiv_make gold gate equiv
hierarchy -top equiv
equiv_simple -seq 2
equiv_induct -seq 2 -ignore-unknown-cells
equiv_status
EOT
t0=$(date +%s)
(cd "$O" && yosys -l eq.log eq.ys > /dev/null 2>&1); rc=$?
echo "defines=[$defs] gold=$(basename "$(dirname "$G")") gate=$(basename "$(dirname "$T")") stubs=${KIDS_FROM:-gold} tie=[${GOLD_TIE:-}]"
echo "blackboxed children (merged): $(grep -c 'Presumably equivalent cells' "$O/eq.log") of $(echo $kids | wc -w | tr -d ' '): $(echo $kids | tr '\n' ' ')"
grep -E 'Found [0-9]+ .equiv cells in|Of those|ERROR' "$O/eq.log" | tail -3
grep -E '^ *Unproven' "$O/eq.log" > "$O/unproven.txt"
echo "unproven: $(wc -l < "$O/unproven.txt" | tr -d ' ')"
python3 "$here/name_unproven.py" "$O"
echo "yosys rc=$rc $(( $(date +%s)-t0 ))s ($(yosys -V | cut -d' ' -f1-2), $(sv2v --version))"
