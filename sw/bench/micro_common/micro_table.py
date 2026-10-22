#!/usr/bin/env python3
"""Per-operation tables for the micro_* benchmarks (README.md here).

  micro_table.py RESULTS [--md OUT.md]

RESULTS is a results.json written by `make -C sim perf` (or the
directory holding it). Only runs that passed validation are in its
"runs" list; this script reads those (the first repeat of each run) and
prints, per micro benchmark, one row per region:

  - cycles per operation for every configuration / memory model run
    (= the harness's cycles/iteration: every region runs exactly
    "iterations" operations);
  - instructions per operation and where the cycles go, per operation
    (the stk_* accounting of the first run, categories >= 0.05);
  - the L1 events per operation (I$/D$ misses, write-backs).

It then derives the cache parameters the sweeps show (miss penalties,
the largest working set / code footprint that still hits).
"""

import argparse
import json
import os
import sys

STK = ["retire", "fetch_lat", "fetch_straddle", "fetch_miss", "fetch_unc", "fetch_itlb",
       "branch", "jal", "jalr", "serial", "loaduse", "muldiv", "fpu", "vec", "dc_lat",
       "dc_miss", "io", "dc_clean", "dtlb", "vls", "trap", "other"]
ORDER = {"default": 0, "sky130": 1, "oreg": 2, "fpga": 3}


def load(path):
    if os.path.isdir(path):
        path = os.path.join(path, "results.json")
    with open(path) as f:
        return json.load(f)


def first_reps(data):
    seen = {}
    for r in sorted(data["runs"], key=lambda r: r["rep"]):
        seen.setdefault((r["bench"], r["variant"], r["region"], r["config"], r["mem"]), r)
    return list(seen.values())


def runs_key(r):
    return (ORDER.get(r["config"], 9), r["config"], r["mem"] != "soc", r["mem"])


def fmt(x, nd=3):
    return f"{x:,.{nd}f}"


def bench_table(name, meta, runs):
    notes = meta.get("region_ops", {})
    combos = sorted({(r["config"], r["mem"]) for r in runs},
                    key=lambda cm: (ORDER.get(cm[0], 9), cm[0], cm[1] != "soc", cm[1]))
    by = {(r["region"], r["config"], r["mem"]): r for r in runs}
    regions = sorted({r["region"] for r in runs})
    ref = combos[0]
    out = [f"### {name}", "", meta.get("description", ""), "",
           f"Operations per region: {runs[0]['iterations']:,}. "
           f"Breakdown and events per operation from {ref[0]}/{ref[1]}.", ""]
    head = (["Region", "One operation"] + [f"cycles/op {c}/{m}" for c, m in combos]
            + ["instr/op", f"where the cycles go per op ({ref[0]}/{ref[1]})",
               "I$ miss/op", "D$ miss/op"])
    out.append("| " + " | ".join(head) + " |")
    out.append("|---|---|" + "---:|" * len(combos) + "---:|---|---:|---:|")
    for rid in regions:
        base = by.get((rid, ref[0], ref[1]))
        if base is None:
            continue
        label = base["label"]
        ops = base["iterations"]
        c = base["counters"]
        if label == "empty":
            cells = [f"{by[(rid, cm[0], cm[1])]['counters']['cycles']} cycles"
                     if (rid, cm[0], cm[1]) in by else "-" for cm in combos]
            out.append(f"| {label} | {notes.get(str(rid), '')} | " + " | ".join(cells)
                       + f" | {c['instret']} instr | (window overhead, not per op) | "
                       f"{c['ic_miss']} | {c['dc_miss']} |")
            continue
        cells = []
        for cm in combos:
            r = by.get((rid, cm[0], cm[1]))
            cells.append(fmt(r["counters"]["cycles"] / r["iterations"]) if r else "-")
        stk = sorted(((c.get("stk_" + k, 0) / ops, k) for k in STK), reverse=True)
        where = ", ".join(f"{k} {v:.2f}" for v, k in stk if v >= 0.05)
        out.append(f"| {label} | {notes.get(str(rid), '')} | " + " | ".join(cells)
                   + f" | {c['instret'] / ops:.3f} | {where} | {c['ic_miss'] / ops:.4f} | "
                   f"{c['dc_miss'] / ops:.4f} |")
    out.append("")
    return out


def derived(runs):
    """Cache parameters from the sweeps, per configuration/memory model."""
    out = ["### Derived cache parameters", "",
           "| Config | Memory | D$ miss penalty (cycles, chase 256 KiB) | D$ load miss cost "
           "(cycles/op, chase 256 KiB - chase 1 KiB) | largest chase that hits (miss/op < 0.01) "
           "| I$ miss penalty (cycles, footprint 32 KiB) | largest footprint that hits "
           "(I$ miss/instr < 0.001) |",
           "|---|---|---:|---:|---:|---:|---:|"]
    combos = sorted({(r["config"], r["mem"]) for r in runs},
                    key=lambda cm: (ORDER.get(cm[0], 9), cm[0], cm[1] != "soc", cm[1]))
    for cfg, mem in combos:
        rs = {r["label"]: r for r in runs if r["config"] == cfg and r["mem"] == mem}
        cells = []
        big, small = rs.get("chase_rand_256k"), rs.get("chase_rand_1k")
        if big:
            c = big["counters"]
            cells.append(fmt(c["dc_miss_cyc"] / c["dc_miss"], 1) if c["dc_miss"] else "-")
        else:
            cells.append("-")
        if big and small:
            cells.append(fmt(big["counters"]["cycles"] / big["iterations"]
                             - small["counters"]["cycles"] / small["iterations"], 2))
        else:
            cells.append("-")
        hits = [int(l[len("chase_rand_"):-1]) for l, r in rs.items()
                if l.startswith("chase_rand_")
                and r["counters"]["dc_miss"] / r["iterations"] < 0.01]
        cells.append(f"{max(hits)} KiB" if hits else "-")
        foot = rs.get("ifoot_32k")
        if foot and foot["counters"]["ic_miss"]:
            c = foot["counters"]
            cells.append(fmt(c["ic_miss_cyc"] / c["ic_miss"], 1))
        else:
            cells.append("-")
        fh = [int(l[len("ifoot_"):-1]) for l, r in rs.items()
              if l.startswith("ifoot_") and r["counters"]["ic_miss"] / r["iterations"] < 0.001]
        cells.append(f"{max(fh)} KiB" if fh else "-")
        if any(x != "-" for x in cells):
            out.append(f"| {cfg} | {mem} | " + " | ".join(cells) + " |")
    out.append("")
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("results")
    ap.add_argument("--md")
    a = ap.parse_args()
    data = load(a.results)
    runs = [r for r in first_reps(data) if r["bench"].startswith("micro_")]
    if not runs:
        sys.exit("micro_table: no valid micro_* runs in " + a.results)
    meta = data["meta"]
    out = ["# Micro benchmarks: cycles per operation", "",
           f"- Date (UTC): {meta['date_utc']}; commit `{meta['git_head']}` "
           f"({meta['git_branch']}{', uncommitted changes' if meta['git_dirty'] else ''}); "
           f"rtl/ tree `{meta['rtl_tree'][:12]}`",
           f"- Simulator: {meta['verilator']}; compiler: {meta['compiler']}",
           f"- Repeats: {meta['repeat']}; deterministic: "
           f"{'-' if meta.get('deterministic') is None else ('yes' if meta['deterministic'] else 'NO')}",
           f"- Memory models: " + "; ".join(f"`{m}` {v}" for m, v in meta["mem_args"].items()), ""]
    if data.get("failed"):
        out += [f"**{len(data['failed'])} run(s) failed validation and are not tabulated.**", ""]
    for name in sorted({r["bench"] for r in runs}):
        br = [r for r in runs if r["bench"] == name]
        out += bench_table(name, meta["benches"].get(name, {}), br)
    out += derived(runs)
    text = "\n".join(out) + "\n"
    if a.md:
        with open(a.md, "w") as f:
            f.write(text)
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
