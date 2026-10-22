#!/usr/bin/env python3
"""pertest.py <run-dir> <stats2.csv>: per-test table (runs, pass, records,
traps, dut cycles, boot modes, pygen peak MiB) from results.csv and the
stats2.py coverage rows."""
import csv, sys, collections
csv.field_size_limit(1 << 24)
root, cov = sys.argv[1:3]
rows = list(csv.DictReader(open(root + "/results.csv")))
covr = {(r["test"], r["seed"]): r for r in csv.DictReader(l for l in open(cov) if not l.startswith("#"))}
order = []
agg = collections.defaultdict(collections.Counter)
boots = collections.defaultdict(collections.Counter)
rss = collections.defaultdict(int)
for r in rows:
    t = r["test"]
    if t not in order: order.append(t)
    a = agg[t]; a["runs"] += 1; a["pass"] += r["status"] == "PASS"
    a["records"] += int(r["ref_records"] or 0); a["cycles"] += int(r["dut_cycles"] or 0)
    if r["ref_records"] != r["dut_records"]: a["neq"] += 1
    c = covr.get((t, r["seed"]))
    if c: a["traps"] += int(c["traps"]); boots[t][c["boot"]] += 1
    rss[t] = max(rss[t], int(r["gen_rss_mb"] or 0))
print("%-38s %4s %4s %9s %6s %10s %s" % ("test", "runs", "pass", "records", "traps", "dut_cycles", "boot modes / pygen peak MiB"))
T = collections.Counter()
for t in order:
    a = agg[t]; T.update(a)
    print("%-38s %4d %4d %9d %6d %10d %s / %d%s" % (t, a["runs"], a["pass"], a["records"], a["traps"], a["cycles"],
          " ".join("%s:%d" % kv for kv in sorted(boots[t].items())), rss[t], "  ref!=dut in %d" % a["neq"] if a["neq"] else ""))
print("total runs %d, PASS %d, records %d, dut cycles %d, runs with ref != dut records %d" % (T["runs"], T["pass"], T["records"], T["cycles"], T["neq"]))
