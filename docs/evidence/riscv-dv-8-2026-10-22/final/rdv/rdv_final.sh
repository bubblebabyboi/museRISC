#!/bin/bash
# riscv-dv vs Spike on ~/wt/8-final after the ACT run: the whole list
# (seeds 1-3), then more seeds of the directed programs the fixes touch.
W=~/wt/8-final; O=~/dvfix-scratch/final/rdv; mkdir -p $O
while ! grep -q ACT_DONE ~/dvfix-scratch/final/act/summary.txt 2>/dev/null; do sleep 15; done
cd $W; source deps/env.sh >/dev/null
R() {  # name tests seeds
  local n=$1 t=$2 s=$3 t0=$(date +%s)
  ~/wt/8-riscv-dv/build/riscv-dv/venv/bin/python3 sim/riscv-dv/rdv_regress.py --tests $t --seeds $s --jobs 12 \
    --out $O/$n --gen-dir ~/wt/8-riscv-dv/build/riscv-dv/gen --venv-py ~/wt/8-riscv-dv/build/riscv-dv/venv/bin/python3 \
    --spike ~/opt/spike/bin/spike > $O/$n.log 2>&1
  echo "$n rc=$? $(( $(date +%s)-t0 ))s $(date -u +%FT%TZ)" >> $O/summary.txt
}
echo "start $(date -u +%FT%TZ) head $(git rev-parse HEAD) core_tb $(md5sum < build/sim/core_tb | cut -c1-32)" > $O/summary.txt
R full all 1-3
R vec sigil_viota_test,sigil_viota_sweep_test,sigil_viota_vstart_test,sigil_viota_overlap_test,sigil_vf_nanbox_test,sigil_vfcvt_sew16_test,sigil_vector_test 4-16
R pmp sigil_pmp_test,sigil_pmp_whole64_test,sigil_priv_test 4-12
echo RDV_DONE >> $O/summary.txt
