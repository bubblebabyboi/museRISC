pmp_check_par == pmp_check (#53 FPGA_TIMING PMP port of the #78 rule)
=====================================================================
53-100mhz-afi merged main's PMP fix (#78: an 8-byte access that the
deciding entry matches only in part fails, also in M-mode) and ported
it to the parallel check the FPGA_TIMING build uses (548f60a,
rtl/core/sigil_csr.sv pmp_check_par: second word a54o, one 54-bit
equality eqo per entry, any/part). This proves the port equal to the
serial pmp_check that the default/ASIC build uses.

gen_miter.py  copies pmp_match, pmp_check and pmp_check_par verbatim
              out of rtl/core/sigil_csr.sv into pmp_csr_miter.sv
              (committed here as generated at ade85a9); ok = 1 iff
              both verdicts agree. Free inputs: 16 x pmpcfg (all 8
              bits), 16 x pmpaddr[53:0], addr, acc (0..3: R, W, X,
              HLVX), priv (0..3), wide; constraint: a wide (8-byte)
              access has addr[2] = 0 (8-byte accesses are 8-byte
              aligned; a misaligned one traps before its PMP verdict
              is used; the walker port's PTE accesses are aligned).
run.sh        generator -> sv2v -> Yosys "sat -prove ok 1 -verify
              -set-def-inputs" on the miter and on three mutants:
                mut1  pmp_check_par without "& ~part" (split match
                      allowed)
                mut2  pmp_check_par TOR lower bound of the second word
                      without eqo
                mut3  pmp_check (reference) without the split-match
                      deny
              Usage: run.sh [REPO] [WORKDIR]

Result (results.txt; Yosys 0.69, sv2v 0.0.13, on the Mac, 2026-10-24,
sigil_csr.sv at ade85a9 = the file of 1892e0e):
  proof  SAT proof finished - no model found: SUCCESS  (101505
         variables, 276407 clauses)
  mut1   model found: FAIL (counterexample: wide=1, ser=0, par=1)
  mut2   model found: FAIL (wide=1, ser=0, par=1)
  mut3   model found: FAIL (wide=1, ser=1, par=0)
Logs: proof.log, mut1.log, mut2.log, mut3.log (with the counterexample
inputs and outputs).

In simulation the FPGA_TIMING build also cross-checks every cycle
(g_pmp_par: $error when the parallel verdict differs from pmp_check
on any of the three ports); core-test with SIGIL_FPGA_TIMING runs the
pmp_partial/pmp_modes/pmp_whole64 directed tests under it.
