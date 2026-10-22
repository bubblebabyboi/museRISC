#!/usr/bin/env python3
"""Performance harness report (issue #56, docs/PERFORMANCE.md).

  perf_report.py RESULTS [--csv OUT.csv] [--md OUT.md]
      Tables from one result set (results.json written by perf_run.py,
      or the directory holding it): cycles, instret, IPC, the per-bench
      metrics (DMIPS/MHz, CoreMark/MHz, bytes/cycle), where the cycles
      go (the per-cycle accounting), and cache/bus/instruction-mix
      events. CSV: one row per run with every counter.
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
    if "bytes_per_cycle" in r["metrics"]:
        m["bytes_per_cycle"] = it * r["bytes_per_iteration"] / cyc
    return m


def metric_text(m):
    out = []
    if "dmips_per_mhz" in m:
        out.append(f"{m['dmips_per_mhz']:.3f} DMIPS/MHz")
    if "coremark_per_mhz" in m:
        out.append(f"{m['coremark_per_mhz']:.3f} CoreMark/MHz")
    if "bytes_per_cycle" in m:
        out.append(f"{m['bytes_per_cycle']:.4f} B/cycle")
    return ", ".join(out) or "-"


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
    ckeys = sorted({k for r in runs for k in r["counters"]})
    mkeys = sorted({k for r in runs for k in metrics(r)})
    head = (["bench", "variant", "region", "label", "config", "mem", "rep",
             "iterations"] + mkeys + ["hw_cycles", "hw_instret", "bin_sha256"] + ckeys)
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(head)
        for r in runs:
            m = metrics(r)
            w.writerow([r["bench"], r["variant"], r["region"], r["label"], r["config"],
                        r["mem"], r["rep"], r["iterations"]] +
                       [f"{m[k]:.6f}" if k in m else "" for k in mkeys] +
                       [r["hw_cycles"], r["hw_instret"], r["bin_sha256"]] +
                       [r["counters"].get(k, "") for k in ckeys])


def pct(a, b):
    return f"{100.0 * a / b:.1f}" if b else "-"


def markdown(data):
    meta, runs = data["meta"], first_reps(data)
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

    out += ["## Summary", "",
            "| Benchmark | Config | Memory | Iterations | Cycles | Instret | IPC | CPI | Cycles/iter | Metric | HW-counter cycles |",
            "|---|---|---|---:|---:|---:|---:|---:|---:|---|---:|"]
    for r in runs:
        c, m = r["counters"], metrics(r)
        out.append(f"| {r['bench']} [{r['variant']}]{'' if r['label'] == 'main' else ' ' + r['label']} "
                   f"| {r['config']} | {r['mem']} | {r['iterations']} | {c['cycles']:,} | "
                   f"{c['instret']:,} | {m['ipc']:.3f} | {m['cpi']:.3f} | "
                   f"{m['cycles_per_iter']:,.1f} | {metric_text(m)} | {r['hw_cycles']:,} |")
    out.append("")

    cols = [label(r, short=True) for r in runs]
    used = [(k, t) for k, t in STACK if any(r["counters"].get(k, 0) for r in runs)]
    out += ["## Where the cycles go (% of cycles in the measured region)", "",
            "| Category | " + " | ".join(cols) + " |",
            "|---|" + "---:|" * len(cols)]
    for k, t in used:
        out.append(f"| {t} | " + " | ".join(pct(r["counters"].get(k, 0), r["counters"]["cycles"])
                                            for r in runs) + " |")
    out.append("")

    def ev_row(name, fn):
        vals = []
        for r in runs:
            try:
                vals.append(fn(r["counters"]))
            except ZeroDivisionError:
                vals.append("-")
        out.append(f"| {name} | " + " | ".join(vals) + " |")

    out += ["## Events", "", "| Event | " + " | ".join(cols) + " |",
            "|---|" + "---:|" * len(cols)]
    for cls in RET:
        if any(r["counters"].get("ret_" + cls, 0) for r in runs):
            ev_row(f"retired {cls} (% of instret)",
                   lambda c, cls=cls: pct(c["ret_" + cls], c["instret"]))
    ev_row("compressed (RVC, % of instret)", lambda c: pct(c["ret_rvc"], c["instret"]))
    ev_row("taken branches (% of branches)", lambda c: pct(c["br_taken"], c["ret_branch"]))
    ev_row("redirects per 1000 instr",
           lambda c: f"{1000.0 * (c['br_taken'] + c['jal_redir'] + c['jalr_redir'] + c['xret_flush'] + c['fencei_flush'] + c['sfence_flush']) / c['instret']:.1f}")
    ev_row("squashed wrong-path instr", lambda c: f"{c['squash_id'] + c['squash_if']:,}")
    ev_row("I$ fetch accesses per instr", lambda c: f"{c['ic_access'] / c['instret']:.3f}")
    ev_row("I$ misses (per 1000 instr)", lambda c: f"{c['ic_miss']:,} ({1000.0 * c['ic_miss'] / c['instret']:.3f})")
    ev_row("D$ loads / stores", lambda c: f"{c['dc_load']:,} / {c['dc_store']:,}")
    ev_row("D$ misses (% of accesses)",
           lambda c: f"{c['dc_miss']:,} ({pct(c['dc_miss'], c['dc_load'] + c['dc_store'])})")
    ev_row("D$ write-backs", lambda c: f"{c['bus_dwb']:,}")
    ev_row("uncached D accesses", lambda c: f"{c['dc_unc']:,}")
    ev_row("bus transactions (I fill / D fill / D wb / uncached)",
           lambda c: f"{c['bus_ifill']}/{c['bus_dfill']}/{c['bus_dwb']}/{c['bus_iunc'] + c['bus_dunc']}")
    ev_row("bus busy (% of cycles)", lambda c: pct(c["bus_busy_cyc"], c["cycles"]))
    ev_row("bus waiting on memory (% of cycles)",
           lambda c: pct(c["bus_rsp_wait"] + c["bus_req_wait"], c["cycles"]))
    ev_row("M unit busy (% of cycles)", lambda c: pct(c["muldiv_busy"], c["cycles"]))
    ev_row("FPU busy (% of cycles)", lambda c: pct(c["fpu_busy"], c["cycles"]))
    ev_row("vector unit busy (% of cycles)", lambda c: pct(c["vec_busy"], c["cycles"]))
    ev_row("vector LS in MEM (% of cycles)", lambda c: pct(c["vls_cyc"], c["cycles"]))
    ev_row("traps (exceptions / interrupts)", lambda c: f"{c['trap_exc']} / {c['trap_irq']}")
    out.append("")
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
    a = ap.parse_args()
    if a.diff:
        text = diff(load(a.diff[0]), load(a.diff[1]))
    elif a.results:
        data = load(a.results)
        if a.csv:
            write_csv(data, a.csv)
        text = markdown(data)
    else:
        ap.error("RESULTS or --diff A B required")
    if a.md:
        with open(a.md, "w") as f:
            f.write(text)
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
