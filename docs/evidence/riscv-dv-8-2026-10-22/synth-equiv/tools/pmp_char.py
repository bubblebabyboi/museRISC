#!/usr/bin/env python3
"""pmp_char.py <main sigil_csr.sv> <branch sigil_csr.sv> <out.sv>

Builds a combinational wrapper around the PMP functions of sigil_csr as
they appear in each tree (pmp_match and pmp_check, copied verbatim from the
preprocessed SYNTHESIS view; main's renamed *_old), with the 16 pmpcfg /
pmpaddr registers as free inputs, and the properties that characterize the
branch's change (Yosys `sat -prove`, tools/pmp_char.ys):

  ok_match        aligned addr: the branch's pmp_match is main's pmp_match
                  applied to the access's two 4-byte words, {addr+4, addr}
  ok_narrow       !wide: branch pmp_check == main pmp_check
  ok_wide_nosplit wide, aligned, the lowest-numbered entry that matches
                  either word (main's matcher) matches both: same verdict
  ok_wide_split   wide, aligned, that entry matches only one word: denied
  diff_wide       wide, aligned, verdicts differ (expected satisfiable:
                  the change is observable)
"""
import re, sys
a_src, b_src, out = sys.argv[1:4]

def fns(path):
    t = open(path).read()
    m = re.search(r'  function automatic logic( \[1:0\])? pmp_match\(.*?endfunction.*?'
                  r'function automatic logic pmp_check\(.*?endfunction\n', t, re.S)
    if not m:
        raise SystemExit(f'{path}: pmp_match/pmp_check not found')
    return m.group(0)

old = fns(a_src)
old = re.sub(r'\bpmp_match\b', 'pmp_match_old', old)
old = re.sub(r'\bpmp_check\b', 'pmp_check_old', old)
new = fns(b_src)

open(out, 'w').write(f'''module pmp_char (
    input  logic [127:0]  cfg_flat,
    input  logic [1023:0] addr_flat,
    input  logic [63:0]   addr,
    input  logic [1:0]    acc,
    input  logic [1:0]    priv,
    input  logic          wide,
    input  logic [7:0]    one_cfg,
    input  logic [63:0]   one_pa,
    input  logic [63:0]   one_prev,
    output logic          ok_match,
    output logic          ok_narrow,
    output logic          ok_wide_nosplit,
    output logic          ok_wide_split,
    output logic          diff_wide,
    output logic          bad_match,
    output logic          bad_narrow,
    output logic          bad_wide_nosplit,
    output logic          bad_wide_split
);
  localparam logic [1:0] PRIV_U = 2'b00, PRIV_S = 2'b01, PRIV_M = 2'b11;
  // Packed here (sigil_csr: unpacked [0:15]); pmpcfg_q[i] / pmpaddr_q[i]
  // index the same way, entry i at cfg_flat[i*8 +: 8] / addr_flat[i*64 +: 64].
  logic [15:0][7:0]  pmpcfg_q;
  logic [15:0][63:0] pmpaddr_q;
  assign pmpcfg_q = cfg_flat;
  assign pmpaddr_q = addr_flat;
  // ---- main 9da0006 (verbatim, renamed) ----
{old}
  // ---- branch (verbatim) ----
{new}
  // ---- properties ----
  logic aligned;
  assign aligned = (addr[2:0] == 3'b000);
  logic n_new, n_old;
  assign n_new = pmp_check(addr, acc, priv, wide);
  assign n_old = pmp_check_old(addr, acc, priv);
  assign ok_match = !aligned ||
      (pmp_match(addr, one_cfg, one_pa, one_prev) ==
       {{pmp_match_old(addr | 64'd4, one_cfg, one_pa, one_prev),
         pmp_match_old(addr, one_cfg, one_pa, one_prev)}});
  assign ok_narrow = wide || (n_new == n_old);
  // Lowest-numbered entry matching either word (main's matcher): split?
  logic split;
  always_comb begin
    logic h0, h1;
    split = 1'b0;
    for (int i = 15; i >= 0; i--) begin
      h0 = pmp_match_old(addr, pmpcfg_q[i], pmpaddr_q[i],
                         (i == 0) ? 64'd0 : pmpaddr_q[i-1]);
      h1 = pmp_match_old(addr | 64'd4, pmpcfg_q[i], pmpaddr_q[i],
                         (i == 0) ? 64'd0 : pmpaddr_q[i-1]);
      if (h0 || h1) split = (h0 != h1);
    end
  end
  assign ok_wide_nosplit = !(wide && aligned && !split) || (n_new == n_old);
  assign ok_wide_split = !(wide && aligned && split) || !n_new;
  assign diff_wide = wide && aligned && (n_new != n_old);
  // Miter outputs for ABC (constant 0 iff the property holds).
  assign bad_match = !ok_match;
  assign bad_narrow = !ok_narrow;
  assign bad_wide_nosplit = !ok_wide_nosplit;
  assign bad_wide_split = !ok_wide_split;
endmodule
''')
print(f'wrote {out}')
