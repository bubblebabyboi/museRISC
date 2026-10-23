#!/bin/bash
# rtlrun.sh <bench-variant> <bench> <out> <regions> <cfg...>: trace the RTL SoC run (default config)
# into the analyzer, once per timing configuration (the stream is captured once to a file).
cd ~/fe-trace
B=~/wt/56-perf-harness/build/perf/baseline-56/default/bin/$1
TB=~/fe-trace/src/build/sim/soc_rtl_tb
tr=~/fe-trace/rtltrace.$1.log
$TB 200000000 --mem-lat 1:1 --mem-gap 0 --mem-ready 100 --load 0x80000000=$B/$2.bin \
  --exit-string "SIGIL TEST PASS $2" --fail-string 'SIGIL TEST FAIL' +fetrace=$tr +sigil_perf=$3.perf > $3.uart 2>&1
for c in ${@:5}; do ./fe $B/$2.elf "$4" $c < $tr > $3.$c 2> $3.$c.err; done
gzip -f $tr
