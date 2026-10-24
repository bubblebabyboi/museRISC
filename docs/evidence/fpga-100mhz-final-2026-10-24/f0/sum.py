import csv, sys, collections
def load(f):
    return list(csv.DictReader(open(f), delimiter='\t'))
def top(rows):
    c = 'u_cpu/u_core/'
    g = collections.defaultdict(lambda: [99.0, 0])
    for r in rows:
        k = r['start'].replace(c, '') + ' -> ' + r['end'].replace(c, '')
        g[k][0] = min(g[k][0], float(r['slack'])); g[k][1] += 1
    return g
for f in sys.argv[1:]:
    rows = load(f)
    pm = [r for r in rows if r['pmp'] == '1']; vs = [r for r in rows if r['vstart'] == '1']
    print(f"== {f}: endpoints with slack < 1.5 ns: {len(rows)}; worst {min(float(r['slack']) for r in rows):.3f}")
    print(f"   PMP-through endpoints: {len(pm)}, worst {min([float(r['slack']) for r in pm] or [99]):.3f}")
    print(f"   vstart-through endpoints: {len(vs)}, worst {min([float(r['slack']) for r in vs] or [99]):.3f}")
    g = top(rows)
    for k, (s, n) in sorted(g.items(), key=lambda x: x[1][0])[:14]:
        print(f"   {s:6.3f} {n:5d}  {k}")
    print("   worst PMP-through pairs:")
    for k, (s, n) in sorted(top(pm).items(), key=lambda x: x[1][0])[:6]:
        print(f"   {s:6.3f} {n:5d}  {k}")
    print("   worst vstart-through pairs:")
    for k, (s, n) in sorted(top(vs).items(), key=lambda x: x[1][0])[:6]:
        print(f"   {s:6.3f} {n:5d}  {k}")
