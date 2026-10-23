# Sigil platform init for riscv-dv pygen programs (issue #8). The
# generator includes this file first thing at _start, in M-mode.
#
# pygen does not configure PMP (setup_pmp is a TODO upstream), and on a
# hart with PMP entries (Sigil: 16, G=0) S/U accesses that match no
# entry fail. Open entry 0 as one NAPOT region over the whole physical
# address space with R/W/X, unlocked (M-mode stays unaffected).
                  li t0, -1
                  csrw pmpaddr0, t0
                  li t0, 0x1f
                  csrw pmpcfg0, t0
