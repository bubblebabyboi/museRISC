#!/bin/bash
# Stage 3d gate (issue #18): run ACT4 self-checking ELFs
# generated for the museRISC in-house core (see
# scripts/build_act4_core.sh) on the core itself via the C++
# harness. Each ELF reports pass/fail by its HTIF tohost halt.
#
# Usage: run_act_core.sh [out.csv] [elf-dir]
# CORE_TB (env) overrides the harness binary; CORE_TB_ARGS (env) is
# appended to every run (e.g. bus latency, --no-cache).
set -u
cd "$(dirname "$0")/.."

CORE_TB=${CORE_TB:-build/sim/core_tb}
CORE_TB_ARGS=${CORE_TB_ARGS:-}
ELF_DIR=${2:-third_party/riscv-arch-test/work/muserisc-core/elfs}
[ -d "$ELF_DIR" ] || { echo "no ELFs in $ELF_DIR; run ./scripts/build_act4_core.sh first"; exit 1; }

pass=0 fail=0 total=0
[ $# -ge 1 ] && echo "test,result,cycles" > "$1"
while IFS= read -r elf; do
  name=$(basename "$elf" .elf)
  total=$((total + 1))
  # shellcheck disable=SC2086
  out=$("$CORE_TB" "$elf" 5000000 $CORE_TB_ARGS 2>&1)
  rc=$?
  cycles=$(echo "$out" | sed -n 's/.* \([0-9][0-9]*\) cycles.*/\1/p')
  if [ $rc -eq 0 ]; then
    pass=$((pass + 1)); res=PASS
  else
    fail=$((fail + 1)); res=FAIL
    echo "$out"
  fi
  echo "$res $name ($cycles cycles)"
  [ $# -ge 1 ] && echo "$name,$res,$cycles" >> "$1"
done < <(find "$ELF_DIR" -type f -name '*.elf' | sort)
echo "ACT (muserisc-core): $pass/$total PASS, $fail FAIL"
[ "$fail" -eq 0 ]
