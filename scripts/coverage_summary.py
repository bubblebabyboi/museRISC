#!/usr/bin/env python3
"""Per-file Verilator coverage summary from a coverage .dat file.

Usage: coverage_summary.py <cov.dat> [path-substring ...]

Prints, per source file (optionally filtered by substrings), the
number of covered/total points for each coverage type
(line, branch, toggle) and the uncovered line/branch points.
Line and branch points are what `verilator_coverage --annotate`
counts as "lines"; toggle points are per bit and direction.
Points from different hierarchy instances of the same source line
are merged (a point counts as covered if any instance hit it).
"""
import collections
import re
import sys


def parse(path):
    pts = collections.defaultdict(int)
    with open(path, "rb") as f:
        for raw in f:
            if not raw.startswith(b"C '"):
                continue
            key, count = raw.rsplit(b"' ", 1)
            fields = {}
            for kv in key[3:].split(b"\x01"):
                if b"\x02" in kv:
                    k, v = kv.split(b"\x02", 1)
                    fields[k.decode()] = v.decode(errors="replace")
            ident = (fields.get("f", "?"), int(fields.get("l", 0)),
                     fields.get("n", ""), fields.get("t", "?"),
                     fields.get("o", ""))
            pts[ident] += int(count)
    return pts


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    pts = parse(sys.argv[1])
    filt = sys.argv[2:]
    per = collections.defaultdict(lambda: collections.defaultdict(lambda: [0, 0]))
    misses = collections.defaultdict(list)
    for (f, line, col, typ, comment), cnt in pts.items():
        if filt and not any(s in f for s in filt):
            continue
        cov = per[f][typ]
        cov[1] += 1
        if cnt > 0:
            cov[0] += 1
        elif typ in ("line", "branch"):
            misses[f].append((line, typ, comment))
    for f in sorted(per):
        parts = []
        for typ in ("line", "branch", "toggle"):
            c, t = per[f][typ]
            if t:
                parts.append(f"{typ} {c}/{t} ({100.0 * c / t:.1f}%)")
        print(f"{f}: " + ", ".join(parts))
        for line, typ, comment in sorted(misses[f]):
            print(f"    uncovered {typ} at line {line} ({comment})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
