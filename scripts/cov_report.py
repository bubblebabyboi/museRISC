#!/usr/bin/env python3
"""Per-file line/toggle coverage from a Verilator coverage .dat.

Points are merged across instances (a line or toggle point counts
as covered if any instance hit it). Usage:
  cov_report.py build/sim/cov_merged.dat [file-substring ...]
  cov_report.py --uncovered FILE.dat muserisc_dcache.sv
"""
import collections
import sys


def parse(path):
    pts = collections.defaultdict(int)
    with open(path, encoding="latin-1") as f:
        for ln in f:
            if not ln.startswith("C '"):
                continue
            body, count = ln[3:].rsplit("' ", 1)
            kv = {}
            for field in body.split("\x01"):
                if "\x02" in field:
                    k, v = field.split("\x02", 1)
                    kv[k] = v
            key = (kv.get("f"), kv.get("t"), kv.get("l"), kv.get("o", ""),
                   kv.get("n", ""))
            pts[key] = max(pts[key], int(count))
    return pts


def main():
    args = sys.argv[1:]
    show = args and args[0] == "--uncovered"
    if show:
        args = args[1:]
    pts = parse(args[0])
    files = args[1:]
    stat = collections.defaultdict(lambda: [0, 0])
    unc = collections.defaultdict(list)
    for (f, t, l, o, _), c in pts.items():
        name = f.split("/")[-1]
        if files and not any(s in name for s in files):
            continue
        st = stat[(name, t)]
        st[1] += 1
        if c > 0:
            st[0] += 1
        elif show:
            unc[(name, t)].append((int(l), o))
    for (name, t), (hit, tot) in sorted(stat.items()):
        print(f"{name:28s} {t:8s} {hit:6d}/{tot:<6d} {100.0 * hit / tot:6.2f}%")
    for (name, t), lst in sorted(unc.items()):
        for l, o in sorted(lst):
            print(f"  uncovered {name}:{l} {t} {o}")


if __name__ == "__main__":
    main()
