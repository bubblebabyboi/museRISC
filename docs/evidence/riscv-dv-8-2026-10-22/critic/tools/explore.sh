#!/bin/bash
# explore.sh <file.S> <core_tb> <seeds...>: assemble, Spike, core_tb, compare
# (the driver's steps for a directed program), one line per seed.
# TNAME (default sigil_priv_test) names the test for the generator seed.
source ~/wt/8-riscv-dv/deps/env.sh
W=~/wt/8-riscv-dv; SRC=$(readlink -f $1); TB=$(readlink -f $2); shift 2
export TNAME=${TNAME:-sigil_priv_test}
B=$(basename $SRC .S)
for seed in "$@"; do
  D=~/rdvcrit2/explore/$B-$(basename $TB)-$seed; rm -rf $D; mkdir -p $D; cd $D
  gs=$(python3 -c "import os, zlib; print((zlib.crc32(os.environ['TNAME'].encode()) + $seed) & 0x7FFFFFFF)")
  riscv64-unknown-elf-gcc -march=${MARCH:-rv64gc} -mabi=lp64 -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles -DRDV_SEED=$gs $SRC -I $W/sim/riscv-dv/user_extension -T $W/third_party/riscv-dv/scripts/link.ld -o t.elf > gcc.out 2>&1 || { echo "seed $seed GCC FAIL: $(tail -2 gcc.out)"; continue; }
  ARGS=$(cd $W/sim/riscv-dv && python3 -c "import rdv_regress as r; print(' '.join(r.SPIKE_ARGS))")
  timeout 600 ~/opt/spike/bin/spike $ARGS -l --log-commits --log=spike.log --instructions=20000000 t.elf > spike.out 2>&1
  timeout 600 $TB t.elf 5000000 --drain 64 +sigil_trace=dut.trace --mem-lat 1:6 --mem-gap 2 --mem-ready 70 --mem-seed $seed > dut.out 2>&1
  python3 $W/sim/riscv-dv/rdv_trace.py --elf t.elf --spike spike.log --dut dut.trace > cmp.txt 2>&1
  echo "seed $seed: $(tail -1 dut.out | cut -c1-60) | $(head -1 cmp.txt | cut -c1-300)"
done
