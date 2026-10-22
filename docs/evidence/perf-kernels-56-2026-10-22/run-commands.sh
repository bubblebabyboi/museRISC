#!/bin/bash
cd ~/wt/56-perf-kernels
source deps/env.sh
rm -rf build/perf/kernels-default build/kernels-faults build/kernels-shift2
make -C sim perf BENCHES=kernels CONFIG=default MEM="soc axi" REPEAT=2 JOBS=8 VJOBS=12 \
  PERF_OUT=$HOME/wt/56-perf-kernels/build/perf/kernels-default > build/logs/perf-default.log 2>&1 &
# Code-placement experiment: every C kernel shifted by one 2-byte c.nop.
S=build/kernels-shift2; mkdir -p $S
for v in scalar shift2; do
  extra=""; [ $v = shift2 ] && extra="KERNELS_C_EXTRA=-fpatchable-function-entry=1"
  make -C sw/bench/kernels OUT=$HOME/wt/56-perf-kernels/$S/$v $extra > $S/build-$v.log 2>&1
done
for v in scalar shift2; do
  build/sim/soc_rtl_tb 200000000 --mem-lat 1:1 --mem-gap 0 --mem-ready 100 --load 0x80000000=$S/$v/kernels.bin \
    --exit-string "SIGIL TEST PASS kernels" --fail-string "SIGIL TEST FAIL" +sigil_perf=$HOME/wt/56-perf-kernels/$S/$v.perf > $S/$v.log 2>&1 &
done
wait
echo ALLDONE > build/logs/launch.done
