#!/usr/bin/env python3
"""Counter-derived quantities quoted in docs/PERFORMANCE.md (sections 12-14).

  derive.py <perf-baseline-56 dir>  > derived.md

Reads <dir>/{default,sky130,fpga}/results.csv (rep 0; rep 1 is identical) and
prints, per headline region and configuration (soc memory model unless noted):
I$ port occupancy, fetches per instruction, average instruction size, taken
redirects, D$ accesses and hit-latency cycles per access, uncached accesses
and cycles per access, vector LS cycles per element, bus occupancy."""
import csv, sys, os
base = sys.argv[1]
rows = {}
for cfg in ('default', 'sky130', 'fpga'):
    for r in csv.DictReader(open(os.path.join(base, cfg, 'results.csv'))):
        if r['rep'] != '0':
            continue
        rows[(cfg, r['mem'], r['bench'], r['variant'], r['label'])] = r
def g(r, k):
    return int(r.get(k) or 0)
SEL = [('coremark', 'scalar', 'main', 'CoreMark scalar'), ('coremark', 'sdk', 'main', 'CoreMark sdk'),
       ('dhrystone', 'scalar', 'main', 'Dhrystone scalar'), ('dhrystone', 'sdk', 'main', 'Dhrystone sdk'),
       ('sha256chain', 'sdk', 'sha256 plain C', 'SHA-256 C'), ('sha256chain', 'sdk', 'sha256 Zknh', 'SHA-256 Zknh'),
       ('sha256chain', 'sdk', 'sha256 RVV x16 (multi-buffer)', 'SHA-256 RVV x16'),
       ('sha256chain', 'sdk', 'sha256 accel sigil_sha256_block', 'SHA-256 accel block'),
       ('sha256chain', 'sdk', 'sha256 accel sigil_sha256', 'SHA-256 accel byte API'),
       ('sha256chain', 'sdk', 'sha512 accel sigil_hash', 'SHA-512 accel chain'),
       ('sha256chain', 'sdk', 'sha3-256 accel sigil_hash', 'SHA3-256 accel chain'),
       ('sha256chain_bulk', 'sdk', 'sha512 accel sigil_hash', 'bulk SHA-512 accel'),
       ('sha256chain_bulk', 'sdk', 'sha3-256 accel sigil_hash', 'bulk SHA3-256 accel')]
print('# Counter-derived quantities (perf-baseline-56-2026-10-22, rep 0)\n')
print('I$ port occupancy = ic_access x hit cycles (2, or 3 with SRAM_OREG) / cycles. '
      'Average instruction size = (2 x ret_rvc + 4 x (instret - ret_rvc)) / instret. '
      'Redirects = br_taken + jal_redir + jalr_redir.\n')
for cfg in ('default', 'sky130'):
    lat = 3 if cfg == 'sky130' else 2
    print(f'## {cfg} / soc\n')
    print('| Region | cycles | instret | IPC | ic_access | I$ port busy | fetches/instr | RVC % | bytes/instr | redirects | redirects/instr | D$ accesses | stk_dc_lat/access | uncached | cycles/uncached | stk_io | stk_vls | ret_vls | bus busy | muldiv_busy |')
    print('|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|')
    for b, v, lab, name in SEL:
        r = rows.get((cfg, 'soc', b, v, lab))
        if not r:
            continue
        cyc, ins, rvc = g(r, 'cycles'), g(r, 'instret'), g(r, 'ret_rvc')
        ia = g(r, 'ic_access')
        red = g(r, 'br_taken') + g(r, 'jal_redir') + g(r, 'jalr_redir')
        dca = g(r, 'dc_load') + g(r, 'dc_store')
        unc = g(r, 'dc_unc')
        print(f"| {name} | {cyc:,} | {ins:,} | {ins / cyc:.3f} | {ia:,} | {100 * lat * ia / cyc:.1f}% | {ia / ins:.3f} | "
              f"{100 * rvc / ins:.1f} | {(2 * rvc + 4 * (ins - rvc)) / ins:.2f} | {red:,} | {red / ins:.3f} | {dca:,} | "
              f"{g(r, 'stk_dc_lat') / dca if dca else 0:.3f} | {unc:,} | {g(r, 'dc_unc_cyc') / unc if unc else 0:.2f} | "
              f"{g(r, 'stk_io'):,} | {g(r, 'stk_vls'):,} | {g(r, 'ret_vls'):,} | {100 * g(r, 'bus_busy_cyc') / cyc:.1f}% | {g(r, 'muldiv_busy'):,} |")
    print()
print('## Per-operation figures\n')
d = lambda cfg, mem, b, v, lab: rows[(cfg, mem, b, v, lab)]
blk = d('default', 'soc', 'sha256chain', 'sdk', 'sha256 accel sigil_sha256_block')
byt = d('default', 'soc', 'sha256chain', 'sdk', 'sha256 accel sigil_sha256')
n = 1024
print(f"- SHA-256 accelerator block API: {g(blk, 'instret') / n:.1f} instructions/hash, {g(blk, 'dc_unc') / n:.1f} uncached accesses/hash, "
      f"stk_io {g(blk, 'stk_io') / n:.1f} cycles/hash, stk_io share {100 * g(blk, 'stk_io') / g(blk, 'cycles'):.1f}%.")
print(f"- SHA-256 accelerator byte API: {g(byt, 'instret') / n:.1f} instructions/hash, "
      f"{(g(byt, 'instret') - g(blk, 'instret')) / n:.1f} more than the block API; same uncached accesses ({g(byt, 'dc_unc') / n:.1f}/hash).")
for mem in ('soc', 'axi'):
    bk = d('default', mem, 'sha256chain_bulk', 'sdk', 'sha512 accel sigil_hash')
    words = 65536 // 4
    print(f"- Bulk SHA-512 accelerator ({mem}): {g(bk, 'cycles') / words:.2f} cycles per 32-bit word; per word: "
          + ', '.join(f"{k} {g(bk, 'stk_' + k) / words:.2f}" for k in ('retire', 'fetch_lat', 'branch', 'dc_lat', 'io', 'dc_miss'))
          + f"; dc_miss {g(bk, 'dc_miss')} at {g(bk, 'dc_miss_cyc') / max(1, g(bk, 'dc_miss')):.1f} cycles; bus busy {100 * g(bk, 'bus_busy_cyc') / g(bk, 'cycles'):.1f}%.")
rv = d('default', 'soc', 'sha256chain', 'sdk', 'sha256 RVV x16 (multi-buffer)')
print(f"- SHA-256 RVV x16: {g(rv, 'ret_vec'):,} vector arithmetic instructions, stk_vec {g(rv, 'stk_vec'):,} = "
      f"{g(rv, 'stk_vec') / g(rv, 'ret_vec'):.2f} EX cycles each; region cycles per vector instruction {g(rv, 'cycles') / g(rv, 'ret_vec'):.2f}.")
for cfg in ('default', 'fpga', 'sky130'):
    ds = d(cfg, 'soc', 'dhrystone', 'sdk', 'main')
    sc = d(cfg, 'soc', 'dhrystone', 'scalar', 'main')
    print(f"- Dhrystone sdk ({cfg}): stk_vls {g(ds, 'stk_vls'):,} over {g(ds, 'ret_vls'):,} vector LS instructions = "
          f"{g(ds, 'stk_vls') / g(ds, 'ret_vls'):.0f} cycles each ({100 * g(ds, 'stk_vls') / g(ds, 'cycles'):.1f}% of cycles); "
          f"sdk minus scalar = {g(ds, 'cycles') - g(sc, 'cycles'):,} cycles.")
print()
print('## Kernels: where the cycles go (default / soc, % of cycles)\n')
print('| Region | cycles | stk_vec % | stk_vls % | stk_fpu % | stk_muldiv % | I$ port busy |')
print('|---|---:|---:|---:|---:|---:|---:|')
for (cfg, mem, b, v, lab), r in sorted(rows.items(), key=lambda x: int(x[1]['region'])):
    if cfg != 'default' or mem != 'soc' or b != 'kernels' or v != 'scalar':
        continue
    cyc = g(r, 'cycles')
    print(f"| {lab} | {cyc:,} | {100 * g(r, 'stk_vec') / cyc:.1f} | {100 * g(r, 'stk_vls') / cyc:.1f} | {100 * g(r, 'stk_fpu') / cyc:.1f} | "
          f"{100 * g(r, 'stk_muldiv') / cyc:.1f} | {100 * 2 * g(r, 'ic_access') / cyc:.1f}% |")
print()
print('## Throughput at a clock (arithmetic on simulation cycles; F2 measures 62.5 MHz on hardware)\n')
print('25 MHz is the clock the W7 sky130 floorplan meets after global routing (docs/SOC_AREA.md); '
      '100 MHz is the #53 FPGA target. Neither is a measured chip or FPGA figure.\n')
print('| Region | config | cycles/iteration | per second at 25 MHz | at 62.5 MHz | at 100 MHz |')
print('|---|---|---:|---:|---:|---:|')
TP = [('dhrystone', 'scalar', 'main', 'Dhrystone scalar (DMIPS)', 1 / 1757),
      ('coremark', 'scalar', 'main', 'CoreMark scalar (CoreMark)', 1),
      ('sha256chain', 'sdk', 'sha256 plain C', 'SHA-256 C (hashes)', 1),
      ('sha256chain', 'sdk', 'sha256 Zknh', 'SHA-256 Zknh (hashes)', 1),
      ('sha256chain', 'sdk', 'sha256 RVV x16 (multi-buffer)', 'SHA-256 RVV x16 (hashes, 16 chains)', 1),
      ('sha256chain', 'sdk', 'sha256 accel sigil_sha256_block', 'SHA-256 accel block (hashes)', 1),
      ('sha256chain', 'sdk', 'sha256 accel sigil_sha256', 'SHA-256 accel byte API (hashes)', 1),
      ('sha256chain', 'sdk', 'sha512 accel sigil_hash', 'SHA-512 accel chain (hashes)', 1),
      ('sha256chain', 'sdk', 'sha3-256 accel sigil_hash', 'SHA3-256 accel chain (hashes)', 1)]
for b, v, lab, name, scale in TP:
    for cfg in ('default', 'fpga', 'sky130'):
        r = rows[(cfg, 'soc', b, v, lab)]
        cpi = g(r, 'cycles') / g(r, 'iterations')
        f = lambda mhz: f"{mhz * 1e6 / cpi * scale:,.1f}" if scale != 1 else f"{mhz * 1e6 / cpi:,.0f}"
        if b == 'coremark':
            f = lambda mhz: f"{mhz * 1e6 / cpi:,.2f}"
        print(f"| {name} | {cfg} | {cpi:,.1f} | {f(25)} | {f(62.5)} | {f(100)} |")
