#!/usr/bin/env python3
"""split_units.py <pp-file> <outdir>: split a Verilator -E -P output into one
file per design unit (module / package / interface), named after the unit;
text outside any unit goes to _toplevel. Prints '<unit> <sha256[:16]> <lines>'."""
import hashlib, os, re, sys
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
start = re.compile(r'^\s*(module|package|interface|program)\s+(?:automatic\s+|static\s+)?(\w+)')
end = re.compile(r'^\s*(endmodule|endpackage|endinterface|endprogram)\b')
units = {}; cur = '_toplevel'
for line in open(src):
    if line.strip() == '':
        continue
    m = start.match(line)
    if m and cur == '_toplevel':
        cur = m.group(2)
        if cur in units: raise SystemExit(f'duplicate unit {cur}')
    units.setdefault(cur, []).append(line)
    if end.match(line) and cur != '_toplevel':
        cur = '_toplevel'
for u, ls in sorted(units.items()):
    txt = ''.join(ls)
    open(os.path.join(out, u + '.sv'), 'w').write(txt)
    print(u, hashlib.sha256(txt.encode()).hexdigest()[:16], len(ls))
