#!/usr/bin/env python3
"""name_unproven.py <dir>: group the unproven $equiv cells of <dir>/eq.log by
the gold/gate signals they compare (bit indices dropped). A signal is named by
its wire name, its constant value, or the gold_core.v / gate_core.v source line
of the cell that drives it (a merged child's input)."""
import re, sys, collections, os
d = sys.argv[1]
src = {s: open(os.path.join(d, f'{s}_core.v')).read().split('\n') for s in ('gold', 'gate')
       if os.path.exists(os.path.join(d, f'{s}_core.v'))}
def name(sig):
    m = re.search(r'(gold|gate)_core\.v:(\d+)', sig)
    if m:
        return f'{m.group(1)}_core.v:{m.group(2)} `{src[m.group(1)][int(m.group(2))-1].strip()}`'
    if sig.startswith('\\'):
        return 'wire ' + re.sub(r'_(gold|gate)$', '', sig[1:])
    return sig
groups = collections.Counter()
for line in open(os.path.join(d, 'eq.log')):
    if not re.match(r'^\s*Unproven \$equiv', line): continue
    body = re.sub(r'^.*?(find_same_wires|find_same_cells)\$\d+:\s*', '', line.strip())
    body = re.sub(r'\s*\[\d+\]', '', body)
    toks = body.split()
    gold, gate = toks[0], toks[1]
    kind = 'merged-child input' if 'find_same_cells' in line else 'matched wire'
    groups[(kind, name(gold), name(gate))] += 1
for (kind, g, t), n in sorted(groups.items()):
    print(f'  {n:3d} bit(s), {kind}: gold {g} | gate {t}')
