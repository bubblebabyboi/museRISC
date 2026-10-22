#!/usr/bin/env python3
"""Smoke test of the per-variant "regions"/"expect" keys (not used by any
bench yet): runs scripts/perf_run.py unchanged with sha256chain's
variants replaced in memory by
  all7     - every region listed explicitly + an expect line that is printed  -> must pass
  subset   - regions 0 and 5 only (the image still measures 7)              -> must fail (undeclared regions)
  badexp   - an expect line the program never prints                         -> must fail
usage: variant_opts_test.py <repo root> -- <perf_run.py args>
"""
import os
import sys

root = sys.argv[1]
assert sys.argv[2] == "--"
sys.path.insert(0, os.path.join(root, "scripts"))
import perf_run  # noqa: E402

_load = perf_run.load_benches


def load_benches(r, wanted):
    found = _load(r, wanted)
    b = found["sha256chain"]
    sdk = b["variants"]["sdk"]
    b["variants"] = {
        "all7": dict(sdk, regions=[str(i) for i in range(7)],
                     expect=["RESULT sha512 accel sigil_hash: {iterations} hash"]),
        "subset": dict(sdk, regions=["0", "5"]),
        "badexp": dict(sdk, expect=["NO SUCH LINE {iterations}"]),
    }
    return found


perf_run.load_benches = load_benches
sys.argv = ["perf_run.py"] + sys.argv[3:]
perf_run.main()
