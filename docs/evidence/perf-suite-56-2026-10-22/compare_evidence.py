#!/usr/bin/env python3
"""Compares an integrated suite result set with the per-branch evidence
result sets: for every (bench, variant, region, mem, config) in both,
rep 0 and rep 1, the image sha256, every SIGIL_PERF counter and the
hardware-counter numbers must be identical.

  compare_evidence.py SUITE_results.json EVIDENCE_results.json ...
"""
import json
import sys


def load(p):
    with open(p) as f:
        return json.load(f)


def key(r):
    return (r["bench"], r["variant"], r["region"], r["mem"], r["config"], r["rep"])


suite = load(sys.argv[1])
s_runs = {key(r): r for r in suite["runs"]}
total_fail = 0
covered = set()
for ev in sys.argv[2:]:
    e = load(ev)
    e_runs = {key(r): r for r in e["runs"]}
    common = sorted(set(s_runs) & set(e_runs))
    same_img = same_cnt = 0
    diffs = []
    for k in common:
        a, b = s_runs[k], e_runs[k]
        covered.add(k)
        img = a["bin_sha256"] == b["bin_sha256"]
        cnt = (a["counters"] == b["counters"] and a["hw_cycles"] == b["hw_cycles"]
               and a["hw_instret"] == b["hw_instret"])
        same_img += img
        same_cnt += cnt
        if not (img and cnt):
            fields = sorted(f for f in set(a["counters"]) | set(b["counters"])
                            if a["counters"].get(f) != b["counters"].get(f))
            diffs.append((k, img, a["counters"].get("cycles"), b["counters"].get("cycles"), fields[:6]))
    benches = sorted({k[0] for k in e_runs})
    print(f"{ev}: benches {' '.join(benches)}; evidence date {e['meta']['date_utc']} "
          f"commit {e['meta']['git_head'][:7]} rtl {e['meta']['rtl_tree'][:12]}")
    print(f"  {len(common)} runs in common ({len(e_runs)} in evidence): "
          f"image identical {same_img}/{len(common)}, counters identical {same_cnt}/{len(common)}")
    for d in diffs[:20]:
        print("  DIFF", d)
    total_fail += len(diffs)
missing = sorted(set(s_runs) - covered)
print(f"suite: {len(s_runs)} valid runs, {len(suite.get('failed', []))} failed; "
      f"{len(covered)} compared with evidence, {len(missing)} not in any evidence set")
for k in missing[:10]:
    print("  not compared:", k)
print("RESULT:", "IDENTICAL" if total_fail == 0 else f"{total_fail} DIFFERENCES")
