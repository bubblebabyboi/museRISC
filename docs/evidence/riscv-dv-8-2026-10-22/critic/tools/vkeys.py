#!/usr/bin/env python3
"""vkeys.py <run_dir>...: records where Spike and the DUT logged different
sets of vector registers / x / f / CSR keys (the comparator checks vector
registers and CSRs only where both logged them)."""
import collections, sys
sys.path.insert(0, sys.argv[1])
import rdv_trace
tot = collections.Counter()
ex = collections.defaultdict(list)
for d in sys.argv[2:]:
    import glob, os
    elf = glob.glob(d + "/*.elf")[0]
    syms = rdv_trace.elf_symbols(elf)
    ref = rdv_trace.parse_spike(d + "/spike.log", rdv_trace.elf_entry(elf), syms["tohost"])
    dut, _ = rdv_trace.truncate_at(rdv_trace.parse_dut(d + "/dut.trace", limit=len(ref) + 16), syms["tohost"])
    asm = rdv_trace.elf_disasm(elf)
    for r, u in zip(ref, dut):
        if r.kind != "I":
            continue
        tot["records"] += 1
        if r.v or u.v:
            tot["vec_write_records"] += 1
            tot["vregs_ref"] += len(r.v)
            tot["vregs_dut"] += len(u.v)
        if set(r.v) != set(u.v):
            tot["vreg_set_differs"] += 1
            m = asm.get(r.pc, "?").split()[0]
            k = "%s ref-only %s dut-only %s" % (m, sorted(set(r.v) - set(u.v)), sorted(set(u.v) - set(r.v)))
            ex[m].append(k)
print(dict(tot))
for m, l in sorted(ex.items(), key=lambda x: -len(x[1]))[:25]:
    print("%5d %s  e.g. %s" % (len(l), m, l[0]))
