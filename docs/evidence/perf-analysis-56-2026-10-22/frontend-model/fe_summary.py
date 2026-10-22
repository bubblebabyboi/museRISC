#!/usr/bin/env python3
"""Front-end what-if table: model cycles per fetch/predictor configuration
over the RTL baseline cycles. usage: fe_summary.py <model-out-dir>... --rtl <baseline dir>
Later directories override earlier ones for the same (file, region)."""
import sys, os, csv, argparse
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tab import parse
ap = argparse.ArgumentParser()
ap.add_argument('dirs', nargs='+')
ap.add_argument('--rtl', required=True)
a = ap.parse_args()
rtl = {}; vls = {}; label = {}
for cfg in ('default', 'sky130'):
    for r in csv.DictReader(open(os.path.join(a.rtl, cfg, 'results.csv'))):
        if r['rep'] == '0' and r['mem'] == 'soc':
            k = (cfg, r['bench'], r['variant'], r['region'])
            rtl[k] = int(r['cycles']); vls[k] = int(r['stk_vls'] or 0); label[k] = r['label']
sets = [('CoreMark scalar', 'cm_scalar', 'coremark', 'scalar', 0), ('CoreMark sdk', 'cm_sdk', 'coremark', 'sdk', 0),
        ('CoreMark validation', 'cm_val', 'coremark', 'validation', 0),
        ('Dhrystone scalar', 'dhry_scalar', 'dhrystone', 'scalar', 0), ('Dhrystone sdk', 'dhry_sdk', 'dhrystone', 'sdk', 0),
        ('SHA-256 C', 'sha', 'sha256chain', 'sdk', 0), ('SHA-256 Zknh', 'sha', 'sha256chain', 'sdk', 1),
        ('bulk SHA-256 C', 'bulk', 'sha256chain_bulk', 'sdk', 0), ('bulk SHA-256 Zknh', 'bulk', 'sha256chain_bulk', 'sdk', 1)]
sets += [(None, 'kernels_scalar', 'kernels', 'scalar', k * 10) for k in range(1, 14)]
cols = ['F1', 'F3s', 'F3', 'F0+bim64+r1', 'F0+bim64', 'F0+btfn', 'F0+perfect', 'F0+bim64+btb64',
        'F3+btfn', 'F3+bim64+r1', 'F3+bim64', 'F3+gsh12', 'F3+perfect', 'F4+bim64', 'F3w16', 'F3w16s+bim64', 'F5+perfect']
print('Speedup = RTL-calibrated model cycles today (F0_rtl) / model cycles of the variant. soc memory model.\n')
for cfg in ('default', 'sky130'):
    print(f'## {cfg}\n')
    print('| Region | RTL cycles | model F0 | error | ' + ' | '.join(cols) + ' | source |')
    print('|---|---:|---:|---:|' + '---:|' * len(cols) + '---|')
    for name, f, b, v, rid in sets:
        found = None
        for d in a.dirs:
            p = os.path.join(d, f'{f}.{cfg}')
            if os.path.exists(p):
                regs = parse(p)
                if rid in regs and regs[rid]['model']:
                    found = (d, regs[rid]['model'])
        if not found:
            continue
        d, m = found
        k = (cfg, b, v, str(rid))
        base = m['F0_rtl']['cycles']; R = rtl.get(k)
        nm = name or f'kernels {label[k]}'
        cells = [f"{base / m[c]['cycles']:.3f}" if c in m else '' for c in cols]
        print(f'| {nm} | {R:,} | {base:,} | {100 * (base - R) / R:+.4f}% | ' + ' | '.join(cells) + f' | {os.path.basename(os.path.normpath(d))} |')
        if vls[k] and abs(base - R) > 0.01 * R:
            # vector LS is not modelled: hold the RTL's non-modelled cycles (R - base, about stk_vls) constant
            off = R - base
            cells = [f"{R / (m[c]['cycles'] + off):.3f}" if c in m else '' for c in cols]
            print(f'| {nm}, vector LS held at RTL (stk_vls {vls[k]:,}) | {R:,} | {base + off:,} | | ' + ' | '.join(cells) + ' | |')
    print()
