#!/usr/bin/env bash
# Berkeley TestFloat vectors for the in-house FPU unit TB
# (tb/cpp/fpu_tb.cpp --testfloat). Builds testfloat_gen
# (berkeley-testfloat-3 a9c849f1, against the SoftFloat 3e host
# library already built for the unit TB with the RISCV
# specialization), generates level-1 vectors for every F/D
# operation in all five IEEE rounding modes, converts them to the
# TB's "op d rm aux a b c result flags" lines and runs them
# through the multi-cycle FPU.
#
#   TF_DIR=/path/to/berkeley-testfloat-3 ./scripts/testfloat_fpu_vectors.sh
#
# TF_DIR is cloned (a9c849f1) if missing. Outputs: build/testfloat-fpu/.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
TF_DIR="${TF_DIR:-$ROOT/build/testfloat-fpu/berkeley-testfloat-3}"
OUT=build/testfloat-fpu
SF_LIB=$ROOT/build/softfloat-host/softfloat.a
SF_DIR=$ROOT/third_party/berkeley-softfloat-3
mkdir -p "$OUT"
[ -f "$SF_LIB" ] || make -C sim "$ROOT/build/softfloat-host/softfloat.a"
if [ ! -d "$TF_DIR" ]; then
  git clone -q https://github.com/ucb-bar/berkeley-testfloat-3.git "$TF_DIR"
  git -C "$TF_DIR" checkout -q a9c849f1
fi
GEN="$TF_DIR/build/HostMuse/testfloat_gen"
if [ ! -x "$GEN" ]; then
  B="$TF_DIR/build/HostMuse"
  mkdir -p "$B"
  cp "$TF_DIR/build/template/Makefile" "$B/"
  cp "$TF_DIR/build/Linux-x86_64-GCC/platform.h" "$B/"
  sed -i -e 's/^==> *//' \
    -e "s|^SOFTFLOAT_DIR ?= .*|SOFTFLOAT_DIR ?= $SF_DIR|" \
    -e "s|^SOFTFLOAT_LIB = .*|SOFTFLOAT_LIB = $SF_LIB|" \
    -e 's|^PLATFORM ?= .*|PLATFORM ?= HostMuse|' \
    -e 's|-DFLOAT16 -DBFLOAT16 -DFLOAT64 -DEXTFLOAT80 -DFLOAT128 -DFLOAT_ROUND_ODD.*|-DFLOAT64 -DFLOAT_ROUND_ODD|' \
    -e 's|^ *-DLONG_DOUBLE_IS_EXTFLOAT80||' \
    -e 's|^LINK = ld -o \$@|LINK = cc -o $@|' \
    -e 's|^EXE = .exe|EXE =|' "$B/Makefile"
  make -C "$B" -j8 testfloat_gen >"$OUT/build.log" 2>&1
fi
[ -x "$GEN" ] || { echo "testfloat_gen build failed (see $OUT/build.log)"; exit 1; }

OPS="f32_add f32_sub f32_mul f32_div f32_sqrt f32_mulAdd f64_add f64_sub
f64_mul f64_div f64_sqrt f64_mulAdd f32_to_i32 f32_to_ui32 f32_to_i64
f32_to_ui64 f64_to_i32 f64_to_ui32 f64_to_i64 f64_to_ui64 i32_to_f32
ui32_to_f32 i64_to_f32 ui64_to_f32 i32_to_f64 ui32_to_f64 i64_to_f64
ui64_to_f64 f32_to_f64 f64_to_f32 f32_eq f32_le f32_lt f64_eq f64_le f64_lt"
: > "$OUT/vectors.txt"
for rm in near_even minMag min max near_maxMag; do
  for op in $OPS; do
    extra=""
    case "$op" in *_to_i*|*_to_ui*) extra="-exact" ;; esac
    "$GEN" -level 1 -seed 42 -r$rm $extra "$op" |
      python3 -I scripts/testfloat_fpu_vectors.py "$op" "$rm" >> "$OUT/vectors.txt"
  done
done
echo "vectors: $(wc -l < "$OUT/vectors.txt")"
make -C sim "$ROOT/build/sim/fpu_tb" >/dev/null
build/sim/fpu_tb --testfloat "$OUT/vectors.txt" | tee "$OUT/run.log" | tail -4
