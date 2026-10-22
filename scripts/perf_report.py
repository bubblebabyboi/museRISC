#!/usr/bin/env python3
"""Performance harness report (issue #56, docs/PERFORMANCE.md).

  perf_report.py RESULTS [--csv OUT.csv] [--md OUT.md] [--clock-mhz "62.5 100"]
      Tables from one result set (results.json written by perf_run.py,
      or the directory holding it): cycles, instret, IPC, the per-bench
      metrics (DMIPS/MHz, CoreMark/MHz, bytes/cycle, work/cycle), cycles
      per iteration net of the bench's window region, speedups over a
      baseline region, where the cycles go (the per-cycle accounting),
      cache/bus/instruction-mix events and, with --clock-mhz, the
      throughput projected at those clocks. CSV: one row per run with
      every counter. With more than WIDE_RUNS runs the accounting and
      event tables list one run per row instead of one per column.
  perf_report.py --diff A B [--md OUT.md]
      Compares two result sets run by run (same bench, variant, region,
      memory model and configuration; first repeat): cycles, IPC and
      metric changes, and the accounting categories that moved.

Without --md the markdown goes to stdout.
"""

import argparse
import csv
import json
import os
import sys

VAX_DHRYSTONES_PER_S = 1757  # VAX 11/780 = 1 DMIPS
WIDE_RUNS = 8  # more runs than this: one row per run in the wide tables

# Per-cycle accounting categories (sigil_perf.svh), in report order.
STACK = [
    ("stk_retire", "retire (base)"),
    ("stk_fetch_lat", "fetch: I$ hit latency / issue gap"),
    ("stk_fetch_straddle", "fetch: 32-bit instr straddles a word"),
    ("stk_fetch_miss", "fetch: I$ miss"),
    ("stk_fetch_unc", "fetch: uncached"),
    ("stk_fetch_itlb", "fetch: ITLB walk"),
    ("stk_branch", "squashed: taken branch"),
    ("stk_jal", "squashed: jal"),
    ("stk_jalr", "squashed: jalr"),
    ("stk_serial", "serialize: xRET/FENCE.I/SFENCE"),
    ("stk_loaduse", "load-use interlock"),
    ("stk_muldiv", "EX: M unit (mul/div)"),
    ("stk_fpu", "EX: FPU"),
    ("stk_vec", "EX: vector unit"),
    ("stk_dc_lat", "MEM: D$ hit latency"),
    ("stk_dc_miss", "MEM: D$ miss"),
    ("stk_io", "MEM: uncached device access"),
    ("stk_dc_clean", "MEM: FENCE.I D$ clean"),
    ("stk_dtlb", "MEM: DTLB walk"),
    ("stk_vls", "MEM: vector load/store"),
    ("stk_trap", "trap"),
    ("stk_other", "other (reset/halt)"),
]
RET = ["alu", "load", "store", "amo", "branch", "jal", "jalr", "mul", "div",
       "fp", "vec", "vls", "vset", "csr", "fence", "system"]


def load(path):
    if os.path.isdir(path):
        path = os.path.join(path, "results.json")
    with open(path) as f:
        return json.load(f)


def metrics(r):
    c = r["counters"]
    cyc, ins, it = c["cycles"], c["instret"], r["iterations"]
    m = {"ipc": ins / cyc if cyc else 0.0, "cpi": cyc / ins if ins else 0.0,
         "cycles_per_iter": cyc / it if it else 0.0}
    if "dmips_per_mhz" in r["metrics"]:
        m["dmips_per_mhz"] = it * 1e6 / cyc / VAX_DHRYSTONES_PER_S
    if "coremark_per_mhz" in r["metrics"]:
        m["coremark_per_mhz"] = it * 1e6 / cyc
    if "bytes_per_cycle" in r["metrics"] and r.get("bytes_per_iteration"):
        m["bytes_per_cycle"] = it * r["bytes_per_iteration"] / cyc
    if r.get("work_per_iteration"):
        m["work_per_cycle"] = it * r["work_per_iteration"] / cyc
        m["cycles_per_work"] = cyc / (it * r["work_per_iteration"])
        m["work_unit"] = r.get("work_unit", "")
    return m


def run_key(r):
    """(bench, variant, mem, config, rep): the runs of one simulation."""
    return (r["bench"], r["variant"], r["mem"], r["config"], r["rep"])


def by_region(runs):
    return {run_key(r) + (r["region"],): r for r in runs}


def net_cycles_per_iter(r, index):
    """Cycles per iteration net of the bench's window region (the cost of
    an empty measurement window in the same simulation), or None."""
    win = r.get("window_region")
    if win is None or r["region"] == win:
        return None
    w = index.get(run_key(r) + (win,))
    if not w or not r["iterations"]:
        return None
    return (r["counters"]["cycles"] - w["counters"]["cycles"]) / r["iterations"]


def speedup(r, index):
    """Baseline region cycles / this region's cycles (same simulation), or None."""
    base = r.get("baseline_region")
    if base is None:
        return None
    b = index.get(run_key(r) + (base,))
    if not b or not r["counters"]["cycles"]:
        return None
    return b["counters"]["cycles"] / r["counters"]["cycles"]


def metric_text(m):
    out = []
    if "dmips_per_mhz" in m:
        out.append(f"{m['dmips_per_mhz']:.3f} DMIPS/MHz")
    if "coremark_per_mhz" in m:
        out.append(f"{m['coremark_per_mhz']:.3f} CoreMark/MHz")
    if "bytes_per_cycle" in m:
        out.append(f"{m['bytes_per_cycle']:.4f} B/cycle")
    if "work_per_cycle" in m:
        out.append(f"{m['work_per_cycle']:.4f} {m['work_unit']}/cycle")
    return ", ".join(out) or "-"


def cyc_iter(v):
    return f"{v:,.2f}"


def key(r):
    return (r["bench"], r["variant"], r["region"], r["mem"], r["config"])


def label(r, short=False):
    reg = "" if r["label"] == "main" else f" {r['label']}"
    if short:
        return f"{r['bench']}[{r['variant']}]{reg} {r['config']}/{r['mem']}"
    return f"{r['bench']} [{r['variant']}]{reg}, {r['config']}, {r['mem']}"


CONFIG_ORDER = ("default", "sky130", "oreg", "fpga")


def order(k):
    """Sort key: bench, variant, region, configuration, memory model."""
    cfg = CONFIG_ORDER.index(k[4]) if k[4] in CONFIG_ORDER else len(CONFIG_ORDER)
    return (k[0], k[1], k[2], cfg, k[3])


def first_reps(data):
    """The first repeat of every run (repeats are identical when the
    determinism check passed)."""
    seen = {}
    for r in sorted(data["runs"], key=lambda r: (key(r), r["rep"])):
        seen.setdefault(key(r), r)
    return [seen[k] for k in sorted(seen, key=order)]


def write_csv(data, path):
    runs = sorted(data["runs"], key=lambda r: (key(r), r["rep"]))
    if not runs:
        return
    index = by_region(runs)
    ckeys = sorted({k for r in runs for k in r["counters"]})
    mkeys = sorted({k for r in runs for k in metrics(r) if k != "work_unit"})
    head = (["bench", "variant", "region", "label", "config", "mem", "rep",
             "iterations"] + mkeys + ["work_unit", "net_cycles_per_iter", "speedup",
                                      "hw_cycles", "hw_instret", "bin_sha256"] + ckeys)
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(head)
        for r in runs:
            m = metrics(r)
            net, sp = net_cycles_per_iter(r, index), speedup(r, index)
            w.writerow([r["bench"], r["variant"], r["region"], r["label"], r["config"],
                        r["mem"], r["rep"], r["iterations"]] +
                       [f"{m[k]:.6f}" if k in m else "" for k in mkeys] +
                       [m.get("work_unit", ""), "" if net is None else f"{net:.6f}",
                        "" if sp is None else f"{sp:.6f}"] +
                       [r["hw_cycles"], r["hw_instret"], r["bin_sha256"]] +
                       [r["counters"].get(k, "") for k in ckeys])


def pct(a, b):
    return f"{100.0 * a / b:.1f}" if b else "-"


def grid(out, rows, runs, corner="Category"):
    """One table over runs: one column per run when there are at most
    WIDE_RUNS of them, otherwise one row per run (rows are (name, short
    name, fn(run) -> str); the short name heads the column)."""
    if len(runs) <= WIDE_RUNS:
        out += [f"| {corner} | " + " | ".join(label(r, short=True) for r in runs) + " |",
                "|---|" + "---:|" * len(runs)]
        for name, _, fn in rows:
            out.append(f"| {name} | " + " | ".join(fn(r) for r in runs) + " |")
    else:
        out += ["| Run | " + " | ".join(short for _, short, _ in rows) + " |",
                "|---|" + "---:|" * len(rows)]
        for r in runs:
            out.append(f"| {label(r, short=True)} | " + " | ".join(fn(r) for _, _, fn in rows) + " |")
        out += ["", "Columns: " + "; ".join(f"`{short}` = {name}" for name, short, _ in rows) + "."]
    out.append("")


def markdown(data, clocks=()):
    meta, runs = data["meta"], first_reps(data)
    index = by_region(first_reps(data))
    out = ["# Sigil performance report", ""]
    out.append(f"- Date (UTC): {meta['date_utc']}")
    out.append(f"- Commit: `{meta['git_head']}` ({meta['git_branch']}"
               f"{', uncommitted changes' if meta['git_dirty'] else ''}); "
               f"merge-base with main `{meta['git_base_main'][:12]}`; rtl/ tree `{meta['rtl_tree'][:12]}`")
    out.append(f"- Simulator: {meta['verilator']}; compiler: {meta['compiler']}")
    out.append(f"- Host: {meta['host']}")
    for mem, args in meta["mem_args"].items():
        if any(r["mem"] == mem for r in meta["runs"]):
            out.append(f"- Memory model `{mem}`: `{args}`")
    for k, text in (("iterations_override", "iterations overridden (ITER)"),
                    ("max_cycles_override", "cycle limit overridden (MAX_CYCLES)"),
                    ("variants_selected", "variants selected (VARIANTS)")):
        if meta.get(k):
            out.append(f"- {text}: {meta[k] if not isinstance(meta[k], list) else ' '.join(meta[k])}")
    det = meta.get("deterministic")
    out.append(f"- Repeats: {meta['repeat']}"
               + ("" if det is None else f"; deterministic: {'yes (identical counts)' if det else 'NO'}"))
    for name, img in sorted(meta["images"].items()):
        out.append(f"- Image `{name}`: sha256 `{img['bin_sha256'][:16]}`, "
                   f"{img.get('variant_description') or 'SDK flags'}")
    out.append("")
    if data.get("failed"):
        out.append(f"**{len(data['failed'])} run(s) failed validation and are not tabulated.**")
        out.append("")
    if not runs:
        return "\n".join(out) + "\n"

    out += ["## Configurations (as reported by the counter records)", "",
            "| Config | Memory | Testbench | I$ sets x ways x line | D$ sets x ways x line | SRAM_OREG | VRF_OREG | L1 on |",
            "|---|---|---|---|---|---:|---:|---:|"]
    seen = set()
    for r in runs:
        c = r["counters"]
        k = (r["config"], r["mem"])
        if k in seen:
            continue
        seen.add(k)
        out.append(f"| {r['config']} | {r['mem']} | `{os.path.basename(r['tb'])}` | {c.get('cfg_ic')} | "
                   f"{c.get('cfg_dc')} | {c.get('cfg_sram_oreg')} | {c.get('cfg_vrf_oreg')} | "
                   f"{c.get('cfg_cache_en')} |")
    out.append("")
    has_net = any(r.get("window_region") is not None for r in runs)
    out += ["## Summary", "",
            "| Benchmark | Config | Memory | Iterations | Cycles | Instret | IPC | CPI | Cycles/iter | "
            + ("Net cycles/iter | " if has_net else "") + "Metric | HW-counter cycles |",
            "|---|---|---|---:|---:|---:|---:|---:|---:|" + ("---:|" if has_net else "") + "---|---:|"]
    for r in runs:
        c, m = r["counters"], metrics(r)
        net = ""
        if has_net:
            n = net_cycles_per_iter(r, index)
            net = ("(window) | " if r.get("window_region") == r["region"]
                   else ("- | " if n is None else f"{cyc_iter(n)} | "))
        out.append(f"| {r['bench']} [{r['variant']}]{'' if r['label'] == 'main' else ' ' + r['label']} "
                   f"| {r['config']} | {r['mem']} | {r['iterations']} | {c['cycles']:,} | "
                   f"{c['instret']:,} | {m['ipc']:.3f} | {m['cpi']:.3f} | "
                   f"{cyc_iter(m['cycles_per_iter'])} | {net}{metric_text(m)} | {r['hw_cycles']:,} |")
    out.append("")
    if has_net:
        out += ["Net cycles/iter: the region's cycles minus those of the bench's window "
                "region (an empty measurement window, `(window)`) in the same simulation, "
                "divided by the iterations.", ""]

    sp = [(r, speedup(r, index)) for r in runs]
    sp = [(r, s) for r, s in sp if s is not None]
    if sp:
        out += ["## Speedups over the baseline region (same image, configuration and memory)", "",
                "| Run | Baseline region | Baseline cycles | Cycles | Speedup |",
                "|---|---|---:|---:|---:|"]
        for r, s in sp:
            b = index[run_key(r) + (r["baseline_region"],)]
            out.append(f"| {label(r, short=True)} | {b['region']} {b['label']} | "
                       f"{b['counters']['cycles']:,} | {r['counters']['cycles']:,} | {s:.2f}x |")
        out.append("")

    if clocks:
        out += ["## Projected throughput at a given clock (simulation cycles; not a hardware measurement)", "",
                "| Run | " + " | ".join(f"Iter/s @ {c:g} MHz" for c in clocks) + " | "
                + " | ".join(f"Work/s @ {c:g} MHz" for c in clocks) + " |",
                "|---|" + "---:|" * (2 * len(clocks))]
        for r in runs:
            cyc, it, m = r["counters"]["cycles"], r["iterations"], metrics(r)
            ips = [it * c * 1e6 / cyc for c in clocks]
            work = []
            for c in clocks:
                if "bytes_per_cycle" in m:
                    work.append(f"{m['bytes_per_cycle'] * c:,.2f} MB/s")
                elif "work_per_cycle" in m:
                    work.append(f"{m['work_per_cycle'] * c * 1e6:,.0f} {m['work_unit']}/s")
                else:
                    work.append("-")
            out.append(f"| {label(r, short=True)} | " + " | ".join(f"{v:,.1f}" for v in ips)
                       + " | " + " | ".join(work) + " |")
        out.append("")

    used = [(k, t) for k, t in STACK if any(r["counters"].get(k, 0) for r in runs)]
    out += ["## Where the cycles go (% of cycles in the measured region)", ""]
    grid(out, [(t, k[4:], lambda r, k=k: pct(r["counters"].get(k, 0), r["counters"]["cycles"]))
               for k, t in used], runs)

    def ev(name, short, fn):
        def cell(r):
            try:
                return fn(r["counters"])
            except ZeroDivisionError:
                return "-"
        return (name, short, cell)

    rows = []
    for cls in RET:
        if any(r["counters"].get("ret_" + cls, 0) for r in runs):
            rows.append(ev(f"retired {cls} (% of instret)", f"{cls} %",
                           lambda c, cls=cls: pct(c["ret_" + cls], c["instret"])))
    rows += [
        ev("compressed (RVC, % of instret)", "rvc %", lambda c: pct(c["ret_rvc"], c["instret"])),
        ev("taken branches (% of branches)", "taken %", lambda c: pct(c["br_taken"], c["ret_branch"])),
        ev("redirects per 1000 instr", "redir/ki",
           lambda c: f"{1000.0 * (c['br_taken'] + c['jal_redir'] + c['jalr_redir'] + c['xret_flush'] + c['fencei_flush'] + c['sfence_flush']) / c['instret']:.1f}"),
        ev("squashed wrong-path instr", "squashed", lambda c: f"{c['squash_id'] + c['squash_if']:,}"),
        ev("I$ fetch accesses per instr", "I$ acc/i", lambda c: f"{c['ic_access'] / c['instret']:.3f}"),
        ev("I$ misses (per 1000 instr)", "I$ miss (/ki)",
           lambda c: f"{c['ic_miss']:,} ({1000.0 * c['ic_miss'] / c['instret']:.3f})"),
        # Hits are derived: an uncached access never looks up the
        # arrays, and every lookup that misses is counted once.
        ev("I$ hits (% of cacheable fetches)", "I$ hit (%)",
           lambda c: f"{c['ic_access'] - c['ic_miss'] - c['ic_unc']:,} "
                     f"({pct(c['ic_access'] - c['ic_miss'] - c['ic_unc'], c['ic_access'] - c['ic_unc'])})"),
        ev("I$ miss-outstanding cycles (% of cycles)", "I$ miss cyc %",
           lambda c: pct(c["ic_miss_cyc"], c["cycles"])),
        ev("D$ loads / stores", "D$ ld / st", lambda c: f"{c['dc_load']:,} / {c['dc_store']:,}"),
        ev("D$ misses (% of accesses)", "D$ miss (%)",
           lambda c: f"{c['dc_miss']:,} ({pct(c['dc_miss'], c['dc_load'] + c['dc_store'])})"),
        ev("D$ hits (% of cacheable accesses)", "D$ hit (%)",
           lambda c: f"{c['dc_load'] + c['dc_store'] - c['dc_miss'] - c['dc_unc']:,} "
                     f"({pct(c['dc_load'] + c['dc_store'] - c['dc_miss'] - c['dc_unc'], c['dc_load'] + c['dc_store'] - c['dc_unc'])})"),
        ev("D$ miss-outstanding cycles (% of cycles)", "D$ miss cyc %",
           lambda c: pct(c["dc_miss_cyc"], c["cycles"])),
        ev("D$ write-backs", "D$ wb", lambda c: f"{c['bus_dwb']:,}"),
        ev("uncached D accesses", "D unc", lambda c: f"{c['dc_unc']:,}"),
        ev("bus transactions (I fill / D fill / D wb / uncached)", "bus if/df/wb/unc",
           lambda c: f"{c['bus_ifill']}/{c['bus_dfill']}/{c['bus_dwb']}/{c['bus_iunc'] + c['bus_dunc']}"),
        ev("bus busy (% of cycles)", "bus %", lambda c: pct(c["bus_busy_cyc"], c["cycles"])),
        ev("bus waiting on memory (% of cycles)", "bus wait %",
           lambda c: pct(c["bus_rsp_wait"] + c["bus_req_wait"], c["cycles"])),
        ev("M unit busy (% of cycles)", "M %", lambda c: pct(c["muldiv_busy"], c["cycles"])),
        ev("FPU busy (% of cycles)", "FPU %", lambda c: pct(c["fpu_busy"], c["cycles"])),
        ev("vector unit busy (% of cycles)", "vec %", lambda c: pct(c["vec_busy"], c["cycles"])),
        ev("vector LS in MEM (% of cycles)", "vls %", lambda c: pct(c["vls_cyc"], c["cycles"])),
        ev("traps (exceptions / interrupts)", "traps", lambda c: f"{c['trap_exc']} / {c['trap_irq']}"),
    ]
    out += ["## Events", ""]
    grid(out, rows, runs, corner="Event")
    return "\n".join(out) + "\n"


def diff(a, b):
    ra = {key(r): r for r in first_reps(a)}
    rb = {key(r): r for r in first_reps(b)}
    common = [k for k in ra if k in rb]
    out = ["# Sigil performance diff", "",
           f"- A: `{a['meta']['git_head'][:12]}` {a['meta']['date_utc']}",
           f"- B: `{b['meta']['git_head'][:12]}` {b['meta']['date_utc']}", ""]
    only = sorted(set(ra) ^ set(rb))
    if only:
        out.append("Runs in only one set: " + ", ".join(
            f"{label(ra.get(k) or rb.get(k), short=True)} ({'A' if k in ra else 'B'})" for k in only))
        out.append("")
    if not common:
        return "\n".join(out + ["No common runs."]) + "\n"
    out += ["| Run | Cycles A | Cycles B | Change | IPC A | IPC B | Metric A | Metric B |",
            "|---|---:|---:|---:|---:|---:|---|---|"]
    for k in common:
        x, y = ra[k], rb[k]
        mx, my = metrics(x), metrics(y)
        cx, cy = x["counters"]["cycles"], y["counters"]["cycles"]
        out.append(f"| {label(x, short=True)} | {cx:,} | {cy:,} | {100.0 * (cy - cx) / cx:+.2f}% | "
                   f"{mx['ipc']:.3f} | {my['ipc']:.3f} | {metric_text(mx)} | {metric_text(my)} |")
    out.append("")
    out += ["## Accounting categories that moved (cycles B - A, and share of A's cycles)", ""]
    for k in common:
        x, y = ra[k]["counters"], rb[k]["counters"]
        moved = [(t, y.get(s, 0) - x.get(s, 0)) for s, t in STACK if y.get(s, 0) != x.get(s, 0)]
        out.append(f"- {label(ra[k], short=True)}: " + (", ".join(
            f"{t} {d:+,} ({100.0 * d / x['cycles']:+.1f} pp)" for t, d in moved) or "no change"))
    out.append("")
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("results", nargs="?")
    ap.add_argument("--diff", nargs=2, metavar=("A", "B"))
    ap.add_argument("--csv")
    ap.add_argument("--md")
    ap.add_argument("--clock-mhz", default="",
                    help="clocks in MHz for the projected-throughput table, e.g. \"62.5 100\"")
    a = ap.parse_args()
    try:
        clocks = [float(c) for c in a.clock_mhz.split()]
    except ValueError:
        ap.error(f"bad --clock-mhz {a.clock_mhz!r}")
    if a.diff:
        text = diff(load(a.diff[0]), load(a.diff[1]))
    elif a.results:
        data = load(a.results)
        if a.csv:
            write_csv(data, a.csv)
        text = markdown(data, clocks)
    else:
        ap.error("RESULTS or --diff A B required")
    if a.md:
        with open(a.md, "w") as f:
            f.write(text)
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
