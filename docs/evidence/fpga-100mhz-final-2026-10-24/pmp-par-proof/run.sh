#!/bin/bash
# pmp_check_par == pmp_check (sigil_csr.sv, #53 FPGA_TIMING path) by a
# Yosys SAT miter generated from the RTL functions, plus three mutants
# that must fail. Run from anywhere: run.sh [REPO] [WORKDIR]
# (default: this checkout, a fresh temporary directory). Needs python3,
# sv2v and yosys. Logs: WORKDIR/{proof,mut1,mut2,mut3}.log, results.txt.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=${1:-$(git -C "$HERE" rev-parse --show-toplevel)}
WD=${2:-$(mktemp -d)}
mkdir -p "$WD"
cd "$WD"
python3 -I "$HERE/gen_miter.py" "$REPO/rtl/core" .
FLOW="hierarchy -top pmp_csr_miter; proc; flatten; memory; opt; stat"
{
  echo "pmp_check_par == pmp_check, $(date -u +%FT%TZ)"
  echo "rtl/core/sigil_csr.sv sha256 $(shasum -a 256 "$REPO/rtl/core/sigil_csr.sv" 2>/dev/null | cut -d' ' -f1 || sha256sum "$REPO/rtl/core/sigil_csr.sv" | cut -d' ' -f1)"
  echo "repo $(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo '?') dirty=[$(git -C "$REPO" status --porcelain -- rtl/core/sigil_csr.sv 2>/dev/null | wc -l | tr -d ' ')]"
  echo "$(yosys -V)"; echo "sv2v $(sv2v --version)"
} > results.txt
rc_all=0
for v in "" _mut1 _mut2 _mut3; do
  name=${v#_}; name=${name:-proof}
  sv2v "pmp_csr_miter$v.sv" > "pmp_csr_miter$v.v"
  set +e
  yosys -p "read_verilog pmp_csr_miter$v.v; $FLOW; sat -prove ok 1 -verify -set-def-inputs -show-inputs -show-outputs" > "$name.log" 2>&1
  rc=$?
  set -e
  verdict=$(grep -m1 -E "SAT proof finished - no model found: SUCCESS|SAT proof finished - model found: FAIL" "$name.log" || echo "no SAT verdict")
  if [ "$name" = proof ]; then want=0; else want=fail; fi
  if { [ $want = 0 ] && [ $rc = 0 ] && grep -q "no model found: SUCCESS" "$name.log"; } ||
     { [ $want = fail ] && [ $rc != 0 ] && grep -q "model found: FAIL" "$name.log"; }; then
    res=OK
  else
    res=UNEXPECTED; rc_all=1
  fi
  printf '%-6s yosys rc=%-3s %-60s expected %-7s -> %s\n' "$name" "$rc" "$verdict" "$( [ $want = 0 ] && echo proven || echo refuted )" "$res" >> results.txt
done
grep -m1 "Solving problem with" proof.log | sed 's/^/proof: /' >> results.txt
cat results.txt
echo "workdir $WD"
exit $rc_all
