#!/bin/bash
# Mutation check of the three new core fixes: each mutant removes one
# part of a fix; the named directed tests must fail on it.
set +e
W=$HOME/wt/8-final
M=$HOME/dvfix-scratch/final/mut
rm -rf $M; mkdir -p $M
mk() {  # name file python-replace(old,new)
  local n=$1 f=$2 old=$3 new=$4
  mkdir -p $M/$n
  (cd $W && git archive HEAD) | tar -x -C $M/$n
  ln -s $W/deps $M/$n/deps
  rm -rf $M/$n/third_party; ln -s $W/third_party $M/$n/third_party
  python3 - "$M/$n/$f" "$old" "$new" <<'PY'
import sys
p,a,b=sys.argv[1:4]
s=open(p).read()
assert s.count(a)==1, (p,a)
open(p,'w').write(s.replace(a,b))
PY
}
mk no_vstart rtl/core/sigil_core.sv "(!idex_ctrl_q.vset && ex_vstart0_op && (csr_vstart != 64'd0)) ||" ""
mk no_hold rtl/core/sigil_core.sv "idex_ctrl_q.vset ||
                          (idex_ctrl_q.vec && ex_vstart0_op)));" "idex_ctrl_q.vset));"
mk no_overlap rtl/core/sigil_core.sv "(!idex_ctrl_q.vset && ex_iota_overlap) ||" "(!idex_ctrl_q.vset && ex_iota_overlap && 1'b0) ||"
mk no_cvt16 rtl/core/sigil_core.sv "((csr_vtype[5:3] < 3'd2) && !ex_fp_cvt16)" "((csr_vtype[5:3] < 3'd2) && !(ex_fp_cvt16 && 1'b0))"
mk no_sat rtl/core/sigil_vec.sv "if (cvt16 && (pos_ovf || neg_ovf)) begin" "if (cvt16 && (pos_ovf || neg_ovf) && 1'b0) begin"
mk no_sext rtl/core/sigil_vec.sv "fp_a = ((aw_q == 3'd1) && imm_q[0]) ? a_s : a;" "fp_a = a;"
run() {
  local n=$1; shift
  source $W/deps/env.sh >/dev/null
  make -s -C $M/$n/sim ../build/sim/core_tb > $M/$n.build.log 2>&1 || { echo "$n: build failed" >> $M/$n.res; return; }
  for T in "$@"; do
    make -s -C $M/$n/sim ../build/sim/$T.bin >/dev/null 2>&1
    (cd $M/$n/build/sim && echo "$n $T: $(./core_tb $T.bin 8000000 --mem-lat 1:6 --mem-gap 2 --mem-ready 70 --mem-seed 7 2>&1 | tail -1)") >> $M/$n.res
  done
}
run no_vstart vstart_illegal_directed viota_vstart_directed &
run no_hold vstart_illegal_directed &
run no_overlap viota_overlap_directed &
run no_cvt16 vfcvt_sew16_directed &
run no_sat vfcvt_sew16_directed &
run no_sext vfcvt_sew16_directed &
wait
cat $M/*.res
