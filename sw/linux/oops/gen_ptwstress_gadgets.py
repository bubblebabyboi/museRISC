#!/usr/bin/env python3
"""Generate ptwstress_gadgets.S (issue #73 oops hunt).

A chain of NPAGES 4 KiB code pages. Each page ends with a load from the
data region (another root entry: VA 0x20_0000_0000) followed by k = 0..3
NOPs, so IF crosses into the next page (cold I-TLB after a thrash) while
the load reaches MEM with a cold D-TLB: the shape that makes sigil_mmu
preempt a fetch walk whose PTE read is in flight. On pages with
j % 8 >= 4 the tail starts with a second, older load (load1: the
previous data page, so a TLB hit, at +2040 B, a line the thrash evicted,
so a D$ miss): while it waits, the fetch walk for the next page arms and
issues in the very cycle the data load (load2) reaches MEM, the
same-cycle variant (anon_vma_clone+0x5e/+0x62 shape). The next page
checks the loaded value (data word at VA X holds X ^ key).

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
# a0 = d - stride (first data VA - stride), a1 = stride, a2 = key.
w("    mv t3, a0")            # t3 = current data VA
w("    xor t4, t3, a2")       # t4 = expected
w("    mv t1, t4")            # first check passes
w("    j 9f")
w("    .balign 4096")
HEAD = 5 * 4
for j in range(NPAGES):
    k = j % 4
    two = (j % 8) >= 4
    tail = 4 * (1 + k + (1 if two else 0))
    w("9:  bne t1, t4, ptw_bad")
    w("    mv t5, t3")            # previous data VA (load1 base)
    w("    add t3, t3, a1")
    w("    xor t4, t3, a2")
    w("    j 8f")
    w(f"    .skip 4096 - {HEAD} - {tail}")
    w("8:")
    if two:
        w("    ld t0, 2040(t5)")  # load1: TLB hit, D$ miss
    w("    ld t1, 0(t3)")         # load2: TLB miss, other root entry
    for _ in range(k):
        w("    nop")
w("9:  bne t1, t4, ptw_bad")
w("    li a0, 0")
w("    ret")
w("ptw_bad:")
w("    mv a0, t3")
w("    ret")
sys.stdout.write("\n".join(out) + "\n")
