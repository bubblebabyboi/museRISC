#!/usr/bin/env python3
"""Canonical form of a flattened Yosys JSON netlist (#53 ASIC invariance).

  netlist_canon.py IN.json OUT.json [--labels FILE] [--rounds K FILE]
  netlist_canon.py diff A.rounds B.rounds

Yosys 0.33 cell counts depend on the order in which identifiers were
created, so one logic read from two source texts (or the same text read
after an unrelated module) can synthesize to different counts. This
removes names and order. Cells and net bits are labelled by colour
refinement over the netlist graph, starting from the cell type, its
parameters (MEMID excepted) and full_case/parallel_case/keep, and the
module port names; ties left over are broken one cell at a time. Cells
are written in label order as $c<n>, nets numbered from their canonical
driver, and only port names are kept. Two netlists give byte-identical
output when they are the same graph up to names, so the same synthesis
script then gives the same result.

--labels writes each cell's final label with its name, type and source
location. --rounds writes the labels of refinement rounds 0..K; `diff`
then lists the cells whose round-r label one side lacks, for the first
rounds: a structural difference shows up around its own cells at round 1.
Input: write_json after proc; flatten; opt_clean; memory_collect. Black
box modules (macro models read with -lib) are copied with their ports.
"""
import hashlib
import json
import sys
from collections import Counter, defaultdict

KEEP_ATTRS = ("full_case", "parallel_case", "keep")
CONSTS = ("0", "1", "x", "z")


def shash(s):
    return int.from_bytes(hashlib.blake2b(s.encode(), digest_size=8).digest(), "little") >> 2


class Netlist:
    def __init__(self, mod):
        self.mod = mod
        self.names = list(mod["cells"])
        cells = [mod["cells"][n] for n in self.names]
        self.cells = cells
        self.conns = [[(p, c["port_directions"][p], c["connections"][p])
                       for p in sorted(c["connections"])] for c in cells]
        self.init = []
        for c, cl in zip(cells, self.conns):
            params = sorted((k, v) for k, v in c["parameters"].items() if k != "MEMID")
            attrs = sorted((k, v) for k, v in c["attributes"].items() if k in KEEP_ATTRS)
            self.init.append(shash(json.dumps(
                [c["type"], params, attrs, [(p, d, len(b)) for p, d, b in cl]])))
        self.drv = {}                  # bit -> label of its driver (ports) or (cell, port, idx)
        self.rd = defaultdict(list)    # bit -> readers: (cell, port, idx) or a port label
        for p, pv in mod["ports"].items():
            for i, b in enumerate(pv["bits"]):
                if isinstance(b, str):
                    continue
                if pv["direction"] == "input":
                    self.drv[b] = shash(f"in:{p}:{i}")
                else:
                    self.rd[b].append(shash(f"out:{p}:{i}"))
        for ci, cl in enumerate(self.conns):
            for p, d, bits in cl:
                for i, b in enumerate(bits):
                    if isinstance(b, str):
                        continue
                    if d == "output":
                        assert b not in self.drv, f"bit {b} has two drivers"
                        self.drv[b] = (ci, shash(p), i)
                    else:
                        self.rd[b].append((ci, shash(p), i))
        self.bits = sorted(set(self.drv) | set(self.rd))
        self.const = {s: shash("const:" + s) for s in CONSTS}
        self.pport = [[shash(p) for p, _, _ in cl] for cl in self.conns]

    def step(self, lab):
        """One refinement round: net labels from their driver and readers,
        then cell labels from their own and their connected nets' labels."""
        term = lambda r: r if isinstance(r, int) else hash((lab[r[0]], r[1], r[2]))
        nl = {}
        for b in self.bits:
            d = self.drv.get(b, 0)
            nl[b] = hash((term(d), tuple(sorted(term(r) for r in self.rd.get(b, ())))))
        new = []
        for ci, cl in enumerate(self.conns):
            t = [lab[ci]]
            for ph, (_, _, bits) in zip(self.pport[ci], cl):
                t.append(ph)
                t.extend(self.const[b] if isinstance(b, str) else nl[b] for b in bits)
            new.append(hash(tuple(t)))
        return new

    def refine(self, lab):
        n = len(set(lab))
        rounds = 0
        while True:
            lab = self.step(lab)
            rounds += 1
            n2 = len(set(lab))
            if n2 <= n:
                return lab, rounds
            n = n2


def canon(src, dst, labels=None, rounds=None):
    mods = json.load(open(src))["modules"]
    bbox = sorted(n for n in mods if mods[n].get("attributes", {}).get("blackbox"))
    tops = [n for n in mods if n not in bbox]
    assert len(tops) == 1, f"expected one flattened module, got {tops}"
    top = tops[0]
    assert not mods[top].get("memories"), "run memory_collect before write_json"
    nl = Netlist(mods[top])
    C = len(nl.cells)
    if rounds:
        k, path = rounds
        lab = list(nl.init)
        with open(path, "w") as f:
            for r in range(k + 1):
                for ci in range(C):
                    c = nl.cells[ci]
                    f.write(f"{r}\t{lab[ci]:016x}\t{c['type']}\t{nl.names[ci]}\t"
                            f"{c['attributes'].get('src', '')}\n")
                lab = nl.step(lab)
    lab, nrounds = nl.refine(list(nl.init))
    final = list(lab)
    cnt = Counter(lab)
    tied = sum(k for k in cnt.values() if k > 1)
    nind = 0
    while True:
        cnt = Counter(lab)
        ties = [v for v, k in cnt.items() if k > 1]
        if not ties:
            break
        v = min(ties)
        ci = lab.index(v)          # the members cannot be told apart
        lab[ci] = hash((v, 1))
        lab, _ = nl.refine(lab)
        nind += 1
    print(f"{top}: {C} cells, {len(nl.bits)} net bits, {nrounds} refinement rounds, "
          f"{len(set(final))} classes, {tied} cells tied, {nind} tie breaks", file=sys.stderr)

    order = sorted(range(C), key=lambda i: lab[i])
    newid = {}
    def number(bits):
        for b in bits:
            if not isinstance(b, str) and b not in newid:
                newid[b] = len(newid) + 2
    ports = mods[top]["ports"]
    for pv in ports.values():
        if pv["direction"] == "input":
            number(pv["bits"])
    for ci in order:
        for _, d, bits in nl.conns[ci]:
            if d == "output":
                number(bits)
    for ci in order:               # undriven nets, by first reader
        for _, _, bits in nl.conns[ci]:
            number(bits)
    for pv in ports.values():
        number(pv["bits"])
    mapb = lambda bits: [b if isinstance(b, str) else newid[b] for b in bits]

    cells = {}
    for k, ci in enumerate(order):
        c = nl.cells[ci]
        params = {p: c["parameters"][p] for p in sorted(c["parameters"])}
        if "MEMID" in params:
            params["MEMID"] = "\\mem%05d" % k
        cells["$c%06d" % k] = {
            "hide_name": 1, "type": c["type"], "parameters": params,
            "attributes": {a: c["attributes"][a] for a in sorted(c["attributes"]) if a in KEEP_ATTRS},
            "port_directions": {p: d for p, d, _ in nl.conns[ci]},
            "connections": {p: mapb(bits) for p, _, bits in nl.conns[ci]}}
    out = {}
    for n in bbox:
        bp = mods[n]["ports"]
        out[n] = {"attributes": {"blackbox": mods[n]["attributes"]["blackbox"]},
                  "ports": bp, "cells": {},
                  "netnames": {p: {"hide_name": 0, "bits": v["bits"], "attributes": {}} for p, v in bp.items()}}
    out[top] = {"attributes": {},
                "ports": {p: {"direction": v["direction"], "bits": mapb(v["bits"])} for p, v in ports.items()},
                "cells": cells,
                "netnames": {p: {"hide_name": 0, "bits": mapb(v["bits"]), "attributes": {}} for p, v in ports.items()}}
    with open(dst, "w") as f:
        json.dump({"creator": "netlist_canon.py", "modules": out}, f, indent=0)
        f.write("\n")
    if labels:
        with open(labels, "w") as f:
            for ci in range(C):
                c = nl.cells[ci]
                f.write(f"{final[ci]:016x}\t{c['type']}\t{nl.names[ci]}\t{c['attributes'].get('src', '')}\n")


def diff(a, b, show=12):
    def load(p):
        d = defaultdict(list)
        for line in open(p):
            r, lab, typ, name, src = line.rstrip("\n").split("\t")
            d[int(r)].append((lab, typ, name, src))
        return d
    A, B = load(a), load(b)
    for r in sorted(A):
        ca, cb = Counter(x[0] for x in A[r]), Counter(x[0] for x in B[r])
        oa = [x for x in A[r] if cb[x[0]] < ca[x[0]]]
        ob = [x for x in B[r] if ca[x[0]] < cb[x[0]]]
        print(f"round {r}: {len(oa)} cells only in A, {len(ob)} only in B")
        if oa or ob:
            for side, xs in (("A", oa), ("B", ob)):
                for x in xs[:show]:
                    print(f"  {side} {x[1]} {x[3]}")
            break


def main(argv):
    if argv and argv[0] == "diff":
        diff(argv[1], argv[2])
        return
    src, dst, rest = argv[0], argv[1], argv[2:]
    labels = rounds = None
    while rest:
        if rest[0] == "--labels":
            labels, rest = rest[1], rest[2:]
        elif rest[0] == "--rounds":
            rounds, rest = (int(rest[1]), rest[2]), rest[3:]
        else:
            sys.exit(f"unknown argument {rest[0]}")
    canon(src, dst, labels, rounds)


if __name__ == "__main__":
    main(sys.argv[1:])
