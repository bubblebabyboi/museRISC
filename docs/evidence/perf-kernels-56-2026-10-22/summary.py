#!/usr/bin/env python3
"""Numbers quoted in README.md, from results.json and alignment-shift2.log
(run in this directory: python3 -I summary.py > summary.log)."""
import json, re
d = json.load(open("results.json"))
R = {(r["variant"], r["mem"], r["config"], r["region"]): r for r in d["runs"] if r["rep"] == 0}
K = d["meta"]["benches"]["kernels"]["kernels"]
sh = {}
for line in open("alignment-shift2.log"):
    m = re.match(r"\| (\d+) .*? \| ([\d,\.]+) \| [\d\.]+ \| ([\d,\.]+) \|", line)
    if m: sh[int(m.group(1))] = (float(m.group(2).replace(",", "")), float(m.group(3).replace(",", "")))
print("| # | Kernel | Work/call | C cyc/call | C units/cyc | RVV cyc/call | RVV units/cyc | RVV speedup | C shifted cyc/call | speedup vs best C | axi RVV speedup |")
for k in K:
    i = k["id"]; u = k["units"]
    c = R[("scalar","soc","default",10*i)]["counters"]["cycles"]/4
    v = R[("scalar","soc","default",10*i+1)]["counters"]["cycles"]/4
    ca = R[("scalar","axi","default",10*i)]["counters"]["cycles"]/4
    va = R[("scalar","axi","default",10*i+1)]["counters"]["cycles"]/4
    assert abs(sh[10*i][0] - c) < 0.06, (i, sh[10*i], c)
    best = min(c, sh[10*i][1])
    print(f"| {i} | {k['name']} | {u:,} {k['unit']} | {c:,.0f} | {u/c:.4f} | {v:,.0f} | {u/v:.4f} | {c/v:.2f}x | {sh[10*i][1]:,.0f} | {best/v:.2f}x | {ca/va:.2f}x |")
    if (("scalar","soc","default",10*i+2)) in R:
        e = R[("scalar","soc","default",10*i+2)]["counters"]["cycles"]/4
        ea = R[("scalar","axi","default",10*i+2)]["counters"]["cycles"]/4
        print(f"| | {k['name']} RVV-e8 | | | | {e:,.0f} | {u/e:.4f} | {c/e:.2f}x | | {best/e:.2f}x | {ca/ea:.2f}x |")
print()
def C(v,m,reg): return R[(v,m,"default",reg)]["counters"]
x = C("scalar","soc",91); print("dgemm RVV vec_busy", x["vec_busy"], "expected", 4*32*(32*(8*32+4)+(32+4)))
x = C("scalar","soc",101); print("sgemm RVV vec_busy", x["vec_busy"], "expected", 4*32*(32*(8*32+4)+(32+4)))
x = C("scalar","soc",31); print("daxpy RVV vec_busy", x["vec_busy"], "expected", 4*8*(8*64+4))
for reg in (30, 40, 50, 90, 100, 110):
    x = C("scalar","soc",reg); print(reg, "stk_fpu", x["stk_fpu"], "fpu_busy", x.get("fpu_busy"), "ret_fp", x["ret_fp"], "fpu/ret_fp", round(x["stk_fpu"]/x["ret_fp"],2), "fpu_busy/ret_fp", round(x["fpu_busy"]/x["ret_fp"],2))
for mem in ("soc", "axi"):
    ls = []
    for k in K:
        for imp in (1,2):
            key = ("scalar",mem,"default",10*k["id"]+imp)
            if key in R:
                c = R[key]["counters"]; ls.append((round(c["stk_vls"]/(c["dc_load"]+c["dc_store"]),2), k["name"], imp))
    print("LS cyc/access", mem, min(ls), max(ls))
x = C("scalar","soc",72); print("memcpy e8 vls_cyc", x["vls_cyc"], "stk_vls", x["stk_vls"], "accesses", x["dc_load"]+x["dc_store"], "ret_vls", x["ret_vls"])
x = C("scalar","soc",71); print("memcpy e64 vls_cyc", x["vls_cyc"], "stk_vls", x["stk_vls"], "accesses", x["dc_load"]+x["dc_store"], "ret_vls", x["ret_vls"])
for k in K:
    c = C("scalar","soc",10*k["id"]); cyc=c["cycles"]
    fe = c["stk_fetch_lat"]+c["stk_fetch_straddle"]+c.get("stk_fetch_miss",0)
    print(k["name"], "C IPC %.3f fetch %.1f%% straddle %.1f%% fpu %.1f%% muldiv %.1f%% dc_lat %.1f%% branch %.1f%% retire %.1f%%" % (c["instret"]/cyc, 100*fe/cyc, 100*c["stk_fetch_straddle"]/cyc, 100*c["stk_fpu"]/cyc, 100*c["stk_muldiv"]/cyc, 100*c["stk_dc_lat"]/cyc, 100*c["stk_branch"]/cyc, 100*c["stk_retire"]/cyc))
print()
for k in K:
    i=k["id"]; s=C("scalar","soc",10*i)["cycles"]; a=C("autovec","soc",10*i)["cycles"]; v=C("scalar","soc",10*i+1)["cycles"]
    print(f"| {k['name']} | {s/4:,.0f} | {a/4:,.0f} | {s/a:.2f}x | {s/v:.2f}x |")
diff = [(k["name"], C("scalar","soc",10*k["id"]+1)["cycles"], C("autovec","soc",10*k["id"]+1)["cycles"]) for k in K]
print("RVV regions differing between variants:", [x for x in diff if x[1]!=x[2]])
hw = [abs(r["counters"]["cycles"] - r["hw_cycles"]) for r in d["runs"]]
print("hw-counter vs window: max diff", max(hw))
print()
x = C("scalar","soc",131); print("mac_i16 RVV vec_busy", x["vec_busy"], "expected", 4*(132 + 16*(5*128+4) + 5 + (128+6) + 4))
x = C("scalar","soc",121); print("mac_i8 RVV vec_busy", x["vec_busy"], "expected", 4*(5 + 16*((5*256+4) + (256+6)) + 4))
x = C("scalar","soc",11); print("vadd_i32 RVV vec_busy", x["vec_busy"], "expected", 4*8*(128+4))
st = [(round(100*C("scalar","soc",10*k["id"]+i)["stk_fetch_straddle"]/C("scalar","soc",10*k["id"]+i)["cycles"],1), k["name"], i)
      for k in K for i in (1,2) if ("scalar","soc","default",10*k["id"]+i) in R]
print("RVV straddle % of cycles: max", max(st))
ir = [(round(100*C("scalar","soc",10*k["id"]+1)["instret"]/C("scalar","soc",10*k["id"])["instret"],2), k["name"]) for k in K]
print("RVV instret as % of C instret:", min(ir), max(ir))
fe = []
for k in K:
    c = C("scalar","soc",10*k["id"]); fe.append((round(100*(c["stk_fetch_lat"]+c["stk_fetch_straddle"]+c.get("stk_fetch_miss",0))/c["cycles"],1), k["name"]))
print("C fetch share: min", min(fe), "max", max(fe))
rat = []
for (v,m,cfg,reg), r in R.items():
    if m != "axi": continue
    s = R[(v,"soc",cfg,reg)]["counters"]["cycles"]
    rat.append((round(r["counters"]["cycles"]/s, 3), v, reg, r["label"]))
rat.sort()
print("axi/soc cycles: min", rat[0], "max", rat[-1])
print("axi/soc > 1.05:", [x for x in rat if x[0] > 1.05])
