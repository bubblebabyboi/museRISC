#!/usr/bin/env python3
"""neutralize_core.py <in sigil_core.sv> <out sigil_core.sv> [hunks]
Reverts the intended fixes of 8-riscv-dv in sigil_core.sv, leaving every other
branch change (mem_size_code, the unused vec_frs1 wire, the sim-only trace
probe) in place. hunks: comma list of iota,nanbox,pmpwide (default: all)."""
import sys
src, dst = sys.argv[1], sys.argv[2]
which = set((sys.argv[3] if len(sys.argv) > 3 else 'iota,nanbox,pmpwide').split(','))
t = open(src).read()
H = {
 'iota': [("    end else if (idex_ctrl_q.bext_op == VOP_IOTA) begin\n"
           "      ex_vd_log2 = ex_lmul_log2;\n"
           "      ex_vs2_log2 = -4'sd3;  // vs2 is a mask register\n", "")],
 'nanbox': [(".scalar_i  (idex_ctrl_q.fp_rs1 ? vec_frs1 : ex_rs1),",
             ".scalar_i  (idex_ctrl_q.fp_rs1 ? ex_frs1 : ex_rs1),")],
 'pmpwide': [("      .pmp_wide_b_i  (mem_size_code == 2'b11),\n", ""),
             ("      .pmp_wide_c_i  (1'b1),   // 8-byte PTE read / A/D write-back\n", "")],
}
for h in sorted(which):
    for old, new in H[h]:
        n = t.count(old)
        if n != 1: raise SystemExit(f'{h}: expected 1 match, found {n}: {old!r}')
        t = t.replace(old, new)
        print(f'reverted {h}: {old.strip()[:60]!r}')
open(dst, 'w').write(t)
