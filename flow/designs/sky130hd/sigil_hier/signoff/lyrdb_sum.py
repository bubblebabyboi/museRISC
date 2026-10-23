#!/usr/bin/env python3
# Marker summary of a KLayout DRC report (.lyrdb): count per rule
# category (all categories of the deck that produced markers), and per
# floorplan region of sigil_soc_top (die um) when --soc is given:
#   glue x < 305 ; cpu 305<=x, y < 3430 ; gap 3430<=y<3470 ; crypto y >= 3470
# (marker position = first coordinate of the marker value).
# usage: lyrdb_sum.py <drc.lyrdb> [--soc]
import sys, re, collections
import xml.etree.ElementTree as ET
path = sys.argv[1]; soc = '--soc' in sys.argv
desc = {}
cnt = collections.Counter(); reg = collections.defaultdict(collections.Counter)
num = re.compile(r'-?\d+(?:\.\d+)?')
def region(x, y):
    if x < 305: return 'glue'
    if y < 3430: return 'cpu'
    if y < 3470: return 'gap'
    return 'crypto'
ctx = ET.iterparse(path, events=('end',))
in_items = False
for ev, el in ctx:
    if el.tag == 'category':
        n = el.find('name'); d = el.find('description')
        if n is not None and n.text:
            desc[n.text.strip("'")] = (d.text or '') if d is not None else ''
    elif el.tag == 'item':
        c = (el.findtext('category') or '').strip("'")
        cnt[c] += 1
        if soc:
            v = el.find('values/value')
            if v is not None and v.text:
                xy = num.findall(v.text.split(':', 1)[-1])
                if len(xy) >= 2:
                    reg[c][region(float(xy[0]), float(xy[1]))] += 1
        el.clear()
total = sum(cnt.values())
print(f'markers {total} in {len(cnt)} categories ({len(desc)} categories in the report)')
for c, v in sorted(cnt.items(), key=lambda kv: (-kv[1], kv[0])):
    r = ''
    if soc:
        r = '  [' + ', '.join(f'{k} {n}' for k, n in sorted(reg[c].items())) + ']'
    print(f'{v:10d}  {c:22s} {desc.get(c, "")}{r}')
