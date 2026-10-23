#!/bin/bash
cd ~/fe-trace
E=~/wt/56-perf-harness/build/perf/baseline-56/default/bin
mkdir -p out4
run() { ./run3.sh "$E/$1" "out4/$2" "$3" "$4"; }
rtl() { zcat rtltrace.$1.log.gz | ./fe3 $E/$1/$2.elf "$3" $4 > out4/$5.$4 2> out4/$5.$4.err; }
run coremark-scalar/coremark.elf cm_scalar.default all default &
run coremark-scalar/coremark.elf cm_scalar.sky130 all sky130 &
run dhrystone-scalar/dhrystone.elf dhry_scalar.default all default &
run dhrystone-scalar/dhrystone.elf dhry_scalar.sky130 all sky130 &
run dhrystone-sdk/dhrystone.elf dhry_sdk.default all default &
run dhrystone-sdk/dhrystone.elf dhry_sdk.sky130 all sky130 &
rtl sha256chain-sdk sha256chain 0,1 default sha &
rtl sha256chain-sdk sha256chain 0,1 sky130 sha &
run coremark-sdk/coremark.elf cm_sdk.default all default &
run micro_pipe-default/micro_pipe.elf micro_pipe.default all default &
run kernels-scalar/kernels.elf kernels_scalar.default 10,20,30,40,50,60,70,80,90,100,110,120,130 default &
wait
echo DONE
