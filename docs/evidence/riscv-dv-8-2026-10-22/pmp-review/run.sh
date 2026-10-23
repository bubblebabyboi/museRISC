#!/bin/bash
# Reproduces the PMP equivalence proofs and synthesis numbers in
# pmp-review.txt (sv2v, Yosys 0.69; run in a scratch copy of this
# directory). FORM: 0 main serial, 1 3ae351d serial, 2 #53 parallel,
# 3 proposed #53 parallel with 3ae351d. WIDE: 0 tied low (fetch port A),
# 1 tied high (walker port C), 2 input (data port B).
set -e
sv2v pmp_forms.sv > pmp_forms.v
# sv2v spells the final always_comb with a sensitivity list naming the
# unpacked arrays, which Yosys rejects.
sed -i.bak -E 's/^	always @\(wide or .*\) begin$/	always @(*) begin/' pmp_forms.v
eq() {  # FA FB WA WB: prove the forms agree (wide only with addr[2] = 0)
  if yosys -q -p "read_verilog pmp_forms.v miter.v; chparam -set FA $1 -set FB $2 -set WA $3 -set WB $4 miter; hierarchy -top miter; proc; flatten; memory; opt; sat -prove ok 1 -verify -set-def-inputs" > eq_$1_$2_$3_$4.log 2>&1
  then echo "FORM $1 (wide $3) == FORM $2 (wide $4): PROVEN"
  else echo "FORM $1 (wide $3) == FORM $2 (wide $4): DIFFER (counterexample in eq_$1_$2_$3_$4.log)"; fi
}
syn() {  # FORM WIDE: generic gates (count, depth) and UltraScale+ LUTs
  T=f$1_w$2
  yosys -q -p "read_verilog pmp_forms.v; chparam -set FORM $1 -set WIDE $2 pmp_forms; synth -flatten -top pmp_forms; abc -g AND,NAND,OR,NOR,XOR,XNOR,MUX; opt_clean; tee -o $T.gates.stat stat; tee -o $T.gates.ltp ltp -noff" > /dev/null 2>&1
  yosys -q -p "read_verilog pmp_forms.v; chparam -set FORM $1 -set WIDE $2 pmp_forms; synth_xilinx -family xcup -flatten -noiopad -top pmp_forms; tee -o $T.xil.stat stat; tee -o $T.xil.ltp ltp -noff" > /dev/null 2>&1
  echo "FORM=$1 WIDE=$2 gates=$(grep -m1 -E '^ +[0-9]+ +cells' $T.gates.stat | awk '{print $1}')" \
       "gate_depth=$(grep -o 'length=[0-9]*' $T.gates.ltp | head -1 | cut -d= -f2)" \
       "luts=$(grep -E 'LUT[1-6]' $T.xil.stat | awk '{s+=$1} END {print s}')" \
       "carry=$(grep -E 'CARRY' $T.xil.stat | awk '{s+=$1} END {print s+0}')" \
       "lut_path_cells=$(grep -o 'length=[0-9]*' $T.xil.ltp | head -1 | cut -d= -f2)"
}
eq 0 2 2 2; eq 0 1 2 0; eq 1 3 2 2; eq 0 1 2 2; eq 2 3 2 2
for a in "0 2" "1 0" "1 2" "1 1" "2 2" "3 0" "3 2" "3 1"; do syn $a; done
