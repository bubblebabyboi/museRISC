#!/bin/bash
# Quick check of the new/affected directed tests on ~/wt/8-final:
# Spike (-DSPIKE_HTIF) for the self-checking ones, then core_tb with a
# random bus and uncached.
set +e
W=${W:-$HOME/wt/8-final}
source $W/deps/env.sh >/dev/null
OUT=$HOME/dvfix-scratch/final; mkdir -p $OUT; cd $OUT
SPIKE="$HOME/opt/spike/bin/spike --isa=rv64imafdcbvh_zicsr_zifencei_zicntr_zbc_zbkb_zbkc_zbkx_zkne_zknd_zknh_zicond_zcb_zvl512b_svnapot_svadu --priv=msu --pmpregions=16 --pmpgranularity=4"
LD=$HOME/wt/8-riscv-dv/third_party/riscv-dv/scripts/link.ld
for T in ${SPIKE_TESTS:-vstart_illegal_directed vfcvt_sew16_directed fpvec_nanbox_directed pmp_whole64_directed}; do
  riscv64-unknown-elf-gcc -march=rv64gcv -mabi=lp64 -nostdlib -static -DSPIKE_HTIF -T $LD $W/sw/core-tests/$T.S -o $T.spike.elf 2>&1 | head -5
  echo "== spike $T"; timeout 300 $SPIKE $T.spike.elf; echo "spike $T rc=$?"
done
make -s -C $W/sim ../build/sim/core_tb > build_tb.log 2>&1 || { echo "core_tb build failed"; tail -20 build_tb.log; exit 1; }
for T in ${CORE_TESTS:-vstart_illegal_directed vfcvt_sew16_directed viota_vstart_directed viota_overlap_directed viota_directed viota_cases_directed fpvec_nanbox_directed pmp_whole64_directed pmp_modes_directed vec_trap_directed}; do
  make -s -C $W/sim ../build/sim/$T.bin > /dev/null 2>&1 || { echo "build $T failed"; make -C $W/sim ../build/sim/$T.bin 2>&1 | tail -5; continue; }
  x=""; [ $T = vec_trap_directed ] && x="--irq-timer-after 2000"
  (cd $W/build/sim && echo "== core $T rand: $(./core_tb $T.bin 8000000 $x --mem-lat 1:6 --mem-gap 2 --mem-ready 70 --mem-seed 7 2>&1 | tail -1)"; echo "== core $T nocache: $(./core_tb $T.bin 8000000 $x --no-cache 2>&1 | tail -1)")
done
