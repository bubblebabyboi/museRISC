#!/bin/bash
# Stage 3c gate (issue #18): build the upstream riscv-tests
# rv64ui/um/mi/si -p-* suites from the in-tree sources and
# run every ELF on the in-house core via the C++ harness
# (HTIF tohost exit). Prints one line per test and a summary;
# optionally writes a CSV (test,result,cycles) for evidence.
#
# Usage: run_riscv_tests.sh [out.csv]
# RISCV_TESTS_DIR overrides the source tree location.
# RISCV_TESTS_LIST (a file of test names, one per line) limits
# the run to a smoke subset; default is every test.
set -u
cd "$(dirname "$0")/.."

RT=${RISCV_TESTS_DIR:-third_party/cva6/tmp/riscv-tests}
BUILD=build/riscv-tests
CORE_TB=${CORE_TB:-build/sim/core_tb}
# Extra harness options (e.g. bus latency) for every run.
CORE_TB_ARGS=${CORE_TB_ARGS:-}
mkdir -p "$BUILD"

PREFIX=$(command -v riscv64-unknown-elf-gcc >/dev/null 2>&1 \
         && echo riscv64-unknown-elf- || echo riscv64-elf-)
GCC=${PREFIX}gcc
# Toolchain shim: this riscv-tests vintage writes satp via its
# pre-1.10 alias `sptbr`, which binutils >= 2.41 no longer
# accepts. Shadow riscv_test.h with a renamed copy (upstream
# sources stay untouched); only the CSR spelling changes.
mkdir -p "$BUILD/shim"
sed -e 's/sptbr/satp/g' -e 's|"../encoding.h"|"encoding.h"|' \
    "$RT/env/p/riscv_test.h" > "$BUILD/shim/riscv_test.h"
OPTS="-march=rv64g -mabi=lp64 -static -mcmodel=medany -fvisibility=hidden
      -nostdlib -nostartfiles -I$BUILD/shim -I$RT/env -I$RT/env/p
      -I$RT/isa/macros/scalar -T$RT/env/p/link.ld"

# The privileged suites use pre-1.10 CSR names in their sources
# (sptbr/mbadaddr/sbadaddr); compile sed-renamed copies so the
# upstream tree stays untouched. Only spellings change.
rm -rf "$BUILD/shim-src"
mkdir -p "$BUILD/shim-src"
cp -R "$RT/isa/rv64mi" "$RT/isa/rv64si" "$BUILD/shim-src/"
for f in "$BUILD/shim-src"/rv64mi/*.S "$BUILD/shim-src"/rv64si/*.S; do
  sed -e 's/sptbr/satp/g' -e 's/mbadaddr/mtval/g' \
      -e 's/sbadaddr/stval/g' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done

pass=0 fail=0 total=0
[ $# -ge 1 ] && echo "test,result,cycles" > "$1"
for suite in rv64ui rv64um rv64ua rv64uf rv64ud rv64uc rv64mi rv64si; do
  case $suite in
    rv64mi|rv64si) SRCDIR=$BUILD/shim-src/$suite ;;
    *)             SRCDIR=$RT/isa/$suite ;;
  esac
  for src in "$SRCDIR"/*.S; do
    name=$suite-p-$(basename "$src" .S)
    if [ -n "${RISCV_TESTS_LIST:-}" ]; then
      grep -qx "$name" "$RISCV_TESTS_LIST" || continue
    fi
    elf=$BUILD/$name
    if [ ! -x "$elf" ]; then
      # shellcheck disable=SC2086
      $GCC $OPTS "$src" -o "$elf" || { echo "BUILD-FAIL $name"; continue; }
    fi
    total=$((total + 1))
    # One ELF run contributes coverage (notably the boot_pc_i
    # pin, which directed binaries tie to 0).
    if [ "$name" = rv64ui-p-simple ]; then
      out=$(COV_FILE=build/sim/cov_rvtest.dat "$CORE_TB" "$elf" 2000000 $CORE_TB_ARGS 2>&1)
    else
      out=$("$CORE_TB" "$elf" 2000000 $CORE_TB_ARGS 2>&1)
    fi
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
  done
done
echo "riscv-tests rv64ui+um+ua+uf+ud+uc+mi+si: $pass/$total PASS, $fail FAIL"
[ "$fail" -eq 0 ] && [ "$total" -gt 0 ]
