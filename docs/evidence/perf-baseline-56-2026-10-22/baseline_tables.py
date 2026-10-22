#!/usr/bin/env python3
"""Cross-configuration tables for the #56 baseline (README.md here).

  baseline_tables.py OUT [--md headline.md] [--merged merged.json]

OUT holds one harness result set per configuration (OUT/<config>/
results.json from run_baseline.sh). The script

  1. checks the sets belong together: same commit and rtl/ tree, no
     failed run, REPEAT=2 with the harness's determinism check passed,
     and every image (bench x variant) bit-identical in every set, and
     repeats the determinism check itself on the raw runs (rep 0 vs
     rep 1: every counter and the hardware-counter numbers);
  2. prints the headline tables, one column per configuration/memory
     model: Dhrystone and CoreMark (cycles, IPC, DMIPS/MHz,
     CoreMark/MHz), the SHA-256 chain (cycles/hash per implementation,
     bytes/cycle, speedup over plain C), the bulk hashes (bytes/cycle),
     the kernels (cycles/call, RVV and auto-vectorization speedups over
     scalar C) and the micro benchmarks (cycles/op net of the window);
  3. prints the per-cycle accounting and the main events of the
     headline regions;
  4. with --merged, writes every set's runs into one results.json for
     the benches' own report scripts (micro_table.py,
     kernels_report.py).

Exit status 1 if a check fails.
"""

import argparse
import json
import os
import sys

CONFIGS = ("default", "sky130", "oreg", "fpga")
MEMS = ("soc", "axi")
STK = ["retire", "fetch_lat", "fetch_straddle", "fetch_miss", "fetch_unc", "fetch_itlb",
       "branch", "jal", "jalr", "serial", "loaduse", "muldiv", "fpu", "vec", "dc_lat",
       "dc_miss", "io", "dc_clean", "dtlb", "vls", "trap", "other"]
VAX = 1757


def load_sets(out):
    sets = {}
    for cfg in CONFIGS:
        p = os.path.join(out, cfg, "results.json")
        if os.path.isfile(p):
            with open(p) as f:
                sets[cfg] = json.load(f)
    if not sets:
        sys.exit(f"baseline_tables: no <config>/results.json under {out}")
    return sets


def check(sets):
    """Returns (lines, ok)."""
    lines, ok = [], True
    heads = {d["meta"]["git_head"] for d in sets.values()}
    trees = {d["meta"]["rtl_tree"] for d in sets.values()}
    if len(heads) != 1 or len(trees) != 1:
        ok = False
        lines.append(f"- FAIL: sets from different commits/trees: {heads} {trees}")
    imgs = {}
    for cfg, d in sets.items():
        m = d["meta"]
        runs = d["runs"]
        sims = {(r["bench"], r["variant"], r["mem"], r["rep"]) for r in runs}
        det = m.get("deterministic")
        # Own determinism check: rep 0 vs rep 1 of every region result.
        by = {}
        for r in runs:
            k = (r["bench"], r["variant"], r["region"], r["mem"])
            by.setdefault(k, {})[r["rep"]] = (json.dumps(r["counters"], sort_keys=True),
                                               r["hw_cycles"], r["hw_instret"])
        pairs = [v for v in by.values() if len(v) == 2]
        same = sum(1 for v in pairs if v[0] == v[1])
        lone = len(by) - len(pairs)
        good = (not d.get("failed") and m["repeat"] == 2 and det is True
                and same == len(pairs) and lone == 0 and not m["git_dirty"])
        ok &= good
        lines.append(f"- `{cfg}`: {len(runs)} valid region results, {len(d.get('failed', []))} failed, "
                     f"{len(sims)} simulations (MEM {' '.join(sorted({r['mem'] for r in runs}))}, "
                     f"REPEAT {m['repeat']}); harness determinism check "
                     f"{'PASS' if det else 'FAIL'}; rep 0 = rep 1 for {same}/{len(pairs)} "
                     f"(bench, variant, region, memory) results{'' if not lone else f', {lone} without a pair'}; "
                     f"date {m['date_utc']}; {'OK' if good else 'FAIL'}")
        for name, img in m["images"].items():
            imgs.setdefault(name, {})[cfg] = img["bin_sha256"]
    diff_imgs = [n for n, v in imgs.items() if len(set(v.values())) != 1 or len(v) != len(sets)]
    if diff_imgs:
        ok = False
        lines.append(f"- FAIL: images differ between configurations: {diff_imgs}")
    else:
        lines.append(f"- Images: all {len(imgs)} images (bench x variant) are bit-identical in the "
                     f"{len(sets)} result set(s); each set built them afresh.")
    lines.append(f"- Commit `{next(iter(heads))[:12]}`, rtl/ tree `{next(iter(trees))[:12]}`.")
    return lines, ok


def index(sets):
    """(bench, variant, region, config, mem) -> rep-0 result."""
    idx = {}
    for d in sets.values():
        for r in d["runs"]:
            if r["rep"] == 0:
                idx[(r["bench"], r["variant"], r["region"], r["config"], r["mem"])] = r
    return idx


def columns(sets):
    return [(c, m) for c in CONFIGS if c in sets for m in MEMS
            if any(r["mem"] == m for r in sets[c]["runs"])]


def head(cols, first="Benchmark", extra=()):
    h = f"| {first} | " + " | ".join(extra) + (" | " if extra else "")
    h += " | ".join(f"{c}/{m}" for c, m in cols) + " |"
    sep = "|---|" + "---|" * len(extra) + "---:|" * len(cols)
    return [h, sep]


def cyc(r):
    return r["counters"]["cycles"]


def table(idx, cols, rows, first="Benchmark", extra_names=()):
    """rows: (label, extra cells, fn(config, mem) -> str)."""
    out = head(cols, first, extra_names)
    for lab, extra, fn in rows:
        out.append(f"| {lab} | " + "".join(f"{e} | " for e in extra)
                   + " | ".join(fn(c, m) for c, m in cols) + " |")
    out.append("")
    return out


def get(idx, b, v, reg, c, m):
    return idx.get((b, v, reg, c, m))


def fmt(x, nd):
    return "-" if x is None else f"{x:,.{nd}f}"


def headline(sets, idx, cols):
    out = []
    # Dhrystone / CoreMark.
    out += ["## Dhrystone and CoreMark", ""]
    rows = []
    for b, metric, f in (("dhrystone", "DMIPS/MHz", lambda r: r["iterations"] * 1e6 / cyc(r) / VAX),
                         ("coremark", "CoreMark/MHz", lambda r: r["iterations"] * 1e6 / cyc(r))):
        variants = sorted({k[1] for k in idx if k[0] == b})
        for v in variants:
            it = next(r["iterations"] for k, r in idx.items() if k[0] == b and k[1] == v)
            def g(c, m, b=b, v=v):
                return get(idx, b, v, 0, c, m)
            rows.append((f"{b} [{v}]", ["cycles", it],
                         lambda c, m, g=g: fmt(cyc(g(c, m)), 0) if g(c, m) else "-"))
            rows.append((f"{b} [{v}]", ["IPC", it],
                         lambda c, m, g=g: fmt(g(c, m)["counters"]["instret"] / cyc(g(c, m)), 3)
                         if g(c, m) else "-"))
            rows.append((f"{b} [{v}]", [metric, it],
                         lambda c, m, g=g, f=f: fmt(f(g(c, m)), 3) if g(c, m) else "-"))
    out += table(idx, cols, rows, extra_names=("Quantity", "Iterations"))

    # SHA-256 chain.
    for b, unit in (("sha256chain", "hash"), ("sha256chain_bulk", "KiB")):
        regs = sorted({k[2] for k in idx if k[0] == b})
        if not regs:
            continue
        title = ("SHA-256 hash chain (1024 chained hashes of a 32-byte value; SHA-512 chain: 64-byte messages)"
                 if b == "sha256chain" else "Bulk hashing of one 64 KiB buffer")
        out += [f"## {title} (`{b}` [sdk])", ""]
        rows = []
        for reg in regs:
            def g(c, m, reg=reg, b=b):
                return get(idx, b, "sdk", reg, c, m)
            r0 = next(r for k, r in idx.items() if k[0] == b and k[2] == reg)
            lab = r0["label"]
            if b == "sha256chain":
                rows.append((lab, [f"cycles/{unit}"],
                             lambda c, m, g=g: fmt(cyc(g(c, m)) / g(c, m)["iterations"], 1) if g(c, m) else "-"))
            else:
                rows.append((lab, ["cycles/byte"],
                             lambda c, m, g=g: fmt(cyc(g(c, m)) / (g(c, m)["iterations"] * 1024), 2)
                             if g(c, m) else "-"))
            rows.append((lab, ["bytes/cycle"],
                         lambda c, m, g=g: fmt(g(c, m)["iterations"] * g(c, m)["bytes_per_iteration"] / cyc(g(c, m)), 4)
                         if g(c, m) else "-"))
            if r0.get("baseline_region") is not None:
                def sp(c, m, g=g, b=b, base=r0["baseline_region"]):
                    r, br = g(c, m), get(idx, b, "sdk", base, c, m)
                    return fmt(cyc(br) / cyc(r), 2) + "x" if r and br else "-"
                rows.append((lab, ["speedup vs plain C"], sp))
        out += table(idx, cols, rows, first="Implementation", extra_names=("Quantity",))

    # Kernels.
    kmeta = next((d["meta"]["benches"].get("kernels") for d in sets.values()
                  if "kernels" in d["meta"]["benches"]), None)
    if kmeta:
        out += ["## Kernels: cycles per call (`kernels`, 4 calls per region)", "",
                "C = portable C (`scalar` image: no V, -O2; `autovec` image: V at -O3, GCC "
                "auto-vectorization). RVV = intrinsics (`scalar` image).", ""]
        rows = []
        for k in kmeta["kernels"]:
            base = 10 * k["id"]
            impls = [("C scalar", "scalar", base), ("C autovec", "autovec", base),
                     ("RVV", "scalar", base + 1)]
            if (("kernels", "scalar", base + 2, cols[0][0], cols[0][1]) in idx):
                impls.append(("RVV-e8", "scalar", base + 2))
            for name, v, reg in impls:
                def g(c, m, v=v, reg=reg):
                    return get(idx, "kernels", v, reg, c, m)
                rows.append((k["name"], [name], lambda c, m, g=g: fmt(cyc(g(c, m)) / g(c, m)["iterations"], 0)
                             if g(c, m) else "-"))
        out += table(idx, cols, rows, first="Kernel", extra_names=("Implementation",))
        out += ["## Kernels: speedup over scalar C (same configuration and memory model)", "",
                "RVV and RVV-e8 against the C region of the same (`scalar`) image; autovec = "
                "the `autovec` image's C region against the `scalar` image's.", ""]
        rows = []
        for k in kmeta["kernels"]:
            base = 10 * k["id"]
            impls = [("RVV", "scalar", base + 1), ("autovec C", "autovec", base)]
            if (("kernels", "scalar", base + 2, cols[0][0], cols[0][1]) in idx):
                impls.insert(1, ("RVV-e8", "scalar", base + 2))
            for name, v, reg in impls:
                def sp(c, m, v=v, reg=reg, base=base):
                    r, b0 = get(idx, "kernels", v, reg, c, m), get(idx, "kernels", "scalar", base, c, m)
                    return fmt(cyc(b0) / cyc(r), 2) + "x" if r and b0 else "-"
                rows.append((k["name"], [name], sp))
        out += table(idx, cols, rows, first="Kernel", extra_names=("Implementation",))

    # Micro benchmarks: cycles/op net of the window region.
    micro = sorted({k[0] for k in idx if k[0].startswith("micro_")})
    if micro:
        out += ["## Micro benchmarks: cycles per operation, net of the empty window", "",
                "(region cycles - `empty` region cycles) / operations, same simulation "
                "(`docs/PERFORMANCE.md` §7).", ""]
        rows = []
        for b in micro:
            regs = sorted({k[2] for k in idx if k[0] == b})
            for reg in regs:
                r0 = next(r for k, r in idx.items() if k[0] == b and k[2] == reg)
                win = r0.get("window_region")
                if reg == win:
                    continue
                def n(c, m, b=b, reg=reg, win=win):
                    r, w = get(idx, b, "default", reg, c, m), get(idx, b, "default", win, c, m)
                    return fmt((cyc(r) - cyc(w)) / r["iterations"], 3) if r and w else "-"
                rows.append((f"{b} {r0['label']}", [], n))
        out += table(idx, cols, rows, first="Region")
    return out


def breakdown(idx, cols):
    """Per-cycle accounting and main events of the headline regions."""
    sel = [k for k in sorted(idx, key=lambda k: (k[0], k[1], k[2], CONFIGS.index(k[3]), MEMS.index(k[4])))
           if k[0] in ("dhrystone", "coremark", "sha256chain", "sha256chain_bulk")]
    used = [s for s in STK if any(idx[k]["counters"].get("stk_" + s, 0) for k in sel)]
    out = ["## Where the cycles go: headline regions (% of the region's cycles)", "",
           "| Run | " + " | ".join(used) + " |", "|---|" + "---:|" * len(used)]
    for k in sel:
        c = idx[k]["counters"]
        lab = f"{k[0]}[{k[1]}] {'' if idx[k]['label'] == 'main' else idx[k]['label'] + ' '}{k[3]}/{k[4]}"
        out.append(f"| {lab} | " + " | ".join(f"{100.0 * c.get('stk_' + s, 0) / c['cycles']:.1f}"
                                            for s in used) + " |")
    out += ["", "Columns: the `stk_*` categories of `docs/PERFORMANCE.md` §3 (they sum to 100%).", ""]
    ev = [("instret", lambda c: f"{c['instret']:,}"),
          ("IPC", lambda c: f"{c['instret'] / c['cycles']:.3f}"),
          ("ld/st/br %", lambda c: f"{100 * c['ret_load'] / c['instret']:.1f}/"
                                   f"{100 * c['ret_store'] / c['instret']:.1f}/"
                                   f"{100 * c['ret_branch'] / c['instret']:.1f}"),
          ("rvc %", lambda c: f"{100 * c['ret_rvc'] / c['instret']:.1f}"),
          ("taken %", lambda c: f"{100 * c['br_taken'] / c['ret_branch']:.1f}" if c["ret_branch"] else "-"),
          ("I$ miss", lambda c: f"{c['ic_miss']:,}"),
          ("I$ miss pen", lambda c: f"{c['ic_miss_cyc'] / c['ic_miss']:.1f}" if c["ic_miss"] else "-"),
          ("D$ ld/st", lambda c: f"{c['dc_load']:,}/{c['dc_store']:,}"),
          ("D$ miss", lambda c: f"{c['dc_miss']:,}"),
          ("D$ miss pen", lambda c: f"{c['dc_miss_cyc'] / c['dc_miss']:.1f}" if c["dc_miss"] else "-"),
          ("D$ wb", lambda c: f"{c['bus_dwb']:,}"),
          ("D unc", lambda c: f"{c['dc_unc']:,}"),
          ("bus %", lambda c: f"{100 * c['bus_busy_cyc'] / c['cycles']:.1f}")]
    out += ["## Events: headline regions", "",
            "| Run | " + " | ".join(n for n, _ in ev) + " |", "|---|" + "---:|" * len(ev)]
    for k in sel:
        c = idx[k]["counters"]
        lab = f"{k[0]}[{k[1]}] {'' if idx[k]['label'] == 'main' else idx[k]['label'] + ' '}{k[3]}/{k[4]}"
        out.append(f"| {lab} | " + " | ".join(f(c) for _, f in ev) + " |")
    out += ["", "Miss penalty = cycles with a miss outstanding / misses (`ic_miss_cyc / ic_miss`, "
            "`dc_miss_cyc / dc_miss`); `D unc` = uncached data accesses (UART, CLINT, accelerator); "
            "bus % = memory bus busy cycles.", ""]
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("out")
    ap.add_argument("--md")
    ap.add_argument("--merged")
    a = ap.parse_args()
    sets = load_sets(a.out)
    lines, ok = check(sets)
    idx = index(sets)
    cols = columns(sets)
    meta = next(iter(sets.values()))["meta"]
    text = ["# #56 baseline: headline tables across configurations", "",
            f"Generated by `baseline_tables.py` from {', '.join(f'`{c}/results.json`' for c in sets)}. "
            "Every number is from the simulation counters over the measured region, first repeat "
            "(the second is identical). Columns: configuration / memory model "
            "(`docs/PERFORMANCE.md` §4).", "",
            f"- Simulator: {meta['verilator']}; compiler: {meta['compiler']}; host: {meta['host']}",
            f"- Memory models: soc `{meta['mem_args']['soc']}`; axi `{meta['mem_args']['axi']}`", "",
            "## Checks", ""] + lines + [f"- Overall: {'PASS' if ok else 'FAIL'}", ""]
    text += headline(sets, idx, cols)
    text += breakdown(idx, cols)
    md = "\n".join(text) + "\n"
    if a.md:
        with open(a.md, "w") as f:
            f.write(md)
    else:
        sys.stdout.write(md)
    if a.merged:
        merged = {"meta": dict(meta), "runs": [], "failed": []}
        merged["meta"]["runs"] = []
        for d in sets.values():
            merged["runs"] += d["runs"]
            merged["failed"] += d.get("failed", [])
            merged["meta"]["runs"] += d["meta"]["runs"]
        with open(a.merged, "w") as f:
            json.dump(merged, f)
    print(f"baseline_tables: checks {'PASS' if ok else 'FAIL'}", file=sys.stderr)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
