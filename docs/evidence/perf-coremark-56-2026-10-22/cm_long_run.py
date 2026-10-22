#!/usr/bin/env python3
"""Runs scripts/perf_run.py unchanged, with the coremark bench's
bench.json settings overridden in memory: max_cycles (bench.json: 2e8,
too small for a run long enough for EEMBC's 10 s rule at 62.5 MHz) and
the variant set (bench.json variants by name, or extra ones given in
full). Validation, determinism check and report are perf_run.py's.

usage: cm_long_run.py <repo root> <max_cycles> <variants JSON> -- <perf_run.py args>
  variants JSON: {"scalar": null, "o3": {"description": "...", "make": {...}}}
                 (null = take the variant from bench.json)
"""
import json
import os
import sys

root, max_cycles, variants = sys.argv[1], int(sys.argv[2]), json.loads(sys.argv[3])
assert sys.argv[4] == "--"
sys.path.insert(0, os.path.join(root, "scripts"))
import perf_run  # noqa: E402

_load = perf_run.load_benches


def load_benches(r, wanted):
    found = _load(r, wanted)
    b = found["coremark"]
    b["max_cycles"] = max_cycles
    b["variants"] = {k: (v if v is not None else b["variants"][k]) for k, v in variants.items()}
    return found


perf_run.load_benches = load_benches
sys.argv = ["perf_run.py"] + sys.argv[5:]
perf_run.main()
