#!/bin/bash
# Full ACT (2,578 ELFs, the set in ~/act8/act-elfs copied from
# sigil-fpga-build:~/oops/fixgates/act-elfs) on ~/wt/8-final, core_tb
# default config, 12 jobs; per-ELF comparison with main 9da0006's run
# on the same ELFs and machine (~/act8/logs/main/act.csv).
W=~/wt/8-final; E=~/act8/act-elfs/elfs; L=~/dvfix-scratch/final/act; mkdir -p $L
cd $W; source deps/env.sh >/dev/null
FP=$(cd ~/act8/act-elfs && find elfs -name '*.elf' | sort | xargs sha256sum | sha256sum | cut -c1-64)
N=$(find $E -name '*.elf' | wc -l)
make -s -C sim ../build/sim/core_tb VJOBS=8 > $L/build.log 2>&1; echo "build rc=$?" >> $L/build.log
{ echo "host $(hostname) $(nproc) vCPU; $(verilator --version)"
  echo "start $(date -u +%FT%TZ) head $(git rev-parse HEAD) dirty=[$(git status --porcelain | wc -l)] core_tb $(md5sum < build/sim/core_tb | cut -c1-32) elfs $N elfs-fingerprint $FP jobs 12"; } > $L/summary.txt
[ "$FP" = 839ba8be12d65bc82e64cfce1dd157f38d3e2c7f41c9bdd9fd64249d2515ae7f ] || echo "ELF FINGERPRINT MISMATCH" >> $L/summary.txt
t0=$(date +%s)
sim/run_act_core_par.sh build/sim/core_tb $L/act.csv $E 12 > $L/act.log 2>&1; rc=$?
{ echo "Vx: $(grep -c '^Vx[0-9]*-.*,PASS,' $L/act.csv)/$(grep -c '^Vx[0-9]*-' $L/act.csv)"
  echo "Vls: $(grep -c '^Vls[0-9]*-.*,PASS,' $L/act.csv)/$(grep -c '^Vls[0-9]*-' $L/act.csv)"
  echo "Vf: $(grep -c '^Vf[0-9]*-.*,PASS,' $L/act.csv)/$(grep -c '^Vf[0-9]*-' $L/act.csv)"; } >> $L/act.log
echo "act rc=$rc $(( $(date +%s)-t0 ))s end $(date -u +%FT%TZ)" >> $L/summary.txt
echo ACT_DONE >> $L/summary.txt
