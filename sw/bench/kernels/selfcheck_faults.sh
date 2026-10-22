#!/usr/bin/env bash
# Fault injection for the kernels benchmark's self-checks (README.md,
# "Validation"). Each case copies this directory to a scratch
# directory, applies one wrong-result edit, builds it
# (BENCH_ITERATIONS=1) and runs it on soc_rtl_tb. Every case must make
# the program fail; the script exits 1 if any run passes (or an edit
# no longer applies to the sources).
#
#   sw/bench/kernels/selfcheck_faults.sh [soc_rtl_tb] [scratch-dir]
#
# Defaults: <repo>/build/sim/soc_rtl_tb (make -C sim ../build/sim/soc_rtl_tb)
# and <repo>/build/kernels-faults. Needs the RISC-V toolchain on PATH
# (source deps/env.sh).
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
tb=${1:-$root/build/sim/soc_rtl_tb}
scratch=${2:-$root/build/kernels-faults}
[ -x "$tb" ] || { echo "no testbench $tb" >&2; exit 2; }
rm -rf "$scratch"
mkdir -p "$scratch"

echo "# kernels self-check fault injection, $(date -u +%Y-%m-%dT%H:%M:%SZ)," \
     "commit $(git -C "$root" rev-parse --short HEAD), $(riscv64-unknown-elf-gcc --version | head -1)"

run_case() { # name file sed-script
  local name=$1 file=$2 script=$3 d=$scratch/$1 rc
  cp -r "$here" "$d"
  rm -rf "$d/build"
  sed -i "$script" "$d/$file"
  if cmp -s "$here/$file" "$d/$file"; then
    printf '## case %s: %s\n   the edit did not apply: test setup error\n\n' "$name" "$file" \
      >"$scratch/$name.out"
    return 1
  fi
  {
    echo "## case $name: $file"
    diff "$here/$file" "$d/$file" | sed 's/^/   /'
    if ! make -s -C "$d" SIGIL_SDK="$root/sw/sdk" BENCH_ITERATIONS=1 OUT="$d/build" \
         >"$d/build.log" 2>&1; then
      echo "   build failed"; sed 's/^/   /' "$d/build.log"
    fi
    "$tb" 200000000 --mem-lat 1:1 --mem-gap 0 --mem-ready 100 \
      --load 0x80000000="$d/build/kernels.bin" \
      --exit-string "SIGIL TEST PASS kernels" --fail-string "SIGIL TEST FAIL" \
      +sigil_perf="$d/run.perf" >"$d/run.log" 2>&1
    rc=$?
    grep -E "MISMATCH|KAT|CHECK OK|SIGIL TEST|TB (PASS|FAIL)" "$d/run.log" | sed 's/^/   /'
    if [ $rc -ne 0 ]; then
      echo "   testbench exit status $rc: failed, as required"
    else
      echo "   testbench exit status 0: UNEXPECTED PASS"
    fi
    echo
  } >"$scratch/$name.out"
  [ $rc -ne 0 ]
}

# name | file | edit (one wrong result each)
cases=(
  "kat_wrong|kernels_kat.h|s/^#define KAT_VADD_I32 0x6c3c6ed2b2e5e720ull/#define KAT_VADD_I32 0x6c3c6ed2b2e5e721ull/"
  "rvv_vadd_short_store|kern_rvv.c|s/__riscv_vadd_vv_i32m8(va, vb, vl), vl);/__riscv_vadd_vv_i32m8(va, vb, vl), vl > 1 ? vl - 1 : vl);/"
  "c_daxpy_one_element|kern_c.c|/ daxpy_c(/,/^}/ s/y\[i\] = a \* x\[i\] + y\[i\];/y[i] = a * x[i] + y[i] + (i == 300 ? 0.0625 : 0.0);/"
  "rvv_ddot_wrong_operand|kern_rvv.c|s/acc = __riscv_vfmacc_vv_f64m8_tu(acc, vx, vy, vl);/acc = __riscv_vfmacc_vv_f64m8_tu(acc, vx, vx, vl);/"
  "rvv_memcpy_overrun|kern_rvv.c|s|for (size_t vl, w = n / 8; w > 0; w -= vl, sp += vl, dp += vl) {|for (size_t vl, w = n / 8 + 1; w > 0; w -= vl, sp += vl, dp += vl) {|"
  "ref_sgemm_one_element|ref.c|/ sgemm_ref(/,/^}/ s/      c\[i \* n + j\] = s;/      c[i * n + j] = (i == 5 \&\& j == 7) ? s + 1.0f : s;/"
  "rvv_mac_i16_last_strip|kern_rvv.c|s/acc = __riscv_vwmacc_vv_i32m8_tu(acc, vx, vy, vl);/acc = __riscv_vwmacc_vv_i32m8_tu(acc, vx, vy, n > vl ? vl : vl - 1);/"
)
pids=()
for c in "${cases[@]}"; do
  IFS='|' read -r name file script <<<"$c"
  run_case "$name" "$file" "$script" &
  pids+=($!)
done
bad=0
for p in "${pids[@]}"; do wait "$p" || bad=1; done
cat "$scratch"/*.out
if [ $bad -ne 0 ]; then
  echo "RESULT: at least one injected fault was NOT detected (or did not apply)"
  exit 1
fi
echo "RESULT: all ${#cases[@]} injected faults detected (every run failed)"
