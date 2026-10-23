#!/usr/bin/env python3
"""neutralize2.py <rtl in> <rtl out> [hunks]: reverts the fixes added to
8-riscv-dv after f239397 (review round 2) in a copy of the rtl tree, leaving
the now-unused helper signals in place. hunks (comma list, default all):
  vstart   vstart != 0 illegal for the vstart=0 class (vec_illegal term)
  hold     that class held in EX while a vector load/store is in MEM
  overlap  viota.m vs2 inside the vd group illegal (vec_illegal term)
  cvt16    int16 <-> f32 conversions legal at SEW=16 (ex_fp_bad) and the
           vector unit's int16 sign extension and int16/uint16 saturation
  w64      vl<n>re64.v elements checked by PMP as 8-byte accesses"""
import os, shutil, sys
src, dst = sys.argv[1], sys.argv[2]
which = set((sys.argv[3] if len(sys.argv) > 3 else 'vstart,hold,overlap,cvt16,w64').split(','))
if os.path.exists(dst): shutil.rmtree(dst)
shutil.copytree(src, dst)
H = {
 'vstart': [('core/sigil_core.sv', "       (!idex_ctrl_q.vset && ex_vstart0_op && (csr_vstart != 64'd0)) ||\n", "")],
 'hold': [('core/sigil_core.sv', "                         (idex_ctrl_q.csr || idex_ctrl_q.vset ||\n                          (idex_ctrl_q.vec && ex_vstart0_op)));",
           "                         (idex_ctrl_q.csr || idex_ctrl_q.vset));")],
 'overlap': [('core/sigil_core.sv', "       (!idex_ctrl_q.vset && ex_iota_overlap) ||\n", "")],
 'cvt16': [('core/sigil_core.sv', "((csr_vtype[5:3] < 3'd2) && !ex_fp_cvt16)", "(csr_vtype[5:3] < 3'd2)"),
           ('core/sigil_vec.sv', "fp_a = ((aw_q == 3'd1) && imm_q[0]) ? a_s : a;", "fp_a = a;"),
           ('core/sigil_vec.sv', "if (cvt16 && (pos_ovf || neg_ovf)) begin", "if (1'b0) begin")],
 'w64': [('core/sigil_core.sv', ".pmp_wide_b_i  (pmp_wide_data),", ".pmp_wide_b_i  (mem_size_code == 2'b11),")],
}
for h in sorted(which):
    for f, old, new in H[h]:
        p = os.path.join(dst, f); t = open(p).read()
        n = t.count(old)
        if n != 1: raise SystemExit(f'{h}: expected 1 match in {f}, found {n}: {old!r}')
        open(p, 'w').write(t.replace(old, new))
        print(f'reverted {h} in {f}: {old.strip()[:70]!r}')
