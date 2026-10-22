#!/usr/bin/env python3
"""Code-placement experiment: C kernels at their 64-byte-aligned placement
(scalar) vs shifted by one 2-byte c.nop (-fpatchable-function-entry=1)."""
import hashlib, json, os, re, sys
S = sys.argv[1]           # build/kernels-shift2
H = sys.argv[2]           # harness result dir
def recs(path):
    out = {}
    for line in open(path):
        m = re.match(r"^SIGIL_PERF v1 (.*)$", line.strip())
        if not m: continue
        kv = {}
        for t in m.group(1).split():
            k, _, v = t.partition("=")
            kv[k] = int(v) if re.fullmatch(r"-?\d+", v) else v
        assert kv["cycles"] == kv["mcycle_delta"] and kv["instret"] == kv["minstret_delta"] and kv["stk_sum"] == kv["cycles"]
        out[kv["region"]] = kv
    return out
sha = lambda p: hashlib.sha256(open(p, "rb").read()).hexdigest()
h = json.load(open(os.path.join(H, "results.json")))
img = h["meta"]["images"]["kernels-scalar"]["bin_sha256"]
print(f"# image {S}/scalar/kernels.bin sha256 {sha(S + '/scalar/kernels.bin')}")
print(f"# harness kernels-scalar image sha256   {img} -> {'identical' if img == sha(S + '/scalar/kernels.bin') else 'DIFFERENT'}")
print(f"# image {S}/shift2/kernels.bin sha256 {sha(S + '/shift2/kernels.bin')}")
for v in ("scalar", "shift2"):
    log = open(f"{S}/{v}.log").read()
    ok = "SIGIL TEST PASS kernels" in log and log.count("CHECK OK") == 14
    print(f"# {v}: {'PASS, 13 kernel checks + KERNELS CHECK OK' if ok else 'NOT VALID'}; every record: cycles == mcycle delta, instret == minstret delta, slots sum to cycles")
a, b = recs(f"{S}/scalar.perf"), recs(f"{S}/shift2.perf")
labels = h["meta"]["benches"]["kernels"]["regions"]
print()
print("| Region | aligned cyc/call | aligned straddle % | shifted cyc/call | shifted straddle % | shifted / aligned |")
print("|---|---:|---:|---:|---:|---:|")
for rid in sorted(a):
    if rid % 10 != 0: continue  # C regions only (RVV code is not shifted)
    x, y = a[rid], b[rid]
    print(f"| {rid} {labels[str(rid)]} | {x['cycles']/4:,.1f} | {100*x['stk_fetch_straddle']/x['cycles']:.1f} "
          f"| {y['cycles']/4:,.1f} | {100*y['stk_fetch_straddle']/y['cycles']:.1f} | {y['cycles']/x['cycles']:.3f} |")
rv = [r for r in a if r % 10 != 0]
same = all(a[r]["cycles"] == b[r]["cycles"] for r in rv)
print(f"\nRVV regions (not shifted): cycles identical in both images: {same}")
