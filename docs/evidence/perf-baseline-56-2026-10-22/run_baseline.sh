#!/usr/bin/env bash
# #56 deterministic simulation baseline (docs/PERFORMANCE.md): the whole
# benchmark suite in the default, sky130 and fpga configurations, on both
# memory models (soc, axi), every simulation twice.
#
#   docs/evidence/perf-baseline-56-2026-10-22/run_baseline.sh [OUT]
#
# Run from a 56-perf-harness checkout with deps/ installed
# (scripts/install_deps.sh --gcc15). It
#   1. records the commit, the rtl/ difference to main eeaa332 and the
#      tool versions (env.log), and checks that the synthesis views of
#      rtl/ equal main's (synth-view-diff.log),
#   2. rebuilds the six perf testbenches from scratch (tb-build.log),
#   3. runs `make -C sim perf` once per configuration, MEM="soc axi",
#      REPEAT=2, into OUT/<config>/ (results.json/.csv, report.md, runs/,
#      perf-run.log).
# JOBS (default 12) bounds the parallel simulations and Verilator threads.
set -euo pipefail
ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
OUT=${1:-$ROOT/build/perf/baseline-56}
JOBS=${JOBS:-12}
CONFIGS=${CONFIGS:-"default sky130 fpga"}
MAIN=eeaa33299d7ba6df5743375ebeed9475b3f206b4
cd "$ROOT"
set +u; source deps/env.sh; set -u
rm -rf "$OUT"
mkdir -p "$OUT"

{
  echo "start_utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "git_head: $(git rev-parse HEAD) ($(git rev-parse --abbrev-ref HEAD))"
  echo "tracked files modified: $(git status --porcelain --untracked-files=no | wc -l)"
  echo "origin/main: $(git rev-parse origin/main)"
  echo "merge-base with main: $(git merge-base HEAD $MAIN)"
  echo "rtl/ tree: $(git rev-parse HEAD:rtl) (main $MAIN: $(git rev-parse $MAIN:rtl))"
  echo "verilator: $(verilator --version)"
  echo "riscv gcc: $(riscv64-unknown-elf-gcc --version | head -1) ($(command -v riscv64-unknown-elf-gcc))"
  echo "host c++: $(g++ --version | head -1)"
  echo "python: $(python3 --version)"
  echo "make: $(make --version | head -1)"
  echo "host: $(uname -srvm); $(lscpu | sed -n 's/^Model name: *//p'); nproc $(nproc)"
  echo "jobs: $JOBS"
  echo
  echo "== git diff --stat $MAIN -- rtl/"
  git diff --stat $MAIN -- rtl/
  echo
  echo "== git diff $MAIN -- rtl/ (the .sv files; sigil_perf.svh is new and only included under ifndef SYNTHESIS)"
  git diff $MAIN -- rtl/ ':!rtl/core/sigil_perf.svh'
} > "$OUT/env.log" 2>&1
cat "$OUT/env.log"

scripts/synth_view_diff.sh $MAIN HEAD > "$OUT/synth-view-diff.log" 2>&1
cat "$OUT/synth-view-diff.log"

# Fresh testbenches: soc_rtl_tb / fpga_top_tb for default, _sky130, _vrforeg.
TBS=""
for fam in "" _sky130 _vrforeg; do
  for tb in soc_rtl_tb fpga_top_tb; do
    rm -f "build/sim/$tb$fam"
    TBS="$TBS ../build/sim/$tb$fam"
  done
  rm -rf "build/sim/obj/socrtl$fam" "build/sim/obj/fpgatop$fam"
done
{
  echo "start_utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  make -C sim VJOBS="$JOBS" $TBS
  echo "end_utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$OUT/tb-build.log" 2>&1
tail -3 "$OUT/tb-build.log"

rc=0
for cfg in $CONFIGS; do
  mkdir -p "$OUT/$cfg"
  {
    echo "start_utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    make -C sim perf CONFIG="$cfg" MEM="soc axi" REPEAT=2 JOBS="$JOBS" VJOBS="$JOBS" \
      CLOCK_MHZ="62.5 100" PERF_OUT="$OUT/$cfg" || rc=1
    echo "end_utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$OUT/$cfg/perf-run.log" 2>&1
  tail -4 "$OUT/$cfg/perf-run.log"
done
echo "run_baseline: exit $rc"
exit $rc
