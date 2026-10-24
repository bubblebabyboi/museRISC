#!/bin/bash
# Differential no-vector ISA sweep (#13 review): Sigil's no-vector
# core (core_tb_novec or core_tb_sky130novec) against Spike with V
# removed from --isa (the same extensions otherwise).
#  - gen_novec_sweep.py: the vector encoding space (OP-V funct3 x
#    funct6 x vm plus random fields; LOAD-FP / STORE-FP every width x
#    bits[31:25] x bits[24:20]; the vector-CSR neighbourhood; a slice
#    with FS = Off), each case recording cause, tval and f8, run in
#    M, S, U (traps in HS via medeleg), VS (traps in M) and VU (traps
#    in VS via hedeleg), each also with every encoding at PC % 4 == 2
#    (--shift2);
#  - status_probe.S: mstatus / sstatus / vsstatus VS, FS, SD writes and
#    readbacks, including the sstatus view from VS mode.
# Each program runs on core_tb (CORE_TB_SIGDUMP=1, random bus timing)
# and on Spike (+signature, granularity 8); the signatures must be
# byte-identical. Negative control: the default core_tb (with V) gives
# a different sweep signature.
# Usage (in a scratch directory): run_sweep.sh <core_tb> <spike> [mode ...]
#   modes: m s u vs vu (default all); make -C sim novec-sweep SPIKE=...
set -euo pipefail
D=$(cd "$(dirname "$0")" && pwd); TB=$1; SPIKE=$2; shift 2
MODES=${*:-m s u vs vu}
ISA=rv64imafdcbh_zicsr_zifencei_zicntr_zbc_zbkb_zbkc_zbkx_zkne_zknd_zknh_zicond_zcb_svnapot_svadu
GCC=${RISCV_PREFIX:-riscv64-unknown-elf-}gcc
LDF=(-march=rv64gc_zicsr -mabi=lp64d -nostdlib -nostartfiles -static -T "$D/sweep.ld")
cmp_run() { # name elf cycles
  CORE_TB_SIGDUMP=1 "$TB" "$2" "$3" --mem-lat 1:6 --mem-gap 2 --mem-ready 70 | sed -n 's/^SIG //p' > "$1.sigil.sig"
  "$SPIKE" --isa=$ISA --priv=msu --pmpregions=16 --pmpgranularity=4 +signature="$1.spike.sig" \
    --signature-granularity=8 "$2"
  [ -s "$1.spike.sig" ] || { echo "SWEEP FAIL $1: no Spike signature"; exit 1; }
  cmp "$1.sigil.sig" "$1.spike.sig" && echo "SWEEP PASS $1 ($(wc -l < "$1.spike.sig") signature words)"
}
for m in $MODES; do for sh in "" --shift2; do
  t=sweep_${m}${sh:+_s2}
  python3 "$D/gen_novec_sweep.py" --mode "$m" $sh --list "$t.cases" > "$t.S"
  "$GCC" "${LDF[@]}" -o "$t.elf" "$t.S"
  cmp_run "$t" "$t.elf" 400000000
done; done
"$GCC" "${LDF[@]}" -o status_probe.elf "$D/status_probe.S"
cmp_run status_probe status_probe.elf 4000000
