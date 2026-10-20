#!/bin/bash
# Parallel equivalent of sim/run_act_core.sh: same per-ELF verdict
# (core_tb exit status, 5M-cycle budget) and CSV format. Each worker
# writes its own result file; the CSV is merged at the end and checked
# for exactly one row per ELF.
#
# Usage: run_act_core_par.sh <core_tb> <out.csv> [elf-dir] [jobs]
# Exit status: 0 only if every ELF passed and the row set is complete.
set -u
TB=$(readlink -f "$1"); OUT=$(readlink -f "$2")
cd "$(dirname "$0")/.."
ELF_DIR=${3:-third_party/riscv-arch-test/work/muserisc-core/elfs}
JOBS=${4:-24}
[ -x "$TB" ] || { echo "no core_tb at $TB"; exit 1; }
[ -d "$ELF_DIR" ] || { echo "no ELFs in $ELF_DIR; run ./scripts/build_act4_core.sh first"; exit 1; }
start=$(date +%s)
RES=$(mktemp -d)
trap 'rm -rf "$RES"' EXIT
one() {
  elf=$1; tb=$2; res=$3
  name=$(basename "$elf" .elf)
  out=$("$tb" "$elf" 5000000 2>&1); rc=$?
  cycles=$(echo "$out" | sed -n 's/.* \([0-9][0-9]*\) cycles.*/\1/p' | tail -1)
  if [ $rc -eq 0 ]; then v=PASS; else v=FAIL; fi
  # One file per ELF: no shared file offset between workers.
  printf '%s,%s,%s\n' "$name" "$v" "$cycles" > "$res/$(echo "$elf" | md5sum | cut -c1-32)"
}
export -f one
find "$ELF_DIR" -type f -name '*.elf' | sort > "$RES/.list"
nelf=$(wc -l < "$RES/.list")
[ "$nelf" -gt 0 ] || { echo "no ELFs found under $ELF_DIR"; exit 1; }
xargs -P "$JOBS" -I{} bash -c 'one "$@"' _ {} "$TB" "$RES" < "$RES/.list"
{ echo "test,result,cycles"; cat "$RES"/[0-9a-f]* 2>/dev/null | sort; } > "$OUT"
rows=$(( $(wc -l < "$OUT") - 1 ))
uniq_names=$(tail -n +2 "$OUT" | cut -d, -f1 | sort -u | wc -l)
pass=$(grep -c ',PASS,' "$OUT")
fail=$(grep -c ',FAIL,' "$OUT")
echo "ACT (muserisc-core): $pass/$nelf PASS, $fail FAIL; rows=$rows unique=$uniq_names elfs=$nelf; wall $(( $(date +%s) - start ))s"
grep ',FAIL,' "$OUT" | sed 's/^/FAIL: /'
if [ "$rows" -ne "$nelf" ] || [ "$uniq_names" -ne "$nelf" ]; then
  echo "row-count mismatch (rows=$rows unique=$uniq_names elfs=$nelf)"
  exit 1
fi
[ "$fail" -eq 0 ]
