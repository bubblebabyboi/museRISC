#!/usr/bin/env python3
"""Generate ptwstress_gadgets.S (issue #73 oops hunt).

A chain of NPAGES 4 KiB code pages. Each page ends with a load from the
data region (another root entry: VA 0x20_0000_0000) followed by k = 0..3
NOPs, so IF crosses into the next page (cold I-TLB after a thrash) while
the load reaches MEM with a cold D-TLB: the shape that makes sigil_mmu
preempt a fetch walk whose PTE read is in flight. The next page checks
the loaded value (data word at VA X holds X ^ key).

  long ptw_chain(unsigned long d, unsigned long stride, unsigned long key);
returns 0 if every load returned its expected value, else the failing
VA (the C side reports it).
"""
import sys
NPAGES = int(sys.argv[1]) if len(sys.argv) > 1 else 48
out = []
w = out.append
w("    .option norvc")
w("    .text")
w("    .balign 4096")
w("    .globl ptw_chain")
w("ptw_chain:")
# a0 = d (first data VA), a1 = stride, a2 = key; t1/s-regs not used.
w("    mv t3, a0")            # t3 = current data VA
w("    xor t4, t3, a2")       # t4 = expected
w("    mv t1, t4")            # first check passes
w("    j 9f")
w("    .balign 4096")
for j in range(NPAGES):
    k = j % 4
    w(f"9:")                   # page j start (first page: jumped to)
    w(f"    bne t1, t4, ptw_bad")
    w(f"    add t3, t3, a1")
    w(f"    xor t4, t3, a2")
    w(f"    j 8f")
    w(f"    .balign 4096")       # placeholder, fixed below
    out.pop()
    # tail at page end: ld + k nops; pad up to there
    w(f"    .skip 4096 - 16 - 4 * ({k} + 1)")
    w(f"8:  ld t1, 0(t3)")
    for _ in range(k):
        w(f"    nop")
w("9:  bne t1, t4, ptw_bad")
w("    li a0, 0")
w("    ret")
w("ptw_bad:")
w("    mv a0, t3")
w("    ret")
sys.stdout.write("\n".join(out) + "\n")
