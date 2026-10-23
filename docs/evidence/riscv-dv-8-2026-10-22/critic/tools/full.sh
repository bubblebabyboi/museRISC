#!/bin/bash
# Full riscv-dv round on the current head of ~/wt/8-riscv-dv (critic, after the merge of main).
# usage: full.sh <name> <tests> <seeds> <jobs>
set -u
N=$1; T=$2; SEEDS=$3; J=$4
cd ~/wt/8-riscv-dv || exit 1
source deps/env.sh
export SPIKE=~/opt/spike/bin/spike
OUT=~/rdvcrit2/$N
mkdir -p "$OUT"
{
  echo "# start $(date -u)"
  echo "# commit $(git rev-parse HEAD)"
  echo "# args --tests $T --seeds $SEEDS --jobs $J"
  echo "# verilator $(verilator --version)"
  echo "# spike $(cat ~/spike.sha)"
  echo "# gcc $(riscv64-unknown-elf-gcc --version | head -1)"
} > "$OUT/meta.txt"
make -C sim ../build/sim/core_tb > "$OUT/core_tb_build.log" 2>&1
echo "# core_tb build rc $?" >> "$OUT/meta.txt"
/usr/bin/time -v scripts/riscv_dv_regress.sh --tests "$T" --seeds "$SEEDS" --jobs "$J" --out "$OUT/run" > "$OUT/driver.log" 2> "$OUT/time.txt"
echo "# rc $?" >> "$OUT/meta.txt"
echo "# end $(date -u)" >> "$OUT/meta.txt"
