#!/bin/bash
# gates.sh <worktree> <vjobs>: make lint (apt Verilator 5.020 and deps/ 5.048), make test,
# make core-test, make riscv-tests in <worktree> (issue #8 review). Logs in ~/rdvcrit2/gates/.
WT=$1; VJ=${2:-8}
G=~/rdvcrit2/gates; mkdir -p $G
cd $WT || exit 1
C=$(git rev-parse --short HEAD)
ts() { date -u +%FT%TZ; }
{ echo "# git status --short (must be empty):"; git status --short; } > $G/tree.txt
{ echo "# make lint, $(/usr/bin/verilator --version), commit $C, $(ts)"
  env -i HOME=$HOME PATH=/usr/bin:/bin make lint 2>&1; echo "make lint rc=$?"; echo "# end $(ts)"; } > $G/lint-5.020.log
source deps/env.sh
{ echo "# make lint, $(verilator --version), commit $C, $(ts)"
  make lint 2>&1; echo "make lint rc=$?"; echo "# end $(ts)"; } > $G/lint-5.048.log
{ echo "# make test VJOBS=$VJ, $(verilator --version), commit $C, $(ts)"
  make test VJOBS=$VJ 2>&1; echo "make test rc=$?"; echo "# end $(ts)"; } > $G/test.log
{ echo "# make core-test VJOBS=$VJ, $(verilator --version), $(riscv64-unknown-elf-gcc --version | head -1), commit $C, $(ts)"
  /usr/bin/time -f "wall %e s" make core-test VJOBS=$VJ 2>&1; echo "make core-test rc=$?"; echo "# end $(ts)"; } > $G/core-test.log
{ echo "# make riscv-tests, $(verilator --version), commit $C, $(ts)"
  make riscv-tests 2>&1; echo "make riscv-tests rc=$?"; echo "# end $(ts)"; } > $G/riscv-tests.log
echo "# gates done $(ts)" > $G/done
