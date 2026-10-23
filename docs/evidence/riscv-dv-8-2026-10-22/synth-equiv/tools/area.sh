#!/usr/bin/env bash
# area.sh <eq/SYNTHESIS dir> <outdir>: generic-gate Yosys synthesis
# (synth -flatten; abc -g AND,NAND,OR,NOR,XOR,XNOR,MUX; stat) of sigil_csr
# (main, branch) and of sigil_core's own logic with its children as port-only
# blackboxes (main, branch, neutral), from the sv2v units of the equivalence
# runs (SYNTHESIS define set). Technology-independent cell counts: an
# indication of size, not an ORFS/Vivado result.
set -uo pipefail
E=$1; O=$2; mkdir -p "$O"
cp "$E/csr_free/gold_core.v" "$O/csr_main.v"; cp "$E/csr_free/gate_core.v" "$O/csr_br.v"
cp "$E/core_neutral/kids.v" "$O/kids_main.v"; cp "$E/core_full/kids.v" "$O/kids_br.v"
cp "$E/core_full/gold_core.v" "$O/core_main.v"; cp "$E/core_full/gate_core.v" "$O/core_br.v"
cp "$E/core_neutral/gate_core.v" "$O/core_neutral.v"
run() { (cd "$O" && yosys -l $1.log -p "read_verilog $2; synth -flatten -top $3; abc -g AND,NAND,OR,NOR,XOR,XNOR,MUX; opt_clean; stat" > /dev/null 2>&1) ; }
run csr_main csr_main.v sigil_csr & run csr_br csr_br.v sigil_csr &
run core_main "kids_main.v core_main.v" sigil_core & run core_br "kids_br.v core_br.v" sigil_core &
run core_neutral "kids_main.v core_neutral.v" sigil_core &
wait
for f in csr_main csr_br core_main core_neutral core_br; do
  awk '/Printing statistics/{b=""} {b=b"\n"$0} END{print b}' "$O/$f.log" > "$O/$f.stat"
  c=$(grep -E '^ +[0-9]+ cells$' "$O/$f.stat" | awk '{print $1}')
  ff=$(grep -E '\$_(S?DFFE?|ALDFF|DLATCH)[A-Z0-9_]*_ *$' "$O/$f.stat" | awk '{s+=$1} END {print s}')
  printf '%-13s %6s cells, %5s flip-flops\n' "$f" "$c" "$ff"
done
echo "($(yosys -V | cut -d' ' -f1-2), $(sv2v --version))"
