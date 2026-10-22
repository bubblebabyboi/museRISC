#!/usr/bin/env bash
# Berkeley TestFloat level-2 mulAdd on the in-house FPU (issue #20).
#
# Streams level-2 f32_mulAdd / f64_mulAdd cases from
# sw/testfloat/tf_l2_mulAdd.c (TestFloat's own case generator and
# SoftFloat 3e RISCV results, split into chunks) through the
# uninstrumented FPU unit TB (sim: fpu_tb_fast --testfloat), comparing
# result bits and all five exception flags per case.
#
#   scripts/testfloat_fpu_l2.sh build
#   scripts/testfloat_fpu_l2.sh validate        # generator == testfloat_gen
#   FMT=32 STRIDE=1 OP=fma scripts/testfloat_fpu_l2.sh run
#   scripts/testfloat_fpu_l2.sh summary OUT.csv  # merge run results
#
# run knobs: FMT (32|64), STRIDE (1 = the complete level-2 stream;
# S > 1 = every S-th grid triple + as many random triples), OP
# (fma|fms|fnms|fnma|rot), RMODES (subset of "0 1 2 3 4" =
# RNE RTZ RDN RUP RMM), CHUNK (pairs per job), JOBS, SEED (42, as the
# level-1 flow). Results: build/testfloat-fpu/l2/<tag>/ (one result
# file per chunk; reruns skip chunks that already passed).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
OUT=build/testfloat-fpu
TF_DIR="${TF_DIR:-$ROOT/build/testfloat-fpu/berkeley-testfloat-3}"
SF_DIR=$ROOT/third_party/berkeley-softfloat-3
SF_LIB=$ROOT/build/softfloat-host/softfloat.a
GEN="$TF_DIR/build/HostSigil/testfloat_gen"
TB=$ROOT/build/sim/fpu_tb_fast
SEED="${SEED:-42}"
L2="$OUT/l2"

build() {
  TF_DIR="$TF_DIR" TF_BUILD_ONLY=1 scripts/testfloat_fpu_vectors.sh
  for f in 32 64; do
    gcc -O2 -std=gnu11 -Wall -Wno-unused-function -DTF_FMT=$f \
      -DFLOAT64 -DFLOAT_ROUND_ODD \
      -I"$TF_DIR/source" -I"$TF_DIR/build/HostSigil" \
      -I"$SF_DIR/source/include" sw/testfloat/tf_l2_mulAdd.c "$SF_LIB" \
      -o "$OUT/tf_l2_f$f"
  done
  make -C sim ../build/sim/fpu_tb_fast >/dev/null
  echo "built $OUT/tf_l2_f32 $OUT/tf_l2_f64 $TB"
}

rm_flag() { case $1 in 0) echo rnear_even;; 1) echo rminMag;; 2) echo rmin;;
  3) echo rmax;; 4) echo rnear_maxMag;; esac; }
rm_name() { case $1 in 0) echo RNE;; 1) echo RTZ;; 2) echo RDN;; 3) echo RUP;;
  4) echo RMM;; esac; }

# Byte-compare generator output with testfloat_gen: the first
# VAL_LINES lines in every rounding mode for both formats, a deep
# window restored from a checkpoint, and the fpu_tb line format
# against scripts/testfloat_fpu_vectors.py.
validate() {
  local n=${VAL_LINES:-20000000} f m lo w
  for f in 32 64; do
    for m in 0 1 2 3 4; do
      cmp <("$OUT/tf_l2_f$f" raw "$m" "$SEED" 0 $((n / 2)) 1) \
          <("$GEN" -level 2 -seed "$SEED" "-$(rm_flag "$m")" "f${f}_mulAdd" | head -n "$n") \
        && echo "validate f${f}_mulAdd $(rm_name "$m") first $n lines: identical"
    done
    cmp <("$OUT/tf_l2_f$f" tb 0 "$SEED" 0 500000 1 fma) \
        <("$GEN" -level 2 -seed "$SEED" -rnear_even "f${f}_mulAdd" | head -n 1000000 |
          python3 -I scripts/testfloat_fpu_vectors.py "f${f}_mulAdd" near_even) \
      && echo "validate f${f}_mulAdd tb-format first 1000000 lines: identical to testfloat_fpu_vectors.py"
  done
  # Deep windows: 2,000,000 lines starting at pair VAL_DEEP_<fmt>
  # (line 2*lo+1), generator state from a checkpoint file.
  for f in 32 64; do
    if [ "$f" = 32 ]; then lo=${VAL_DEEP_32:-1500000000}; else lo=${VAL_DEEP_64:-400000000}; fi
    w=1000000
    "$OUT/tf_l2_f$f" ckpt "$SEED" "$lo" 2 > "$OUT/val_ckpt_f$f.txt"
    cmp <("$OUT/tf_l2_f$f" raw 3 "$SEED" "$lo" $((lo + w)) 1 "$OUT/val_ckpt_f$f.txt") \
        <("$GEN" -level 2 -seed "$SEED" -rmax "f${f}_mulAdd" | tail -n +$((2 * lo + 1)) | head -n $((2 * w))) \
      && echo "validate f${f}_mulAdd RUP lines $((2 * lo + 1))..$((2 * lo + 2 * w)) (checkpoint start): identical"
  done
}

run() {
  local fmt=${FMT:-32} stride=${STRIDE:-1} op=${OP:-fma}
  local rmodes=${RMODES:-0 1 2 3 4} jobs=${JOBS:-15}
  local chunk=${CHUNK:-33554432}
  local tag="f${fmt}_s${stride}_${op}"
  local dir="$L2/$tag" bin="$ROOT/$OUT/tf_l2_f$fmt"
  mkdir -p "$dir"
  local npairs
  npairs=$("$bin" info "$stride" | awk '{print $10}')
  local nchunks=$(( (npairs + chunk - 1) / chunk ))
  if [ ! -s "$dir/ckpt.txt" ] || [ "$(wc -l < "$dir/ckpt.txt")" -ne "$nchunks" ]; then
    echo "$(date -u +%FT%TZ) checkpoints: $nchunks x $chunk pairs"
    "$bin" ckpt "$SEED" "$chunk" "$nchunks" > "$dir/ckpt.txt"
  fi
  : > "$dir/jobs.txt"
  local m k
  for m in $rmodes; do
    for ((k = 0; k < nchunks; k++)); do
      echo "$m $k" >> "$dir/jobs.txt"
    done
  done
  echo "$(date -u +%FT%TZ) run $tag: pairs/mode $npairs, $nchunks chunks/mode, modes [$rmodes], $jobs jobs"
  export bin TB dir chunk npairs stride op SEED fmt
  one() {
    local m=$1 k=$2 lo hi res t0 out rc emitted checks fails
    lo=$((k * chunk)); hi=$((lo + chunk)); [ "$hi" -gt "$npairs" ] && hi=$npairs
    res="$dir/r_${m}_${k}.txt"
    if [ -s "$res" ] && grep -q ' PASS ' "$res"; then return 0; fi
    t0=$(date +%s)
    set +e
    out=$("$bin" tb "$m" "$SEED" "$lo" "$hi" "$stride" "$op" "$dir/ckpt.txt" \
            2> "$dir/gen_${m}_${k}.err" | "$TB" --testfloat /dev/stdin 2>&1)
    rc=$?
    set -e
    emitted=$(sed -n 's/.* emitted \([0-9]*\).*/\1/p' "$dir/gen_${m}_${k}.err")
    checks=$(echo "$out" | sed -n 's/^checks\[testfloat\] = \([0-9]*\).*/\1/p')
    fails=$(echo "$out" | sed -n 's/^fails\[testfloat\] = \([0-9]*\)/\1/p')
    [ -n "$fails" ] || fails=0
    local v=FAIL
    if [ "$rc" -eq 0 ] && [ -n "$emitted" ] && [ "$emitted" = "$checks" ] &&
       [ "$checks" -eq $((2 * (hi - lo))) ]; then v=PASS; fi
    echo "$fmt $m $k $lo $hi $emitted ${checks:-0} $fails $v $(( $(date +%s) - t0 ))" > "$res"
    [ "$v" = PASS ] || echo "$out" | grep '^FAIL' | head -8 > "$dir/fail_${m}_${k}.txt"
  }
  export -f one
  xargs -P "$jobs" -L 1 bash -c 'one "$@"' _ < "$dir/jobs.txt"
  local done_n pass_n
  done_n=$(cat "$dir"/r_*.txt 2>/dev/null | wc -l)
  pass_n=$(cat "$dir"/r_*.txt 2>/dev/null | grep -c ' PASS ' || true)
  echo "$(date -u +%FT%TZ) $tag: $pass_n/$done_n chunks PASS"
}

# Merge every run directory into one CSV row per (format, mode, op).
summary() {
  local csv=$1 d
  echo "function,instruction,rounding_mode,level,selection,stride,seed,cases_in_selection,cases_checked,fails,chunks,result,cpu_seconds" > "$csv"
  for d in "$L2"/f*_s*_*; do
    [ -d "$d" ] || continue
    local tag fmt stride op bin npairs
    tag=$(basename "$d"); fmt=${tag%%_*}; fmt=${fmt#f}
    stride=$(echo "$tag" | sed 's/^f[0-9]*_s\([0-9]*\)_.*/\1/'); op=${tag##*_}
    bin="$ROOT/$OUT/tf_l2_f$fmt"
    npairs=$("$bin" info "$stride" | awk '{print $10}')
    local m
    for m in 0 1 2 3 4; do
      ls "$d"/r_"${m}"_*.txt >/dev/null 2>&1 || continue
      cat "$d"/r_"${m}"_*.txt | awk -v fn="f${fmt}_mulAdd" -v op="$op" -v fmt="$fmt" \
        -v rmn="$(rm_name "$m")" -v stride="$stride" -v seed="$SEED" -v want=$((2 * npairs)) '
        { chk += $7; fl += $8; n++; if ($9 != "PASS") bad++; cpu += $10 }
        END {
          sx = (fmt == 32) ? ".s" : ".d";
          ins = (op == "fma") ? "fmadd" sx : (op == "fms") ? "fmsub" sx : (op == "fnms") ? "fnmsub" sx : (op == "fnma") ? "fnmadd" sx : "fmadd" sx "/fmsub" sx "/fnmsub" sx "/fnmadd" sx " (rotating)";
          sel = (stride == 1) ? "complete level-2 stream" : "every " stride "th grid triple + first random triples";
          res = (bad == 0 && chk == want) ? "PASS" : (bad == 0 ? "PARTIAL" : "FAIL");
          printf "%s,%s,%s,2,%s,%s,%s,%d,%d,%d,%d,%s,%d\n", fn, ins, rmn, sel, stride, seed, want, chk, fl, n, res, cpu
        }' >> "$csv"
    done
  done
  cat "$csv"
}

case "${1:-}" in
  build) build ;;
  validate) validate ;;
  run) run ;;
  summary) summary "${2:?usage: summary OUT.csv}" ;;
  *) sed -n '2,21p' "$0"; exit 2 ;;
esac
