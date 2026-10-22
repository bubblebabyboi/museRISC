#!/usr/bin/env python3
"""stats2.py <run-dir>: per (test, seed) coverage from the reference trace
(ref.csv): boot mode, records, traps by cause, privilege mix, records with
FP / vector / CSR writes. Last line: totals."""
import csv, glob, os, re, sys, collections
csv.field_size_limit(1 << 24)
root = sys.argv[1]
rows = list(csv.DictReader(open(os.path.join(root, "results.csv"))))
tot = collections.Counter()
causes_all = collections.Counter()
print("test,seed,status,boot,records,traps,trap_causes,priv_mix,fp_write_records,vec_write_records,csr_write_records")
for r in rows:
    d = os.path.join(root, r["test"], r["seed"])
    boot = "-"
    for s in glob.glob(os.path.join(d, "*_0.S")):
        m = re.search(r"^init_(machine|supervisor|user)_mode:", open(s).read(), re.M)
        boot = m.group(1)[0].upper() if m else ("M" if r["test"].startswith("riscv_") else "M(directed)")
    recs = traps = fpw = vw = csrw = 0
    causes = collections.Counter(); priv = collections.Counter()
    f = os.path.join(d, "ref.csv")
    if os.path.exists(f):
        for x in csv.DictReader(open(f)):
            recs += 1
            if x["instr"] == "trap":
                traps += 1
                c = int(x["csr"].split(";")[0].split(":")[1], 16)
                causes[c] += 1; causes_all[c] += 1
                continue
            priv[x["mode"]] += 1
            g = [t for t in x["gpr"].split(";") if t]
            if any(t.startswith("f") for t in g): fpw += 1
            if any(re.match(r"v\d+:", t) for t in g): vw += 1
            if x["csr"]: csrw += 1
    tot["records"] += recs; tot["traps"] += traps; tot["fp"] += fpw; tot["vec"] += vw
    tot["runs"] += 1; tot[r["status"]] += 1
    print("%s,%s,%s,%s,%d,%d,%s,%s,%d,%d,%d" % (r["test"], r["seed"], r["status"], boot, recs, traps,
          " ".join("%d:%d" % kv for kv in sorted(causes.items())),
          " ".join("%s:%d" % kv for kv in sorted(priv.items())), fpw, vw, csrw))
print("# runs %d (PASS %d), records %d, traps %d (causes %s), FP-write records %d, vector-write records %d" % (
      tot["runs"], tot["PASS"], tot["records"], tot["traps"],
      " ".join("%d:%d" % kv for kv in sorted(causes_all.items())), tot["fp"], tot["vec"]))
