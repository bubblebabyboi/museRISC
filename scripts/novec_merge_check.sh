#!/usr/bin/env bash
# #13 merge gate: re-prove the no-vector invariance on the merge commit
# that brings the no-vector change (SIGIL_NO_VECTOR, sigil_pkg::
# HAS_VECTOR) together with another line of development, e.g.
# 53-mem-stage-pipeline (SIGIL_FPGA_TIMING). Run it in a checkout of
# the merge commit itself (the one about to be pushed), not on a
# hand-resolved patch: what is proven is that tree.
#
# REF is the merge parent WITHOUT the no-vector change (default: the
# parent of HEAD in which sigil_pkg has no HAS_VECTOR). The proof
# holds when REF already contains main at the commit the no-vector
# branch is based on, so that HEAD - REF is the no-vector change and
# nothing else: merge main (up to, not including, the no-vector merge)
# into the other branch first, then merge the no-vector change. Any
# other difference is reported by the static step and the module
# proofs.
#
# Steps (all must pass):
#   equiv    scripts/novec_equiv.sh (static, sigil_decoder, sigil_csr,
#            sigil_core in every CORE_CFGS configuration, flow, synth)
#            vs REF; again with EXTRA_DEFS=SIGIL_FPGA_TIMING and
#            MOD_CHPARAM=FPGA_TIMING=1 when REF has SIGIL_FPGA_TIMING.
#   lint     make lint, plus Verilator lint of the SIGIL_NO_VECTOR
#            configurations combined with SIGIL_FPGA_TIMING (when REF
#            has it): sigil_core, sigil_cpu, sigil_soc_top (also with
#            SIGIL_VRF_OREG) and sigil_fpga_top.
#   tests    every directed program that the no-vector suite runs
#            (sim/Makefile NOVEC_RUN_TESTS minus NOVEC_TESTS),
#            assembled with -DSIGIL_NO_VECTOR, contains no vector
#            instruction and no vector-CSR access (a test brought in
#            by the merge that uses V goes in VEC_TESTS or guards its
#            vector part with SIGIL_NO_VECTOR); and sim/run_directed.sh
#            calls core_tb only through run() or with the ${B} binary
#            prefix (a direct "$TB" call would run the default binary
#            on the no-vector core).
#   sim      (SIM=1 only) make -C sim core-novec-quick, the CI job.
# Needs what novec_equiv.sh needs (sv2v, Yosys, docker + the ORFS
# image for synth), Verilator and the RISC-V GCC.
#   scripts/novec_merge_check.sh [REF]      (STEPS="equiv lint tests sim")
# Logs: build/novec_merge/.
set -uo pipefail
cd "$(dirname "$0")/.."
STEPS=${STEPS:-"equiv lint tests${SIM:+ sim}"}
OUT=build/novec_merge; mkdir -p "$OUT"
G=${RISCV_PREFIX:-riscv64-unknown-elf-}
has_vec() { git show "$1:rtl/core/sigil_pkg.sv" 2>/dev/null | grep -qw HAS_VECTOR; }
REF=${1:-}
if [ -z "$REF" ]; then
  for p in HEAD^1 HEAD^2; do
    if git rev-parse -q --verify "$p" > /dev/null && ! has_vec "$p"; then REF=$p; break; fi
  done
fi
[ -n "$REF" ] || { echo "novec_merge_check: no merge parent without HAS_VECTOR; pass REF"; exit 2; }
has_vec HEAD || { echo "novec_merge_check: HEAD has no sigil_pkg::HAS_VECTOR"; exit 2; }
has_vec "$REF" && { echo "novec_merge_check: REF $REF already has HAS_VECTOR"; exit 2; }
if ! git diff --quiet HEAD -- rtl flow scripts sim sw Makefile; then
  echo "novec_merge_check: uncommitted changes; commit the merge first (the proof reads HEAD's tree)"; exit 2
fi
FT=0; git grep -q SIGIL_FPGA_TIMING "$REF" -- rtl && FT=1
echo "novec_merge_check: HEAD $(git rev-parse --short HEAD) vs REF $REF ($(git rev-parse --short "$REF"))," \
     "SIGIL_FPGA_TIMING in REF: $FT"
rc=0

step_equiv() {
  REF=$REF scripts/novec_equiv.sh 2>&1 | tee "$OUT/equiv.log"
  [ "${PIPESTATUS[0]}" = 0 ] || rc=1
  if [ $FT = 1 ]; then
    REF=$REF EXTRA_DEFS=SIGIL_FPGA_TIMING MOD_CHPARAM=FPGA_TIMING=1 \
      scripts/novec_equiv.sh static sigil_decoder sigil_csr sigil_core synth 2>&1 | tee "$OUT/equiv_fpga_timing.log"
    [ "${PIPESTATUS[0]}" = 0 ] || rc=1
  fi
}

step_lint() {
  local v=(verilator --lint-only -Wall -Wno-DECLFILENAME -Irtl/core) core cache rtl fpga d n=0 bad=0
  if make lint > "$OUT/lint.log" 2>&1; then
    echo "lint: make lint OK ($(grep -c '^verilator' "$OUT/lint.log") invocations)"
  else
    echo "lint: make lint FAILED (see $OUT/lint.log)"; rc=1
  fi
  read -r core < <(make -s -f - pv <<< $'include Makefile\npv: ; @echo $(CORE_RTL)')
  read -r cache < <(make -s -f - pv <<< $'include Makefile\npv: ; @echo $(CACHE_RTL)')
  read -r rtl < <(make -s -f - pv <<< $'include Makefile\npv: ; @echo $(RTL)')
  read -r fpga < <(make -s -f - pv <<< $'include Makefile\npv: ; @echo $(FPGA_RTL)')
  local x=(); [ $FT = 1 ] && x=(+define+SIGIL_FPGA_TIMING)
  : > "$OUT/lint_novec.log"
  for d in "sigil_core" "sigil_cpu" "sigil_soc_top" "sigil_soc_top +define+SIGIL_VRF_OREG" "sigil_fpga_top"; do
    local top=${d%% *} more=""; [ "$top" != "$d" ] && more=${d#* }
    local files=$core
    case $top in
      sigil_cpu) files="$core $cache" ;;
      sigil_soc_top) files="$core $cache $rtl" ;;
      sigil_fpga_top) files="$core $cache $rtl $fpga" ;;
    esac
    n=$((n + 1))
    # shellcheck disable=SC2086
    "${v[@]}" --top-module "$top" +define+SIGIL_NO_VECTOR ${x[@]+"${x[@]}"} $more $files >> "$OUT/lint_novec.log" 2>&1 ||
      { echo "lint: $top SIGIL_NO_VECTOR ${x[*]} $more FAILED"; bad=1; }
  done
  [ $bad = 0 ] && echo "lint: $n SIGIL_NO_VECTOR${x[*]:+ + SIGIL_FPGA_TIMING} tops OK" || rc=1
}

step_tests() {
  local list novec t n=0 bad=0 d=$OUT/bins
  read -r list < <(make -s -C sim -f - pv <<< $'include Makefile\npv: ; @echo $(NOVEC_RUN_TESTS)')
  read -r novec < <(make -s -C sim -f - pv <<< $'include Makefile\npv: ; @echo $(NOVEC_TESTS)')
  local fl; fl=$(make -s -C sim -f - pv <<< $'include Makefile\npv: ; @echo $(SWFLAGS)' | sed "s| -T [^ ]*| -T sw/core-tests/link.ld|")
  rm -rf "$d"; mkdir -p "$d"
  for t in $list; do
    [[ " $novec " == *" $t "* ]] && continue
    n=$((n + 1))
    # shellcheck disable=SC2086
    if ! ${G}gcc $fl -Isw/core-tests -DSIGIL_NO_VECTOR "sw/core-tests/$t.S" -o "$d/$t.elf" 2> "$d/$t.err"; then
      echo "tests: $t does not assemble with -DSIGIL_NO_VECTOR"; bad=1; continue
    fi
    ${G}objcopy -O binary --only-section='.text*' "$d/$t.elf" "$d/$t.text"
    local hits; hits=$(python3 -I - "$d/$t.text" <<'PY'
# Walk the code as an instruction stream (16-bit if bits[1:0] != 11)
# and report V instructions: OP-V (incl. vset*), vector loads/stores
# in the LOAD-FP/STORE-FP space (width not 001/010/011/100) and CSR
# instructions on vstart/vxsat/vxrm/vcsr/vl/vtype/vlenb.
import sys
b = open(sys.argv[1], 'rb').read(); i = 0; out = []
VCSR = {0x008, 0x009, 0x00A, 0x00F, 0xC20, 0xC21, 0xC22}
while i + 2 <= len(b):
    h = int.from_bytes(b[i:i+2], 'little')
    if h & 3 != 3: i += 2; continue
    if i + 4 > len(b): break
    w = int.from_bytes(b[i:i+4], 'little'); op = w & 0x7f; f3 = (w >> 12) & 7
    if op == 0x57 or (op in (0x07, 0x27) and f3 not in (1, 2, 3, 4)) or \
       (op == 0x73 and f3 not in (0, 4) and (w >> 20) in VCSR):
        out.append(f'+{i:#x}: {w:08x}')
    i += 4
print(' '.join(out[:4]) + (f' ... ({len(out)})' if len(out) > 4 else ''))
PY
)
    if [ -n "$hits" ]; then
      echo "tests: $t has vector instructions or vector-CSR accesses with -DSIGIL_NO_VECTOR: $hits" \
           "(add it to VEC_TESTS in sim/Makefile or guard the vector part)"
      bad=1
    fi
  done
  # Direct core_tb calls in run_directed.sh must use the ${B} prefix.
  local direct; direct=$(grep -nE '"\$TB" +[a-z_0-9]+\.bin' sim/run_directed.sh || true)
  if [ -n "$direct" ]; then
    echo "tests: sim/run_directed.sh calls core_tb on a default binary outside run() (use \"\${B}<bin>\" and" \
         "skip it under NOVEC=1 if it needs V):"; echo "$direct"; bad=1
  fi
  [ $bad = 0 ] && echo "tests: $n no-vector directed programs free of vector instructions; run_directed.sh calls OK" || rc=1
}

step_sim() {
  if make -C sim core-novec-quick > "$OUT/sim.log" 2>&1; then
    echo "sim: core-novec-quick $(grep -c 'CORE TB PASS' "$OUT/sim.log") PASS lines, $(grep -c '\] skip ' "$OUT/sim.log") skipped"
  else
    echo "sim: core-novec-quick FAILED (see $OUT/sim.log)"; tail -20 "$OUT/sim.log"; rc=1
  fi
}

for s in $STEPS; do
  case $s in
    equiv|lint|tests|sim) "step_$s" ;;
    *) echo "unknown step $s"; exit 2 ;;
  esac
done
echo "novec_merge_check rc=$rc"
exit $rc
