#!/usr/bin/env python3
"""Validate and tabulate the #56 benchmark runs on F2 hardware.

  f2_validate.py --logs DIR --bench-dir sw/bench --sha256sums SHA256SUMS --sim RESULTS.json:RUNS_DIR
                 [--sim-long RESULTS.json:RUNS_DIR] [--sim-extra base=RESULTS.json ...]
                 --json OUT.json --md OUT.md

DIR holds <image>.r<k>.uart (UART capture, sigil_host --log) and
<image>.r<k>.host (sigil_host stderr). <image> is <bench>-<variant>
or <bench>-<variant>-<iterations>.

A run is valid only if all of these hold:
  1. sigil_host exited 0 on "SIGIL TEST PASS <bench>" (the program prints
     it only after its own checks: CRCs, KATs, known answers);
  2. STATUS at the end has no UART TX overflow (bit 2);
  3. every bench.json expect line is in the UART output (substring, as
     scripts/perf_run.py checks it);
  4. exactly one "SIGIL PERF region=<id>" line per declared region, no
     other region;
  5. the UART output has the same lines as the simulation run of the same
     image (same sha256), apart from numbers on timing lines: every line
     whose text differs only in numbers must be a timing line (no
     CHECK/KAT/CRC line may differ at all), and no line may be missing,
     added or changed in its non-numeric text (catches dropped UART
     bytes).
"""
import argparse, glob, json, os, re, statistics, sys

NUM = re.compile(r'[-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?')
TB_LINE = re.compile(r'^(\$ |loaded \d+ bytes|fpga_top_tb:|soc_rtl_tb:|FPGA TOP TB |SOC RTL TB |AXI: |SoC RTL TB|'
                     r'socrtl|\[soc_rtl_tb\]|\[fpga_top_tb\]|TB PASS|TB FAIL|%Warning|- V e r i l a t i o n)')
MUST_MATCH = re.compile(r'CHECK|KAT|CRC|crc|Correct operation|digest|known answer', re.I)


def uart_lines(text):
    text = text.replace('\r', '')
    return [l for l in text.split('\n') if l.strip() != '']


def sim_uart(path):
    lines = uart_lines(open(path, errors='replace').read())
    return [l for l in lines if not TB_LINE.match(l)]


def parse_host(path):
    h = {'path': path}
    t = open(path, errors='replace').read()
    m = re.search(r'result: (\w+) \((.*)\) after ([\d.]+) s, (\d+) core cycles', t)
    if m:
        h.update(result=m.group(1), marker=m.group(2), wall_s=float(m.group(3)), run_cycles=int(m.group(4)))
    m = re.search(r'measured core clock: ([\d.]+) MHz', t)
    if m: h['clock_mhz'] = float(m.group(1))
    m = re.search(r'STATUS 0x([0-9a-fA-F]+)', t)
    if m: h['status'] = int(m.group(1), 16)
    m = re.search(r'traps: (\d+)', t)
    if m: h['traps'] = int(m.group(1))
    m = re.search(r'start_utc (\S+) rc (\d+)', t)
    if m: h.update(start_utc=m.group(1), rc=int(m.group(2)))
    m = re.search(r'loaded (\S+): (\d+) bytes', t)
    if m: h['bin_bytes'] = int(m.group(2))
    return h


def perf_lines(lines):
    out = []
    for l in lines:
        m = re.match(r'^SIGIL PERF region=(\d+) cycles=(\d+) instret=(\d+)\s*$', l)
        if m: out.append(tuple(int(x) for x in m.groups()))
    return out


def load_bench(bench_dir, bench):
    return json.load(open(os.path.join(bench_dir, bench, 'bench.json')))


def regions_of(bj, variant):
    regs = bj.get('regions', {'0': 'main'})
    lab = {int(k): (v if isinstance(v, str) else v['label']) for k, v in regs.items()}
    meta = {int(k): ({} if isinstance(v, str) else v) for k, v in regs.items()}
    var = bj.get('variants', {}).get(variant, {})
    ids = var.get('regions')
    if ids is not None:
        lab = {int(i): lab[int(i)] for i in ids}
    return lab, meta


def expects_of(bj, variant, iters):
    ex = list(bj.get('expect', [])) + list(bj.get('variants', {}).get(variant, {}).get('expect', []))
    return [e.replace('{iterations}', str(iters)) for e in ex]


def split_image(img, bench_names):
    for b in sorted(bench_names, key=len, reverse=True):
        if img.startswith(b + '-'):
            rest = img[len(b) + 1:]
            m = re.match(r'^(.*)-(\d+)$', rest)
            if m: return b, m.group(1), int(m.group(2))
            return b, rest, None
    raise SystemExit(f'unknown image {img}')


def compare_uart(hw, sim):
    """Line-by-line check; returns (errors, numeric_diff_lines)."""
    errs, diffs = [], []
    if len(hw) != len(sim):
        errs.append(f'line count {len(hw)} (hw) vs {len(sim)} (sim)')
    for i, (a, b) in enumerate(zip(hw, sim)):
        if a == b: continue
        if NUM.sub('#', a) != NUM.sub('#', b):
            errs.append(f'line {i+1} text differs: hw={a!r} sim={b!r}')
        elif MUST_MATCH.search(a):
            errs.append(f'line {i+1} check line differs: hw={a!r} sim={b!r}')
        else:
            diffs.append((i + 1, a, b))
    return errs, diffs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--logs', required=True)
    ap.add_argument('--bench-dir', required=True)
    ap.add_argument('--sha256sums', required=True, help='sha256sum output for <image>.bin (checked on the F2)')
    ap.add_argument('--sim', required=True, help='results.json:runs_dir for the 20-iteration images')
    ap.add_argument('--sim-long', help='results.json:runs_dir for the -1000 images')
    ap.add_argument('--sim-extra', action='append', default=[], help='label=results.json (cycle columns only)')
    ap.add_argument('--json', required=True)
    ap.add_argument('--md', required=True)
    a = ap.parse_args()

    def load_sim(spec):
        rj, rd = spec.split(':')
        return json.load(open(rj)), rd
    sim, sim_runs = load_sim(a.sim)
    siml = load_sim(a.sim_long) if a.sim_long else (None, None)
    extras = []
    for s in a.sim_extra:
        lab, p = s.split('=', 1)
        extras.append((lab, json.load(open(p))))

    def sim_rec(res, bench, variant, region, mem, config='default', iters=None):
        for r in res['runs']:
            if (r['bench'], r['variant'], r['region'], r['mem'], r['config']) == (bench, variant, region, mem, config) \
               and r.get('rep', 0) == 0 and (iters is None or r['iterations'] == iters):
                return r
        return None

    sums = {}
    for l in open(a.sha256sums):
        h, n = l.split()
        sums[n.lstrip('*')[:-4]] = h
    benches = [os.path.basename(os.path.dirname(p)) for p in glob.glob(os.path.join(a.bench_dir, '*/bench.json'))]
    runs, failed = [], []
    by_img = {}
    for up in sorted(glob.glob(os.path.join(a.logs, '*.r*.uart'))):
        base = up[:-5]
        img, rep = re.match(r'^(.*)\.r(\d+)$', os.path.basename(base)).groups()
        by_img.setdefault(img, []).append((int(rep), base))

    out_images = {}
    for img, reps in sorted(by_img.items()):
        bench, variant, it_over = split_image(img, benches)
        bj = load_bench(a.bench_dir, bench)
        iters = it_over or bj['iterations']
        labels, rmeta = regions_of(bj, variant)
        sha = sums[img]
        long_img = it_over is not None
        res, rdir = (siml if long_img else (sim, sim_runs))
        mem_ref = 'soc' if long_img else 'axi'
        mems = ['soc'] if long_img else ['axi', 'soc']
        # The simulation run of the same image.
        img_sha_sim = None
        for k, v in res['meta']['images'].items():
            if k == f'{bench}-{variant}':
                img_sha_sim = v['bin_sha256']
        simlog = os.path.join(rdir, f'{bench}-{variant}.{mem_ref}-default.r0.log')
        sim_lines = sim_uart(simlog)
        rec_img = {'bench': bench, 'variant': variant, 'iterations': iters, 'bin_sha256': sha,
                   'sim_bin_sha256': img_sha_sim, 'same_image_as_sim': sha == img_sha_sim,
                   'sim_log': os.path.relpath(simlog), 'sim_mem_compared': mem_ref, 'reps': []}
        for rep, base in sorted(reps):
            host = parse_host(base + '.host')
            lines = uart_lines(open(base + '.uart', errors='replace').read())
            errs = []
            exit_m = f'SIGIL TEST PASS {bench}'
            if host.get('result') != 'PASS' or host.get('marker') != exit_m or host.get('rc') != 0:
                errs.append(f"host result {host.get('result')} ({host.get('marker')}) rc {host.get('rc')}")
            if host.get('status', 0) & 0x4:
                errs.append('UART TX overflow (STATUS bit 2)')
            text = '\n'.join(lines)
            for e in expects_of(bj, variant, iters):  # substring, as scripts/perf_run.py
                if e not in text:
                    errs.append(f'expect line missing: {e!r}')
            pl = perf_lines(lines)
            got = {}
            for rid, cyc, ins in pl:
                if rid in got: errs.append(f'region {rid} twice')
                got[rid] = (cyc, ins)
            for rid in labels:
                if rid not in got: errs.append(f'region {rid} missing')
            for rid in got:
                if rid not in labels: errs.append(f'undeclared region {rid}')
            # The sim log ends at the exit string; sigil_host stops there too.
            cerrs, diffs = compare_uart(lines, sim_lines)
            errs += cerrs
            if sha != img_sha_sim:
                errs.append(f'image sha256 {sha} differs from the simulated image {img_sha_sim}')
            ok = not errs
            rrec = {'rep': rep, 'ok': ok, 'errors': errs, 'host': host,
                    'regions': {str(k): {'cycles': v[0], 'instret': v[1]} for k, v in got.items()},
                    'uart_lines': len(lines), 'numeric_diff_lines': len(diffs),
                    'numeric_diff_kinds': sorted({' '.join(d[1].split()[:2]) for d in diffs})}
            rec_img['reps'].append(rrec)
            (runs if ok else failed).append(f'{img}.r{rep}')
        # Per-region summary over the valid repeats.
        regs = {}
        for rid, lab in sorted(labels.items()):
            vals = [r['regions'][str(rid)] for r in rec_img['reps'] if r['ok'] and str(rid) in r['regions']]
            if not vals: continue
            cyc = [v['cycles'] for v in vals]
            ins = [v['instret'] for v in vals]
            s = {'label': lab, 'n': len(vals), 'cycles': cyc, 'instret': ins,
                 'cycles_median': statistics.median(cyc), 'cycles_min': min(cyc), 'cycles_max': max(cyc),
                 'instret_set': sorted(set(ins))}
            for mem in mems:
                sr = sim_rec(res, bench, variant, rid, mem, iters=iters)
                if sr:
                    s[f'sim_{mem}'] = {'hw_cycles': sr['hw_cycles'], 'hw_instret': sr['hw_instret'],
                                       'cycles': sr['counters']['cycles'],
                                       'ic_miss': sr['counters'].get('ic_miss'), 'dc_miss': sr['counters'].get('dc_miss'),
                                       'ic_miss_cyc': sr['counters'].get('ic_miss_cyc'),
                                       'dc_miss_cyc': sr['counters'].get('dc_miss_cyc'),
                                       'dc_unc': sr['counters'].get('dc_unc'), 'dc_unc_cyc': sr['counters'].get('dc_unc_cyc'),
                                       'stk_io': sr['counters'].get('stk_io'),
                                       'bus_dwb': sr['counters'].get('bus_dwb')}
            for lab2, er in extras:
                for mem in ('axi', 'soc'):
                    for cfgname in {r['config'] for r in er['runs']}:
                        sr = sim_rec(er, bench, variant, rid, mem, config=cfgname, iters=iters)
                        if sr:
                            s[f'{lab2}_{cfgname}_{mem}'] = {'hw_cycles': sr['hw_cycles'], 'hw_instret': sr['hw_instret']}
            regs[str(rid)] = s
        rec_img['regions'] = regs
        out_images[img] = rec_img

    out = {'images': out_images, 'valid_runs': runs, 'failed_runs': failed}
    json.dump(out, open(a.json, 'w'), indent=1)
    print(f'valid runs: {len(runs)}  failed: {len(failed)}')
    for f in failed:
        img, rep = f.rsplit('.r', 1)
        for r in out_images[img]['reps']:
            if str(r['rep']) == rep:
                print(' ', f, r['errors'][:5])
    # Minimal markdown (the evidence README carries the analysis).
    with open(a.md, 'w') as m:
        m.write('| image | region | label | n | HW cycles (median) | min | max | instret | sim axi cycles | sim soc cycles | HW vs axi | instret = sim |\n')
        m.write('|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---|\n')
        for img, ri in out_images.items():
            for rid, s in ri['regions'].items():
                ref = s.get('sim_axi') or s.get('sim_soc')
                sa = s.get('sim_axi', {}).get('hw_cycles', '')
                ss = s.get('sim_soc', {}).get('hw_cycles', '')
                d = f"{(s['cycles_median'] / ref['hw_cycles'] - 1) * 100:+.2f}%" if ref else ''
                ie = 'yes' if ref and s['instret_set'] == [ref['hw_instret']] else 'no'
                m.write(f"| {img} | {rid} | {s['label']} | {s['n']} | {s['cycles_median']:,} | {s['cycles_min']:,} | "
                        f"{s['cycles_max']:,} | {','.join(f'{x:,}' for x in s['instret_set'])} | "
                        f"{sa if sa == '' else f'{sa:,}'} | {ss if ss == '' else f'{ss:,}'} | {d} | {ie} |\n")
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
