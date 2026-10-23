#!/bin/bash
# Gates for 8-riscv-dv on sigil-fpga-build (~/dv8final): lint with the
# pinned Verilator 5.048 and Ubuntu's 5.020, make test, make core-test,
# make riscv-tests.
cd ~/dv8final
L=build/gates; rm -rf $L; mkdir -p $L
source deps/env.sh >/dev/null
J=${VJOBS:-6}
{
  echo "host $(hostname) (sigil-fpga-build, $(nproc) vCPU) start $(date -u +%FT%TZ)"
  echo "head $(git rev-parse HEAD) dirty=[$(git status --porcelain | wc -l)]"
  echo "verilator(deps) $(verilator --version)"
  echo "verilator(5.020) $($HOME/rel73/v5020-path/verilator --version)"
  echo "riscv-gcc $(riscv64-unknown-elf-gcc --version | head -1)"
  echo "VJOBS=$J"
} > $L/info.txt
step() { local name=$1; shift; local t0=$(date +%s); "$@" > $L/$name.log 2>&1; local rc=$?; echo "$name rc=$rc $(( $(date +%s)-t0 ))s" >> $L/summary.txt; }
step lint-5.048 bash -c 'verilator --version; make lint'
step lint-5.020 bash -c 'export PATH=$HOME/rel73/v5020-path:$PATH; verilator --version; make lint'
step test make test
step core-test make core-test VJOBS=$J
step riscv-tests make riscv-tests VJOBS=$J
echo "core-test TB PASS lines: $(grep -c 'TB PASS' $L/core-test.log), FAIL lines: $(grep -c 'FAIL' $L/core-test.log)" >> $L/summary.txt
echo "end $(date -u +%FT%TZ)" >> $L/summary.txt
echo DONE >> $L/summary.txt
