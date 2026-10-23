#!/usr/bin/env python3
"""vtypes.py <run-dir>: RVV iterations of sigil_vector_test by SEW/LMUL, from
each iteration's `csrr a5, vtype` (0xc21027f3) in the reference traces."""
import csv, glob, os, sys, collections
csv.field_size_limit(1 << 24)
LM = {0: "m1", 1: "m2", 2: "m4", 3: "m8", 5: "mf8", 6: "mf4", 7: "mf2"}
cnt = collections.Counter(); n = 0
for f in sorted(glob.glob(os.path.join(sys.argv[1], "sigil_vector_test", "*", "ref.csv"))):
    for r in csv.DictReader(open(f)):
        if r["binary"] == "c21027f3":
            v = int(r["gpr"].split(":")[1], 16)
            if v >> 63:
                cnt["vill"] += 1
            else:
                cnt["e%d %s" % (8 << ((v >> 3) & 7), LM[v & 7])] += 1
            n += 1
print("iterations", n)
for sew in (8, 16, 32, 64):
    print("  e%-2d: %s" % (sew, ", ".join("%s %d" % (k.split()[1], v) for k, v in sorted(cnt.items()) if k.startswith("e%d " % sew))))
if cnt["vill"]:
    print("  vill", cnt["vill"])
print("pairs", len([k for k in cnt if k != "vill"]))
