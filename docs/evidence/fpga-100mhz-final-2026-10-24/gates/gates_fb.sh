#!/bin/bash
# chain24.sh <off|fpga|lint> <sha>: quick gates on 53-100mhz-afi at <sha>
# (2026-10-24, integration step), clean build per worktree.
#  lint: make lint + lintx.sh (FPGA tops, FPGA_TIMING=1 modules) on
#        Verilator 5.048 (deps) and 5.020 (CI)
#  off:  SIGIL_FPGA_TIMING undefined: make test, oops walker set,
#        core-test (make -k: every sim target, SRAM-macro families),
#        riscv-tests
#  fpga: SIGIL_FPGA_TIMING + SIGIL_VRF_OREG on every Verilator build:
#        make test, oops walker set OOPS_CFG=fpga, core-test with the
#        vrforeg/fpga SRAM families, riscv-tests
MODE=$1; SHA=$2
W=$HOME/mhz100final
case $MODE in off) T=$W/hoff;; fpga) T=$W/hfpga;; lint) T=$W/lint;; esac
cd $T && git -c advice.detachedHead=false checkout -q --detach $SHA || exit 1
L=$W/logs24/$MODE; rm -rf $L; mkdir -p $L
source deps/env.sh >/dev/null
J=${VJOBS:-8}
V="verilator +define+SIGIL_FPGA_TIMING +define+SIGIL_VRF_OREG"
rm -rf build
{ echo "host $(hostname) (sigil-fpga-build) start $(date -u +%FT%TZ) mode $MODE"
  echo "head $(git rev-parse HEAD) dirty=[$(git status --porcelain | grep -v '^??' | wc -l)]"
  echo "verilator(deps) $(verilator --version)"; echo "verilator(5.020) $($HOME/rel73/v5020-path/verilator --version)"
  echo "riscv-gcc $(riscv64-unknown-elf-gcc --version | head -1)"; echo "VJOBS=$J"; [ $MODE = fpga ] && echo "VERILATOR=$V"; df -h / | tail -1; } > $L/info.txt
( while [ ! -f $L/stop-janitor ]; do find build/sim -maxdepth 1 -name 'nocov_*.dat' -mmin +2 -delete 2>/dev/null; echo "$(date -u +%T) $(df --output=avail -h / | tail -1) $(du -sh build/sim 2>/dev/null | cut -f1)" >> $L/disk.log; sleep 60; done ) &
step() { local name=$1; shift; local t0=$(date +%s); "$@" > $L/$name.log 2>&1; local rc=$?; echo "$name rc=$rc $(( $(date +%s)-t0 ))s $(date -u +%T)" >> $L/summary.txt; }
case $MODE in
lint)
  step lint-5.048 bash -c "verilator --version; make lint && bash $HOME/mhz100/lintx.sh ."
  step lint-5.020 bash -c "export PATH=$HOME/rel73/v5020-path:\$PATH; verilator --version; make lint && bash $HOME/mhz100/lintx.sh ."
  ;;
off)
  step make-test make test
  step oops-ptw-walker make -C sim -f Makefile.oops oops-ptw-walker VJOBS=$J
  step core-test make -k core-test VJOBS=$J
  step riscv-tests make riscv-tests VJOBS=$J
  ;;
fpga)
  step make-test-fpga make test "VERILATOR=$V"
  step oops-ptw-walker-fpga make -C sim -f Makefile.oops oops-ptw-walker OOPS_CFG=fpga VJOBS=$J
  step core-test-fpga make -k core-test VJOBS=$J "VERILATOR=$V" "SRAM_MACROS=vrforeg fpga"
  step riscv-tests-fpga make riscv-tests VJOBS=$J "VERILATOR=$V"
  ;;
esac
touch $L/stop-janitor
echo "end $(date -u +%FT%TZ) porcelain-after=[$(git status --porcelain | grep -v '^??' | wc -l)]" >> $L/summary.txt
echo DONE >> $L/summary.txt
