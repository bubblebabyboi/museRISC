#!/usr/bin/env python3
"""Tables for the #56 F2 hardware evidence from f2_validate.py's JSON.

  f2_report.py f2_results.json > tables.md

Every figure is computed from the program's own counter line
(SIGIL PERF region=<id> cycles=<mcycle delta> instret=<minstret delta>),
on hardware and in simulation alike (the simulation's `hw_cycles` /
`hw_instret`), so both sides use the same window. Hardware values are
the median of the valid repeats.
"""
import json, statistics, sys

d = json.load(open(sys.argv[1]))
I = d['images']
MHZ = 62.5


def reg(img, rid):
    return I[img]['regions'][str(rid)]


def simc(s, key):
    v = s.get(key)
    return v['hw_cycles'] if v else None


def pct(a, b):
    return f'{(a / b - 1) * 100:+.2f}%' if a is not None and b else ''


def f(x, nd=0):
    if x is None: return ''
    return f'{x:,.{nd}f}'


def extra_key(s, cfg, mem):
    for k in s:
        if k.endswith(f'_{cfg}_{mem}') and k.startswith('base'):
            return k
    return None


out = []
p = out.append
clocks = sorted({r['host']['clock_mhz'] for im in I.values() for r in im['reps']})
p(f'Measured core clock over all {sum(len(im["reps"]) for im in I.values())} runs: '
  f'{clocks[0]:.3f}–{clocks[-1]:.3f} MHz (sigil_host: cycle counter / host wall time).\n')

has_fpga = any(extra_key(s, 'fpga', 'axi') for im in I.values() for s in im['regions'].values())

# ---- Dhrystone / CoreMark ----
p('### Dhrystone 2.1 and CoreMark 1.0\n')
hdr = '| Image | Iterations | HW cycles | HW instret | IPC | Metric (HW) | Sim default/axi | Sim default/soc |'
sep = '|---|---:|---:|---:|---:|---:|---:|---:|'
if has_fpga:
    hdr += ' Sim fpga/axi |'; sep += '---:|'
hdr += ' HW vs default/axi | At 62.5 MHz (HW) | Region wall-clock |'
sep += '---:|---:|---:|'
p(hdr); p(sep)
for img in ('dhrystone-scalar', 'dhrystone-sdk', 'coremark-scalar', 'coremark-sdk', 'coremark-validation',
            'coremark-scalar-1000', 'coremark-validation-1000'):
    if img not in I: continue
    s = reg(img, 0); it = I[img]['iterations']; c = s['cycles_median']; ins = s['instret_set'][0]
    dh = img.startswith('dhrystone')
    met = (lambda cyc: it / cyc * 1e6 / 1757) if dh else (lambda cyc: it / cyc * 1e6)
    unit = 'DMIPS/MHz' if dh else 'CoreMark/MHz'
    sa, ss = simc(s, 'sim_axi'), simc(s, 'sim_soc')
    row = (f'| {img} | {it:,} | {c:,.0f} | {ins:,} | {ins / c:.3f} | **{met(c):.3f}** {unit} | '
           f'{met(sa):.3f} | {met(ss):.3f} |' if sa else
           f'| {img} | {it:,} | {c:,.0f} | {ins:,} | {ins / c:.3f} | **{met(c):.3f}** {unit} | (not run) | {met(ss):.3f} |')
    if has_fpga:
        k = extra_key(s, 'fpga', 'axi')
        row += f' {met(s[k]["hw_cycles"]):.3f} |' if k else ' |'
    ref = sa or ss
    abs_ = f'{met(c) * MHZ:.2f} DMIPS' if dh else f'{it / (c / (MHZ * 1e6)):.2f} CoreMark'
    row += f' {pct(c, ref)}{"" if sa else " (vs soc)"} | {abs_} | {c / (MHZ * 1e6):.3f} s |'
    p(row)
p('')

# ---- SHA-256 chain ----
p('### SHA-256 hash chain (`sha256chain`, 1024 hashes per region) and 64 KiB bulk hashing\n')
hdr = '| Region | HW cycles/hash | Sim default/axi | Sim default/soc |'
sep = '|---|---:|---:|---:|'
if has_fpga: hdr += ' Sim fpga/axi |'; sep += '---:|'
hdr += ' HW vs axi | HW hashes/s at 62.5 MHz | HW instret = sim |'; sep += '---:|---:|---|'
p(hdr); p(sep)
img = 'sha256chain-sdk'
for rid, s in sorted(I[img]['regions'].items(), key=lambda kv: int(kv[0])):
    it = I[img]['iterations']; c = s['cycles_median']
    sa, ss = simc(s, 'sim_axi'), simc(s, 'sim_soc')
    row = f'| {s["label"]} | {c / it:,.1f} | {sa / it:,.1f} | {ss / it:,.1f} |'
    if has_fpga:
        k = extra_key(s, 'fpga', 'axi'); row += f' {s[k]["hw_cycles"] / it:,.1f} |' if k else ' |'
    same = s['instret_set'] == [s['sim_axi']['hw_instret']]
    row += f' {pct(c, sa)} | {MHZ * 1e6 / (c / it):,.0f} | {"yes" if same else "no: " + ", ".join(map(str, s["instret_set"])) + " vs " + str(s["sim_axi"]["hw_instret"])} |'
    p(row)
p('')
hdr = '| Bulk region (64 KiB) | HW cycles | HW bytes/cycle | Sim default/axi bytes/cycle | Sim default/soc |'
sep = '|---|---:|---:|---:|---:|'
if has_fpga: hdr += ' Sim fpga/axi |'; sep += '---:|'
hdr += ' HW vs axi (cycles) | HW MB/s at 62.5 MHz |'; sep += '---:|---:|'
p(hdr); p(sep)
img = 'sha256chain_bulk-sdk'
B = 64 * 1024
for rid, s in sorted(I[img]['regions'].items(), key=lambda kv: int(kv[0])):
    c = s['cycles_median']; sa, ss = simc(s, 'sim_axi'), simc(s, 'sim_soc')
    row = f'| {s["label"]} | {c:,.0f} | {B / c:.4f} | {B / sa:.4f} | {B / ss:.4f} |'
    if has_fpga:
        k = extra_key(s, 'fpga', 'axi'); row += f' {B / s[k]["hw_cycles"]:.4f} |' if k else ' |'
    row += f' {pct(c, sa)} | {B / c * MHZ:.2f} |'
    p(row)
p('')

# ---- kernels ----
for img in ('kernels-scalar', 'kernels-autovec'):
    p(f'### `{img}`: cycles per call (4 calls per region)\n')
    hdr = '| Kernel | HW C | HW RVV | HW RVV-e8 | HW RVV speedup | Sim default/axi C / RVV | HW vs axi C / RVV |'
    sep = '|---|---:|---:|---:|---:|---:|---:|'
    if has_fpga: hdr += ' Sim fpga/axi RVV | HW vs fpga/axi RVV |'; sep += '---:|---:|'
    p(hdr); p(sep)
    regs = I[img]['regions']; it = I[img]['iterations']
    for base in sorted({int(r) // 10 * 10 for r in regs}):
        c = regs.get(str(base)); v = regs.get(str(base + 1)); e8 = regs.get(str(base + 2))
        if not c or not v: continue
        name = c['label'].rsplit(' ', 1)[0]
        row = (f'| {name} | {c["cycles_median"] / it:,.0f} | {v["cycles_median"] / it:,.0f} | '
               f'{f(e8["cycles_median"] / it) if e8 else ""} | {c["cycles_median"] / v["cycles_median"]:.2f}x | '
               f'{simc(c, "sim_axi") / it:,.0f} / {simc(v, "sim_axi") / it:,.0f} | '
               f'{pct(c["cycles_median"], simc(c, "sim_axi"))} / {pct(v["cycles_median"], simc(v, "sim_axi"))} |')
        if has_fpga:
            k = extra_key(v, 'fpga', 'axi')
            row += (f' {v[k]["hw_cycles"] / it:,.0f} | {pct(v["cycles_median"], v[k]["hw_cycles"])} |' if k else ' | |')
        p(row)
    p('')

# ---- micro ----
p('### Microbenchmarks: cycles per operation (raw, as the harness reports them)\n')
hdr = '| Bench | Region | HW | Sim default/axi | Sim default/soc |'
sep = '|---|---|---:|---:|---:|'
if has_fpga: hdr += ' Sim fpga/axi |'; sep += '---:|'
hdr += ' HW vs axi | HW spread (max-min cycles) |'; sep += '---:|---:|'
p(hdr); p(sep)
for img in ('micro_pipe-default', 'micro_units-default', 'micro_dmem-default', 'micro_imem-default', 'micro_vec-default'):
    it = I[img]['iterations']
    for rid, s in sorted(I[img]['regions'].items(), key=lambda kv: int(kv[0])):
        c = s['cycles_median']; sa, ss = simc(s, 'sim_axi'), simc(s, 'sim_soc')
        row = f'| {img.split("-")[0]} | {s["label"]} | {c / it:.2f} | {sa / it:.2f} | {ss / it:.2f} |'
        if has_fpga:
            k = extra_key(s, 'fpga', 'axi'); row += f' {s[k]["hw_cycles"] / it:.2f} |' if k else ' |'
        row += f' {pct(c, sa)} | {s["cycles_max"] - s["cycles_min"]} |'
        p(row)
p('')

# ---- wall clock per image ----
p('### Whole runs: host wall-clock (release to exit marker)\n')
p('| Image | Repeats | Run cycles (median) | Wall-clock (median) | Measured clock |')
p('|---|---:|---:|---:|---:|')
for img, im in I.items():
    reps = im['reps']
    p(f'| {img} | {len(reps)} | {statistics.median(r["host"]["run_cycles"] for r in reps):,.0f} | '
      f'{statistics.median(r["host"]["wall_s"] for r in reps):.3f} s | '
      f'{statistics.median(r["host"]["clock_mhz"] for r in reps):.3f} MHz |')
p('')

# ---- instret agreement ----
tot = same = 0
for img, im in I.items():
    for rid, s in im['regions'].items():
        ref = s.get('sim_axi') or s.get('sim_soc')
        tot += 1
        same += s['instret_set'] == [ref['hw_instret']]
p(f'Retired instructions: {same} of {tot} regions retire exactly the simulated count on every repeat.\n')
print('\n'.join(out))
