#!/usr/bin/env bash
# ACT Zalrsc-sc case-level probe on the in-house core (issue #20).
#
# The CVA6-era sweep waived ACT Zalrsc-sc.w/sc.d because they hung
# that testharness's memory path. This probe runs them on sigil-core
# case by case instead of as a single pass/fail:
#
#  1. "noretry" variants: the upstream sources with every constrained
#     LR/SC retry budget LI(xN, 100) cut to LI(xN, 1), so an SC that
#     fails spuriously on its first attempt lands in the signature
#     instead of being retried away. Built through the same ACT flow
#     (Sail 0.15 signature + self-check ELF), then moved out of the
#     ACT tree so later full ACT runs are unaffected.
#  2. For sc.w, sc.d and both noretry variants, under each harness
#     configuration (default; --no-cache; randomized bus timing
#     --mem-lat 1:6 --mem-gap 2 --mem-ready 70 with seeds 1..SEEDS,
#     cached and uncached):
#       a) the self-check ELF on core_tb (5M-cycle budget: a hang
#          shows up as a timeout);
#       b) the signature-mode .sig.elf (the binary Sail executed)
#          with CORE_TB_SIGDUMP=1 and CORE_TB_HTIF_CONSOLE=1 (its
#          halt/print macros are Sail's HTIF ones), every signature
#          word compared with Sail's .sig (scripts/act_sig_cases.py).
#  3. Writes OUT_DIR/cases.csv (one row per test case, default
#     configuration) and OUT_DIR/runs.csv (one row per test x
#     configuration).
#
# Prereqs: EXTENSIONS=Zalrsc scripts/build_act4_core.sh has run in
# this tree, and build/sim/core_tb exists (make -C sim ../build/sim/core_tb).
#   scripts/act_zalrsc_sc_probe.sh [OUT_DIR]   (default build/act-zalrsc-probe)
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
OUT=$(mkdir -p "${1:-build/act-zalrsc-probe}" && cd "${1:-build/act-zalrsc-probe}" && pwd)
ACT=third_party/riscv-arch-test
SRC=$ACT/tests/rv64i/Zalrsc
WORK=$ACT/work/sigil-core
TB=$ROOT/build/sim/core_tb
SEEDS=${SEEDS:-16}
JOBS=${JOBS:-4}
[ -x "$TB" ] || { echo "build core_tb first: make -C sim ../build/sim/core_tb"; exit 1; }
[ -f "$WORK/elfs/rv64i/Zalrsc/Zalrsc-sc.w-00.elf" ] ||
  { echo "generate first: EXTENSIONS=Zalrsc scripts/build_act4_core.sh"; exit 1; }
mkdir -p "$OUT/src" "$OUT/elf" "$OUT/dump"

# 1. noretry variants through the ACT flow
for t in sc.w sc.d; do
  up=$SRC/Zalrsc-$t-00.S
  nr=$SRC/Zalrsc-$t-noretry-00.S
  sed 's/LI(\(x[0-9]*\), 100) # retry counter for constrained LR\/SC loop/LI(\1, 1) # retry counter cut to 1 (issue #20 probe)/' "$up" > "$nr"
  n_up=$(grep -c 'LI(x[0-9]*, 100) # retry counter' "$up")
  n_nr=$(grep -c 'LI(x[0-9]*, 1) # retry counter cut to 1' "$nr")
  echo "Zalrsc-$t-noretry-00.S: $n_nr of $n_up retry budgets cut to 1"
  [ "$n_up" = "$n_nr" ] || { echo "sed did not rewrite every retry budget"; exit 1; }
  cp "$up" "$nr" "$OUT/src/"
done
EXTENSIONS=Zalrsc scripts/build_act4_core.sh > "$OUT/act_gen.log" 2>&1 ||
  { tail -20 "$OUT/act_gen.log"; exit 1; }
for t in sc.w sc.d sc.w-noretry sc.d-noretry; do
  n=Zalrsc-$t-00
  cp "$WORK/elfs/rv64i/Zalrsc/$n.elf" "$OUT/elf/$n.elf"
  cp "$WORK/build/rv64i/Zalrsc/$n.sig.elf" "$OUT/elf/$n.sig.elf"
  cp "$WORK/build/rv64i/Zalrsc/$n.sig" "$OUT/elf/$n.sail.sig"
done
for t in sc.w sc.d; do
  rm -f "$SRC/Zalrsc-$t-noretry-00.S" \
        "$WORK/elfs/rv64i/Zalrsc/Zalrsc-$t-noretry-00.elf" \
        "$WORK"/build/rv64i/Zalrsc/Zalrsc-$t-noretry-00.*
done

# 2. runs
cfgs="default nocache"
for s in $(seq 1 "$SEEDS"); do cfgs="$cfgs rand$s rand${s}_nocache"; done
cfg_args() {
  case $1 in
    default) echo "" ;;
    nocache) echo "--no-cache" ;;
    rand*_nocache) s=${1#rand}; s=${s%_nocache}; echo "--mem-lat 1:6 --mem-gap 2 --mem-ready 70 --mem-seed $s --no-cache" ;;
    rand*) echo "--mem-lat 1:6 --mem-gap 2 --mem-ready 70 --mem-seed ${1#rand}" ;;
  esac
}
export -f cfg_args
export TB OUT ROOT
one() {
  local t=$1 cfg=$2 n=Zalrsc-$1-00 args out rc cyc v sv sres
  args=$(cfg_args "$cfg")
  # shellcheck disable=SC2086
  out=$("$TB" "$OUT/elf/$n.elf" 5000000 $args 2>&1); rc=$?
  cyc=$(echo "$out" | sed -n 's/.* \([0-9][0-9]*\) cycles.*/\1/p' | tail -1)
  case $rc in 0) v=PASS;; 2) v=TIMEOUT;; *) v=FAIL;; esac
  # shellcheck disable=SC2086
  CORE_TB_HTIF_CONSOLE=1 CORE_TB_SIGDUMP=1 "$TB" "$OUT/elf/$n.sig.elf" 5000000 $args \
    > "$OUT/dump/$n.$cfg.dump" 2>&1; sv=$?
  sres=$(python3 -I "$ROOT/scripts/act_sig_cases.py" "$OUT/src/$n.S" "$OUT/elf/$n.sail.sig" \
           "$OUT/dump/$n.$cfg.dump" "$n" 2>&1 >/dev/null)
  local words mis
  words=$(echo "$sres" | sed -n 's/.*core=\([0-9]*\);.*/\1/p')
  mis=$(echo "$sres" | sed -n 's/.*word mismatches \([0-9]*\);.*/\1/p')
  local sig_v=MATCH sig_run=PASS
  [ "$sv" -eq 0 ] || sig_run=FAIL
  { [ "$sv" -eq 0 ] && [ "$mis" = 0 ] && [ -n "$words" ] && [ "$words" -gt 0 ]; } || sig_v=MISMATCH
  echo "$n,$cfg,$v,$cyc,$sig_run,$words,$mis,$sig_v" > "$OUT/dump/$n.$cfg.row"
}
export -f one
: > "$OUT/jobs.txt"
for t in sc.w sc.d sc.w-noretry sc.d-noretry; do
  for c in $cfgs; do echo "$t $c" >> "$OUT/jobs.txt"; done
done
set +e
xargs -P "$JOBS" -L 1 bash -c 'one "$@"' _ < "$OUT/jobs.txt"
set -e
{ echo "test,config,selfcheck_elf,selfcheck_cycles,sig_elf_run,sig_words,sig_word_mismatches,signature_vs_sail"
  for t in sc.w sc.d sc.w-noretry sc.d-noretry; do
    for c in $cfgs; do cat "$OUT/dump/Zalrsc-$t-00.$c.row"; done
  done; } > "$OUT/runs.csv"

# 3. per-case table (default configuration)
{ echo "test,case,coverpoint,slots,sail,core,result"
  for t in sc.w sc.d sc.w-noretry sc.d-noretry; do
    n=Zalrsc-$t-00
    python3 -I scripts/act_sig_cases.py "$OUT/src/$n.S" "$OUT/elf/$n.sail.sig" \
      "$OUT/dump/$n.default.dump" "$n" --csv 2>>"$OUT/summary.txt" | tail -n +2
  done; } > "$OUT/cases.csv"
runs=$(( $(wc -l < "$OUT/runs.csv") - 1 ))
pass=$(grep -c ',PASS,[0-9]*,PASS,.*,MATCH$' "$OUT/runs.csv" || true)
cases=$(grep -vc '^test,\|,canary,\|,unused_slots' "$OUT/cases.csv" || true)
cmatch=$(grep -v ',canary,\|,unused_slots' "$OUT/cases.csv" | grep -c ',MATCH$' || true)
echo "runs: $pass/$runs self-check PASS with signature == Sail" | tee -a "$OUT/summary.txt"
echo "cases (default config): $cmatch/$cases match Sail" | tee -a "$OUT/summary.txt"
[ "$pass" = "$runs" ] && [ "$cmatch" = "$cases" ]
