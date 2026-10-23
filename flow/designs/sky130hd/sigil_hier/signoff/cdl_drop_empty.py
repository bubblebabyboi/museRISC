#!/usr/bin/env python3
# Drop the instances of device-less subcircuits (empty .SUBCKT bodies in
# sky130hd.cdl: tapvpwrvgnd_1, the antenna diode_2, fill cells) from a
# CDL netlist before KLayout LVS. An empty subcircuit connects nothing,
# so the netlist's connectivity is unchanged; the layout extraction has
# no devices in these cells either. With the instances kept, KLayout's
# align step flattens them one by one into the block's top circuit
# ("Flatten schematic circuit (no layout)"), each time purging all of
# its nets (db::Circuit::do_purge_nets): 5.8 h for the crypto block's
# 39k tap/diode instances, days for the CPU block's 141k.
# Only standard cells (name prefix, default sky130_fd_sc_hd__) are
# dropped: black-box stubs (empty bodies too, e.g. the OpenRAM macro
# stubs used with blank_circuit) stay.
# usage: cdl_drop_empty.py <in.cdl> <out.cdl> [prefix]
import sys, collections
src, dst = sys.argv[1], sys.argv[2]
prefix = (sys.argv[3] if len(sys.argv) > 3 else 'sky130_fd_sc_hd__').lower()
stmts = []
for line in open(src):
    line = line.rstrip('\n')
    if line.startswith('+') and stmts:
        stmts[-1].append(line)
    else:
        stmts.append([line])
def toks(st):
    return ' '.join(l[1:] if l.startswith('+') else l for l in st).split()
empty, cur, body = set(), None, 0
for st in stmts:
    t = toks(st)
    if not t:
        continue
    k = t[0].lower()
    if k == '.subckt':
        cur, body = t[1].lower(), 0
    elif k == '.ends':
        if cur is not None and body == 0 and cur.startswith(prefix):
            empty.add(cur)
        cur = None
    elif cur is not None and not t[0].startswith('*'):
        body += 1
dropped = collections.Counter()
with open(dst, 'w') as f:
    for st in stmts:
        t = toks(st)
        if t and t[0][0] in 'xX':
            m = [x for x in t[1:] if '=' not in x and x != '/'][-1].lower()
            if m in empty:
                dropped[m] += 1
                continue
        f.write('\n'.join(st) + '\n')
print('empty subcircuits:', ' '.join(sorted(empty)))
for m, n in sorted(dropped.items()):
    print(f'dropped {n} instances of {m}')
