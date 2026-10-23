#!/usr/bin/env bash
# area2.sh <eq/SYNTHESIS dir> <outdir>: generic-gate Yosys synthesis
# (synth -flatten; abc -g AND,NAND,OR,NOR,XOR,XNOR,MUX; stat) of sigil_core's
# own logic (children as port-only blackboxes) and of sigil_vec, before
# (f239397) and after (1eac727) the review-round fixes, from the sv2v units of
# the equivalence runs (SYNTHESIS define set). Technology-independent cell
# counts: an indication of size, not an ORFS/Vivado result.
set -uo pipefail
E=$1; O=$2; mkdir -p "$O"
cp "$E/core_full/kids.v" "$O/kids.v"
cp "$E/core_full/gold_core.v" "$O/core_old.v"; cp "$E/core_full/gate_core.v" "$O/core_new.v"
cp "$E/vec_full/gold_core.v" "$O/vec_old.v"; cp "$E/vec_full/gate_core.v" "$O/vec_new.v"
run() { (cd "$O" && yosys -l $1.log -p "read_verilog $2; synth -flatten -top $3; abc -g AND,NAND,OR,NOR,XOR,XNOR,MUX; opt_clean; stat" > /dev/null 2>&1) ; }
run core_old "kids.v core_old.v" sigil_core & run core_new "kids.v core_new.v" sigil_core &
run vec_old vec_old.v sigil_vec & run vec_new vec_new.v sigil_vec &
wait
for f in core_old core_new vec_old vec_new; do
  awk '/Printing statistics/{b=""} {b=b"\n"$0} END{print b}' "$O/$f.log" > "$O/$f.stat"
  c=$(grep -E '^ +[0-9]+ cells$' "$O/$f.stat" | awk '{print $1}')
  ff=$(grep -E '\$_(S?DFFE?|ALDFF|DLATCH)[A-Z0-9_]*_ *$' "$O/$f.stat" | awk '{s+=$1} END {print s}')
  printf '%-9s %6s cells, %5s flip-flops\n' "$f" "$c" "$ff"
done
echo "($(yosys -V | cut -d' ' -f1-2), $(sv2v --version))"
