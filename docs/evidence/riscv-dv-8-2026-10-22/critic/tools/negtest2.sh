#!/bin/bash
# negtest2.sh <rdv_trace.py>: feed the comparator corrupted copies of matching
# DUT traces; every corruption must be a MISMATCH (rc 1), unmodified a MATCH.
source ~/wt/8-riscv-dv/deps/env.sh
T=$1
W=$(mktemp -d ~/rdvcrit/negtest.XXXX)
run() { # name dir trace
  local e; e=$(ls $2/*.elf); local out
  out=$(python3 $T --elf $e --spike $2/spike.log --dut $3); local rc=$?
  printf '%-34s rc=%d %s\n' "$1" $rc "$(echo "$out" | cut -c1-230)"
}
Q=~/wt/8-riscv-dv/build/riscv-dv/quick4
A=$Q/riscv_amo_test/21; E=$Q/riscv_ebreak_test/21; F=$Q/riscv_floating_point_rand_test/21
V=~/rdvcrit/run-v3/sigil_vector_test/1
run "unmodified (amo)" $A $A/dut.trace
L=$(grep -n " x[0-9]*=" $A/dut.trace | sed -n 200p | cut -d: -f1)
sed "${L}s/ x\([0-9]*\)=\([0-9a-f]*\)\([0-9a-f]\)/ x\1=\2X\3/; ${L}s/X0/1/; ${L}s/X\([1-9a-f]\)/0/" $A/dut.trace > $W/x.trace
run "x write value" $A $W/x.trace
sed "300d" $A/dut.trace > $W/drop.trace;                       run "dropped record" $A $W/drop.trace
L=$(grep -n " m[0-9a-f]*:" $A/dut.trace | sed -n 5p | cut -d: -f1)
sed "${L}s/=\([0-9a-f]*\)\$/=\1f/" $A/dut.trace > $W/st.trace;  run "store data" $A $W/st.trace
L=$(grep -n "^I" $A/dut.trace | sed -n 400p | cut -d: -f1)
sed "${L}s/^I \([0-9]*\) \([0-9]\) /I \1 0 /" $A/dut.trace > $W/priv.trace; run "privilege" $A $W/priv.trace
L=$(grep -n " c300=" $A/dut.trace | head -1 | cut -d: -f1)
sed "${L}s/ c300=[0-9a-f]*/ c300=0000000000000000/" $A/dut.trace > $W/csr.trace; run "mstatus write value" $A $W/csr.trace
L=$(grep -n "^E" $E/dut.trace | head -1 | cut -d: -f1)
sed "${L}s/ 0000000000000003 / 0000000000000002 /" $E/dut.trace > $W/trap.trace; run "trap cause (ebreak)" $E $W/trap.trace
run "unmodified (fp)" $F $F/dut.trace
L=$(grep -n " f[0-9]*=" $F/dut.trace | sed -n 20p | cut -d: -f1)
sed "${L}s/ f\([0-9]*\)=\([0-9a-f]*\)/ f\1=ffffffffffffffff/" $F/dut.trace > $W/f.trace; run "f write value" $F $W/f.trace
L=$(grep -n " c001=" $F/dut.trace | head -1 | cut -d: -f1)
sed "${L}s/ c001=[0-9a-f]*//" $F/dut.trace > $W/ff.trace; run "missing fflags update" $F $W/ff.trace
run "unmodified (random vector)" $V $V/dut.trace
L=$(grep -n " v[0-9]*=" $V/dut.trace | sed -n 300p | cut -d: -f1)
sed -E "${L}{s/ (v[0-9]+)=0/ \1=1/;t;s/ (v[0-9]+)=[1-9a-f]/ \1=0/}" $V/dut.trace > $W/v.trace; run "vector register value" $V $W/v.trace
# Drop the first logged vector register of a line whose instruction changed it
# (a vadd.vv-class write in the first iteration): one-sided ref write.
L=$(grep -n " v16=" $V/dut.trace | sed -n 40p | cut -d: -f1)
sed -E "${L}s/ v16=[0-9a-f]+//" $V/dut.trace > $W/vdrop.trace; run "dropped vector write (v16)" $V $W/vdrop.trace
rm -rf $W
