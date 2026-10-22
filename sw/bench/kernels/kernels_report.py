#!/usr/bin/env python3
"""Per-kernel table for the kernels benchmark, from a harness result set.

The harness (scripts/perf_report.py) reports every region on its own:
cycles, IPC, cycles/iteration and the cycle accounting. This script
pairs each kernel's regions (10*k + 0 = C, 1 = RVV, 2 = RVV-e8) and adds
the per-kernel work from bench.json's "kernels" list (carried into
results.json): work units per call, units per cycle, and the speedup of
each implementation over C. One iteration is one call, so
cycles/call = cycles / iterations.

  kernels_report.py <results.json | dir> [--md out.md] [--csv out.csv]

Only validated runs (results.json "runs") are used, rep 0 (the harness
already fails a result set whose repeats differ).
"""

import argparse
import csv
import json
import os
import sys

IMPLS = {0: "C", 1: "RVV", 2: "RVV-e8"}


def load(path):
    if os.path.isdir(path):
        path = os.path.join(path, "results.json")
    with open(path) as f:
        d = json.load(f)
    bench = d["meta"]["benches"].get("kernels")
    if not bench or "kernels" not in bench:
        sys.exit(f"{path}: no kernels benchmark (bench.json \"kernels\") in this result set")
    runs = {}
    for r in d["runs"]:
        if r["bench"] != "kernels" or r["rep"] != 0:
            continue
        runs[(r["variant"], r["mem"], r["config"], r["region"])] = r
    return d["meta"], bench, runs


def row(kern, runs, variant, mem, cfg):
    """Per-kernel numbers for one (variant, mem, config), or None."""
    out = {"variant": variant, "mem": mem, "config": cfg, "kernel": kern["name"],
           "units_per_call": kern["units"], "unit": kern["unit"]}
    have = False
    for impl, name in IMPLS.items():
        r = runs.get((variant, mem, cfg, 10 * kern["id"] + impl))
        if not r:
            continue
        have = True
        c = r["counters"]
        it = r["iterations"]
        cyc = c["cycles"]
        out[f"{name}_cycles_per_call"] = cyc / it
        out[f"{name}_units_per_cycle"] = kern["units"] * it / cyc
        out[f"{name}_ipc"] = c["instret"] / cyc
        out[f"{name}_instret_per_call"] = c["instret"] / it
        out[f"{name}_vls_pct"] = 100.0 * c.get("stk_vls", 0) / cyc
        out[f"{name}_vec_pct"] = 100.0 * c.get("stk_vec", 0) / cyc
        out[f"{name}_fpu_pct"] = 100.0 * c.get("stk_fpu", 0) / cyc
        # Vector load/store cycles per D$ access: each vector element
        # is one data-port access (the few scalar accesses in the
        # region are counted too, so this is a slight underestimate).
        acc = c.get("dc_load", 0) + c.get("dc_store", 0)
        out[f"{name}_vls_cyc_per_access"] = c.get("stk_vls", 0) / acc if acc else None
    if not have:
        return None
    for name in ("RVV", "RVV-e8"):
        if f"{name}_cycles_per_call" in out and "C_cycles_per_call" in out:
            out[f"{name}_speedup"] = out["C_cycles_per_call"] / out[f"{name}_cycles_per_call"]
    return out


def fmt(v, nd):
    return "" if v is None else f"{v:,.{nd}f}"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("results")
    ap.add_argument("--md")
    ap.add_argument("--csv")
    a = ap.parse_args()
    meta, bench, runs = load(a.results)
    kernels = bench["kernels"]
    keys = sorted({(v, m, c) for v, m, c, _ in runs})
    rows = [r for v, m, c in keys for k in kernels if (r := row(k, runs, v, m, c))]

    md = ["# Kernels: C vs RVV", "",
          f"- Date (UTC): {meta['date_utc']}; commit `{meta['git_head']}`; "
          f"rtl/ tree `{meta['rtl_tree'][:12]}`",
          f"- {meta['verilator']}; {meta['compiler']}",
          f"- {'/'.join(str(i) for i in sorted({r['iterations'] for r in runs.values()}))} "
          "calls per region; cycles are the simulation window (= mcycle delta)",
          "- Work units: elem = output element (dot products: element pair), "
          "byte, mac = multiply-accumulate", ""]
    for v in sorted({k[0] for k in keys}):
        desc = bench["variants"].get(v, {}).get("description", "")
        md.append(f"- Variant `{v}`: {desc}")
    md.append("")
    for v, m, c in keys:
        sel = [r for r in rows if (r["variant"], r["mem"], r["config"]) == (v, m, c)]
        md += [f"## {v} / {c} / {m}", "",
               "| Kernel | Work/call | C cyc/call | C units/cyc | C IPC | RVV cyc/call "
               "| RVV units/cyc | RVV speedup | RVV: vector LS % | RVV: vector unit % "
               "| RVV: LS cyc/access |",
               "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|"]
        for r in sel:
            md.append(
                f"| {r['kernel']} | {r['units_per_call']:,} {r['unit']} "
                f"| {fmt(r.get('C_cycles_per_call'), 1)} | {fmt(r.get('C_units_per_cycle'), 4)} "
                f"| {fmt(r.get('C_ipc'), 3)} | {fmt(r.get('RVV_cycles_per_call'), 1)} "
                f"| {fmt(r.get('RVV_units_per_cycle'), 4)} | {fmt(r.get('RVV_speedup'), 2)}x "
                f"| {fmt(r.get('RVV_vls_pct'), 1)} | {fmt(r.get('RVV_vec_pct'), 1)} "
                f"| {fmt(r.get('RVV_vls_cyc_per_access'), 2)} |")
            if "RVV-e8_cycles_per_call" in r:
                md.append(
                    f"| {r['kernel']} (RVV-e8) | {r['units_per_call']:,} {r['unit']} | | | "
                    f"| {fmt(r['RVV-e8_cycles_per_call'], 1)} | {fmt(r['RVV-e8_units_per_cycle'], 4)} "
                    f"| {fmt(r.get('RVV-e8_speedup'), 2)}x | {fmt(r['RVV-e8_vls_pct'], 1)} "
                    f"| {fmt(r['RVV-e8_vec_pct'], 1)} | {fmt(r.get('RVV-e8_vls_cyc_per_access'), 2)} |")
        md.append("")
    # Where the cycles go, one row per region (the harness's own table
    # has one column per region and run, too wide for 28 regions).
    for v, m, c in keys:
        regs = sorted((rid, r) for (vv, mm, cc, rid), r in runs.items() if (vv, mm, cc) == (v, m, c))
        cats = sorted({k for _, r in regs for k, x in r["counters"].items()
                       if k.startswith("stk_") and k != "stk_sum" and x})
        if not regs:
            continue
        md += [f"## Where the cycles go: {v} / {c} / {m} (% of region cycles)", "",
               "| Region | " + " | ".join(k[4:] for k in cats) + " |",
               "|---|" + "---:|" * len(cats)]
        for rid, r in regs:
            cyc = r["counters"]["cycles"]
            md.append(f"| {rid} {r['label']} | " + " | ".join(
                f"{100.0 * r['counters'].get(k, 0) / cyc:.1f}" for k in cats) + " |")
        md.append("")
    # GCC auto-vectorization: the autovec image's C against the scalar
    # image's C (and the RVV intrinsics, from the scalar image).
    for m, c in sorted({(m, c) for _, m, c in keys}):
        sc = {r["kernel"]: r for r in rows if (r["variant"], r["mem"], r["config"]) == ("scalar", m, c)}
        av = {r["kernel"]: r for r in rows if (r["variant"], r["mem"], r["config"]) == ("autovec", m, c)}
        if not sc or not av:
            continue
        md += [f"## GCC auto-vectorization vs intrinsics / {c} / {m}", "",
               "| Kernel | scalar C cyc/call | autovec C cyc/call | autovec speedup "
               "| RVV intrinsics speedup |", "|---|---:|---:|---:|---:|"]
        for k in kernels:
            s_, a_ = sc.get(k["name"]), av.get(k["name"])
            if not s_ or not a_:
                continue
            md.append(f"| {k['name']} | {fmt(s_['C_cycles_per_call'], 1)} "
                      f"| {fmt(a_['C_cycles_per_call'], 1)} "
                      f"| {fmt(s_['C_cycles_per_call'] / a_['C_cycles_per_call'], 2)}x "
                      f"| {fmt(s_.get('RVV_speedup'), 2)}x |")
        md.append("")
    text = "\n".join(md)
    if a.md:
        with open(a.md, "w") as f:
            f.write(text)
    else:
        print(text)
    if a.csv:
        cols = sorted({k for r in rows for k in r},
                      key=lambda k: (k not in ("variant", "mem", "config", "kernel",
                                               "units_per_call", "unit"), k))
        with open(a.csv, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=cols)
            w.writeheader()
            for r in rows:
                w.writerow({k: (f"{v:.6g}" if isinstance(v, float) else v) for k, v in r.items()})


if __name__ == "__main__":
    main()
