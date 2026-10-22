#!/bin/bash
# Build the #56 benchmark images for the F2 run, in a private detached
# worktree of origin/56-perf-harness, with the same make arguments the
# harness used (docs/evidence/perf-suite-56-2026-10-22/results.json).
set -euo pipefail
WT=$HOME/wt/56-f2-bins
git -C ~/sigil fetch -q origin
if [ ! -d "$WT" ]; then
  git -C ~/sigil worktree add -q --detach "$WT" origin/56-perf-harness
  (cd "$WT" && ~/sigil/scripts/worktree_setup.sh)
fi
cd "$WT"
git -c advice.detachedHead=false checkout -q --detach origin/56-perf-harness
echo "head $(git rev-parse HEAD)"
source deps/env.sh
which riscv64-unknown-elf-gcc; riscv64-unknown-elf-gcc --version | head -1
OUTB=$WT/build/f2bins
rm -rf "$OUTB"; mkdir -p "$OUTB"
SC=SIGIL_MARCH=rv64gc_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh
P=RISCV_PREFIX=riscv64-unknown-elf-
b() { # name bench args...
  local n=$1 bench=$2; shift 2
  make -C sw/bench/$bench OUT=$OUTB/$n "$@" $P > $OUTB/$n.build.log 2>&1 || { echo "BUILD FAIL $n"; tail -20 $OUTB/$n.build.log; exit 1; }
}
b coremark-scalar coremark $SC BENCH_ITERATIONS=20
b coremark-sdk coremark BENCH_ITERATIONS=20
b coremark-validation coremark $SC COREMARK_RUN=validation BENCH_ITERATIONS=20
b coremark-scalar-1000 coremark $SC BENCH_ITERATIONS=1000
b coremark-validation-1000 coremark $SC COREMARK_RUN=validation BENCH_ITERATIONS=1000
b dhrystone-scalar dhrystone $SC BENCH_ITERATIONS=2000
b dhrystone-sdk dhrystone BENCH_ITERATIONS=2000
b kernels-scalar kernels BENCH_ITERATIONS=4
b kernels-autovec kernels KERNELS_C_MARCH=rv64gcv_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh KERNELS_C_OPT=-O3 BENCH_ITERATIONS=4
b micro_dmem-default micro_dmem BENCH_ITERATIONS=4096
b micro_imem-default micro_imem BENCH_ITERATIONS=49152
b micro_pipe-default micro_pipe BENCH_ITERATIONS=4096
b micro_units-default micro_units BENCH_ITERATIONS=1024
b micro_vec-default micro_vec BENCH_ITERATIONS=256
b sha256chain-sdk sha256chain BENCH_ITERATIONS=1024
b sha256chain_bulk-sdk sha256chain_bulk BENCH_ITERATIONS=64
mkdir -p $OUTB/pay
for d in $OUTB/*/; do
  n=$(basename $d); [ $n = pay ] && continue
  cp $d/*.bin $OUTB/pay/$n.bin
  cp $d/*.elf $OUTB/pay/$n.elf
done
(cd $OUTB/pay && sha256sum *.bin > SHA256SUMS && cat SHA256SUMS)
