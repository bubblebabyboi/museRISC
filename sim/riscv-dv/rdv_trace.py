#!/usr/bin/env python3
"""Commit traces for the Sigil riscv-dv regression (issue #8).

Reads the two sides of a riscv-dv run into one record format, writes
them as riscv-dv trace CSV, and compares them:

- reference: Spike run with ``-l --log-commits`` (commit lines, plus the
  ``exception ...`` / ``tval ...`` lines that -l prints on traps);
- DUT: the Sigil core's retire trace, written by the simulation-only
  probe at the end of rtl/core/sigil_core.sv when core_tb runs with
  ``+sigil_trace=<file>`` (format in docs/VERIFICATION.md).

Record = one retired instruction ('I') or one trap taken ('E'). For an
'I' record: privilege, pc, instruction bits, and the architectural
writes it made: x and f registers, CSRs, stores (address, size, data)
and whole vector registers.

Comparison rules (first divergence wins):
- records are compared in order; kind, pc and instruction bits must
  match, and privilege for retired instructions;
- x/f register writes: the same registers with the same values;
- stores: the same (address, size, data) list (scalar stores; vector
  store data is checked when loaded back);
- CSR writes: the DUT logs explicit CSR-instruction writes (value read
  back after the write) and fflags accrual; Spike also logs side
  effects (mstatus.FS/VS dirtying, xRET status updates, ...). Values are
  compared for every CSR both sides logged; fflags must additionally be
  logged by both or neither. fcsr/vcsr writes are split into their
  fields first (Spike logs the fields), and an sstatus write is checked
  against the mstatus value Spike logs for it;
- vector registers: compared where both sides logged the register; a
  register only one side logged must already hold that value on the
  other side (its last logged value, 0 at reset): a write that leaves
  the register unchanged, e.g. a mask compare with every element
  masked off, may be logged by one side only;
- traps: cause, epc and tval;
- the reference is cut after the first store to ``tohost`` (HTIF exit)
  and the DUT trace must reach that same record.

Usage (the regression driver imports this module; the CLI is for
re-running one comparison by hand):
  rdv_trace.py --elf T.elf --spike spike.log --dut dut.trace \
      [--ref-csv ref.csv --dut-csv dut.csv]
Exit status 0 = traces match, 1 = mismatch, 2 = usage/parse error.
"""

import argparse
import csv
import re
import subprocess
import sys
from dataclasses import dataclass, field

MASK64 = (1 << 64) - 1

SPIKE_TRAPS = {
    "trap_instruction_address_misaligned": 0,
    "trap_instruction_access_fault": 1,
    "trap_illegal_instruction": 2,
    "trap_breakpoint": 3,
    "trap_load_address_misaligned": 4,
    "trap_load_access_fault": 5,
    "trap_store_address_misaligned": 6,
    "trap_store_access_fault": 7,
    "trap_user_ecall": 8,
    "trap_supervisor_ecall": 9,
    "trap_virtual_supervisor_ecall": 10,
    "trap_machine_ecall": 11,
    "trap_instruction_page_fault": 12,
    "trap_load_page_fault": 13,
    "trap_store_page_fault": 15,
    "trap_double_trap": 16,
    "trap_software_check": 18,
    "trap_instruction_guest_page_fault": 20,
    "trap_load_guest_page_fault": 21,
    "trap_virtual_instruction": 22,
    "trap_store_guest_page_fault": 23,
}

XABI = ["zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0", "s1",
        "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7", "s2", "s3", "s4",
        "s5", "s6", "s7", "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"]
FABI = ["ft0", "ft1", "ft2", "ft3", "ft4", "ft5", "ft6", "ft7", "fs0",
        "fs1", "fa0", "fa1", "fa2", "fa3", "fa4", "fa5", "fa6", "fa7",
        "fs2", "fs3", "fs4", "fs5", "fs6", "fs7", "fs8", "fs9", "fs10",
        "fs11", "ft8", "ft9", "ft10", "ft11"]
CSR_NAMES = {
    0x001: "fflags", 0x002: "frm", 0x003: "fcsr", 0x008: "vstart",
    0x009: "vxsat", 0x00A: "vxrm", 0x00F: "vcsr", 0x100: "sstatus",
    0x104: "sie", 0x105: "stvec", 0x106: "scounteren", 0x10A: "senvcfg",
    0x140: "sscratch", 0x141: "sepc", 0x142: "scause", 0x143: "stval",
    0x144: "sip", 0x180: "satp", 0x300: "mstatus", 0x301: "misa",
    0x302: "medeleg", 0x303: "mideleg", 0x304: "mie", 0x305: "mtvec",
    0x306: "mcounteren", 0x30A: "menvcfg", 0x320: "mcountinhibit",
    0x340: "mscratch", 0x341: "mepc", 0x342: "mcause", 0x343: "mtval",
    0x344: "mip", 0x34A: "mtinst", 0x34B: "mtval2", 0x3A0: "pmpcfg0",
    0x3A2: "pmpcfg2", 0xC20: "vl", 0xC21: "vtype",
}
CSR_NAMES.update({0x3B0 + i: "pmpaddr%d" % i for i in range(16)})
# CSR bits whose value is implementation-defined and differs between the
# two, left out of CSR-write comparisons (docs/VERIFICATION.md):
# mideleg bit 12 (SGEIP) reads one on Spike with H even with no guest
# external interrupts (GEILEN = 0); on Sigil (GEILEN = 0) it reads zero.
CSR_IMPL_DEFINED = {0x303: 1 << 12}
# RV64 sstatus view of mstatus: SIE SPIE UBE SPP VS FS XS SUM MXR UXL SD.
SSTATUS_MASK = ((1 << 1) | (1 << 5) | (1 << 6) | (1 << 8) | (3 << 9) | (3 << 13) |
                (3 << 15) | (1 << 18) | (1 << 19) | (3 << 32) | (1 << 63))


@dataclass
class Rec:
    kind: str                 # 'I' retired instruction, 'E' trap
    pc: int
    insn: int = 0
    ilen: int = 4             # 2 or 4 bytes
    priv: int = -1            # -1: not known (Spike prints none for traps)
    x: dict = field(default_factory=dict)
    f: dict = field(default_factory=dict)
    c: dict = field(default_factory=dict)
    m: list = field(default_factory=list)   # stores: (addr, size, data)
    v: dict = field(default_factory=dict)
    cause: int = 0
    tval: int = 0
    asm: str = ""
    src: int = 0              # line number in the source log

    def describe(self):
        if self.kind == "E":
            return "trap cause=0x%x epc=0x%x tval=0x%x" % (
                self.cause, self.pc, self.tval)
        bits = ("%04x" if self.ilen == 2 else "%08x") % self.insn
        s = "pc=0x%x insn=0x%s priv=%d" % (self.pc, bits, self.priv)
        if self.asm:
            s += " (%s)" % self.asm
        return s


def _int(tok):
    return int(tok, 16)


# ---------------------------------------------------------------------
# Spike
# ---------------------------------------------------------------------
_COMMIT = re.compile(
    r"^core\s+\d+:\s+(\d)\s+0x([0-9a-f]+)\s+\(0x([0-9a-f]+)\)(.*)$")
_DISASM = re.compile(r"^core\s+\d+:\s+0x([0-9a-f]+)\s+\(0x([0-9a-f]+)\)\s+(.*)$")
_EXC = re.compile(r"^core\s+\d+:\s+exception\s+(.+?),\s+epc\s+0x([0-9a-f]+)")
_TVAL = re.compile(r"^core\s+\d+:\s+tval\s+0x([0-9a-f]+)")


def _parse_spike_effects(rec, toks):
    i = 0
    n = len(toks)
    while i < n:
        t = toks[i]
        if t == "mem":
            addr = _int(toks[i + 1])
            if i + 2 < n and toks[i + 2].startswith("0x"):
                hexv = toks[i + 2][2:]
                rec.m.append((addr, len(hexv) // 2, int(hexv, 16)))
                i += 3
            else:
                i += 2        # load address: not compared
            continue
        mreg = re.match(r"^([xfv])(\d+)$", t)
        if mreg and i + 1 < n:
            getattr(rec, mreg.group(1))[int(mreg.group(2))] = _int(toks[i + 1])
            i += 2
            continue
        mcsr = re.match(r"^c(\d+)_\S+$", t)
        if mcsr and i + 1 < n:
            rec.c[int(mcsr.group(1))] = _int(toks[i + 1])
            i += 2
            continue
        # vector header "e<sew> m<lmul>|mf<n> l<vl>" and anything unknown
        i += 1


def parse_spike(path, entry, tohost):
    """Records from the first instruction at `entry` up to and including
    the first store to `tohost` (Spike's own boot ROM is skipped)."""
    recs = []
    started = False
    last_asm = {}
    with open(path, errors="replace") as fh:
        for ln, line in enumerate(fh, 1):
            line = line.rstrip("\n")
            m = _COMMIT.match(line)
            if m:
                pc = _int(m.group(2))
                if not started:
                    if pc != entry:
                        continue
                    started = True
                bits = m.group(3)
                rec = Rec("I", pc, int(bits, 16), len(bits) // 2,
                          int(m.group(1)), src=ln)
                rec.asm = last_asm.get(pc, "")
                _parse_spike_effects(rec, m.group(4).split())
                recs.append(rec)
                if any(a == tohost for a, _, _ in rec.m):
                    break
                continue
            m = _DISASM.match(line)
            if m:
                last_asm[_int(m.group(1))] = m.group(3).strip()
                if not started and _int(m.group(1)) == entry:
                    started = True
                continue
            if not started:
                continue
            m = _EXC.match(line)
            if m:
                name = m.group(1)
                if name in SPIKE_TRAPS:
                    cause = SPIKE_TRAPS[name]
                else:
                    mi = re.match(r"(interrupt|trap) #(\d+)", name)
                    if not mi:
                        raise ValueError("%s:%d: unknown trap %r" % (path, ln, name))
                    cause = int(mi.group(2)) | ((1 << 63) if mi.group(1) == "interrupt" else 0)
                recs.append(Rec("E", _int(m.group(2)), cause=cause, src=ln))
                continue
            m = _TVAL.match(line)
            if m and recs and recs[-1].kind == "E":
                recs[-1].tval = _int(m.group(1))
    return recs


# ---------------------------------------------------------------------
# DUT (sigil_core +sigil_trace)
# ---------------------------------------------------------------------
_DUT_CSR = re.compile(r"^c([0-9a-f]{3})=([0-9a-f]+)$")
_DUT_REG = re.compile(r"^([xfv])(\d+)=([0-9a-f]+)$")
_DUT_MEM = re.compile(r"^m([0-9a-f]+):(\d+)=([0-9a-f]+)$")


def _dut_csr(rec, addr, val):
    # Spike logs fcsr/vcsr writes as their fields.
    if addr == 0x003:
        rec.c[0x001] = val & 0x1F
        rec.c[0x002] = (val >> 5) & 0x7
    elif addr == 0x00F:
        rec.c[0x009] = val & 0x1
        rec.c[0x00A] = (val >> 1) & 0x3
    else:
        rec.c[addr] = val


def parse_dut(path, limit=None):
    """DUT records; with `limit`, stop after that many."""
    recs = []
    with open(path, errors="replace") as fh:
        for ln, line in enumerate(fh, 1):
            if limit is not None and len(recs) >= limit:
                break
            toks = line.split()
            if not toks:
                continue
            if toks[0] == "E":
                recs.append(Rec("E", _int(toks[3]), priv=int(toks[2]),
                                cause=_int(toks[4]), tval=_int(toks[5]), src=ln))
                continue
            if toks[0] != "I":
                raise ValueError("%s:%d: bad record %r" % (path, ln, line))
            rec = Rec("I", _int(toks[3]), _int(toks[4]), len(toks[4]) // 2,
                      int(toks[2]), src=ln)
            for t in toks[5:]:
                m = _DUT_REG.match(t)
                if m:
                    getattr(rec, m.group(1))[int(m.group(2))] = _int(m.group(3))
                    continue
                m = _DUT_CSR.match(t)
                if m:
                    _dut_csr(rec, _int(m.group(1)), _int(m.group(2)))
                    continue
                m = _DUT_MEM.match(t)
                if m:
                    size = int(m.group(2))
                    data = _int(m.group(3)) & ((1 << (8 * size)) - 1)
                    rec.m.append((_int(m.group(1)), size, data))
                    continue
                raise ValueError("%s:%d: bad token %r" % (path, ln, t))
            recs.append(rec)
    return recs


# ---------------------------------------------------------------------
# Comparison
# ---------------------------------------------------------------------
def _fmt_regs(prefix, d):
    return "{%s}" % ", ".join("%s%d=0x%x" % (prefix, k, d[k]) for k in sorted(d))


def is_vector_store(rec):
    """Vector stores: STORE-FP opcode with a vector width (funct3 0/5/6/7).
    The DUT trace logs scalar stores only; vector store data is checked
    when it is loaded back."""
    return (rec.ilen == 4 and (rec.insn & 0x7F) == 0x27 and
            ((rec.insn >> 12) & 7) in (0, 5, 6, 7))


def _diff(ref, dut):
    """List of human-readable differences between two records."""
    d = []
    if ref.kind != dut.kind:
        return ["kind: dut %s vs ref %s" % (dut.describe(), ref.describe())]
    if ref.pc != dut.pc:
        d.append("pc: dut 0x%x ref 0x%x" % (dut.pc, ref.pc))
    if ref.kind == "E":
        if ref.cause != dut.cause:
            d.append("cause: dut 0x%x ref 0x%x" % (dut.cause, ref.cause))
        if ref.tval != dut.tval:
            d.append("tval: dut 0x%x ref 0x%x" % (dut.tval, ref.tval))
        return d
    if ref.insn != dut.insn:
        d.append("insn: dut 0x%x ref 0x%x" % (dut.insn, ref.insn))
    if ref.priv != dut.priv:
        d.append("priv: dut %d ref %d" % (dut.priv, ref.priv))
    rx = {k: v for k, v in ref.x.items() if k != 0}
    if rx != dut.x:
        d.append("x: dut %s ref %s" % (_fmt_regs("x", dut.x), _fmt_regs("x", rx)))
    if ref.f != dut.f:
        d.append("f: dut %s ref %s" % (_fmt_regs("f", dut.f), _fmt_regs("f", ref.f)))
    if sorted(ref.m) != sorted(dut.m) and not is_vector_store(ref):
        fm = lambda l: "[%s]" % ", ".join("0x%x:%d=0x%x" % s for s in l)
        d.append("store: dut %s ref %s" % (fm(dut.m), fm(ref.m)))
    for a in sorted(set(ref.c) & set(dut.c)):
        keep = ~CSR_IMPL_DEFINED.get(a, 0)
        if ref.c[a] & keep != dut.c[a] & keep:
            d.append("csr 0x%03x (%s): dut 0x%x ref 0x%x" % (
                a, CSR_NAMES.get(a, "?"), dut.c[a], ref.c[a]))
    # Spike logs an sstatus write as the mstatus write it performs.
    if 0x100 in dut.c and 0x100 not in ref.c and 0x300 in ref.c:
        if dut.c[0x100] != ref.c[0x300] & SSTATUS_MASK:
            d.append("csr 0x100 (sstatus): dut 0x%x ref 0x%x (mstatus 0x%x)" % (
                dut.c[0x100], ref.c[0x300] & SSTATUS_MASK, ref.c[0x300]))
    if (0x001 in ref.c) != (0x001 in dut.c):
        d.append("fflags write: dut %s ref %s" % (
            "0x%x" % dut.c[1] if 1 in dut.c else "none",
            "0x%x" % ref.c[1] if 1 in ref.c else "none"))
    for r in sorted(set(ref.v) & set(dut.v)):
        if ref.v[r] != dut.v[r]:
            d.append("v%d: dut 0x%x ref 0x%x" % (r, dut.v[r], ref.v[r]))
    return d


def _vreg_one_sided(ref, dut, last_ref_v, last_dut_v):
    """Vector registers logged by one side only: the other side's
    register (last logged value, 0 at reset) must already hold the
    logged value."""
    d = []
    for r in sorted(set(ref.v) - set(dut.v)):
        if last_dut_v.get(r, 0) != ref.v[r]:
            d.append("v%d: ref wrote 0x%x, dut logged no write (dut v%d 0x%x)" % (
                r, ref.v[r], r, last_dut_v.get(r, 0)))
    for r in sorted(set(dut.v) - set(ref.v)):
        if last_ref_v.get(r, 0) != dut.v[r]:
            d.append("v%d: dut wrote 0x%x, ref logged no write (ref v%d 0x%x)" % (
                r, dut.v[r], r, last_ref_v.get(r, 0)))
    return d


def compare(ref, dut, context=4):
    """Returns (ok, first_divergence_one_line, detail_lines)."""
    last_ref_v, last_dut_v = {}, {}
    for i in range(min(len(ref), len(dut))):
        diffs = _diff(ref[i], dut[i])
        if not diffs and ref[i].kind == "I":
            diffs = _vreg_one_sided(ref[i], dut[i], last_ref_v, last_dut_v)
        last_ref_v.update(ref[i].v)
        last_dut_v.update(dut[i].v)
        if diffs:
            detail = ["first divergence at record %d (spike log line %d, dut trace line %d)"
                      % (i, ref[i].src, dut[i].src)]
            for j in range(max(0, i - context), i):
                detail.append("  ok   #%d %s" % (j, ref[j].describe()))
            detail.append("  REF  #%d %s" % (i, ref[i].describe()))
            detail.append("  DUT  #%d %s" % (i, dut[i].describe()))
            detail.extend("    " + x for x in diffs)
            one = "#%d %s: %s" % (i, ref[i].describe(), "; ".join(diffs))
            return False, one, detail
    if len(ref) != len(dut):
        i = min(len(ref), len(dut))
        if len(dut) < len(ref):
            one = "#%d: DUT trace ends; ref continues with %s" % (i, ref[i].describe())
        else:
            one = "#%d: ref ends at tohost; DUT continues with %s" % (i, dut[i].describe())
        return False, one, ["length: ref %d records, dut %d" % (len(ref), len(dut)), one]
    return True, "", ["%d records match" % len(ref)]


def truncate_at(recs, tohost):
    """DUT records up to and including the first store to tohost."""
    for i, r in enumerate(recs):
        if r.kind == "I" and any(a == tohost for a, _, _ in r.m):
            return recs[:i + 1], True
    return recs, False


# ---------------------------------------------------------------------
# riscv-dv trace CSV (scripts/riscv_trace_csv.py field layout)
# ---------------------------------------------------------------------
def write_csv(recs, path):
    with open(path, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["pc", "instr", "gpr", "csr", "binary",
                                           "mode", "instr_str", "operand", "pad"])
        w.writeheader()
        for r in recs:
            if r.kind == "E":
                w.writerow({"pc": "%016x" % r.pc, "instr": "trap", "gpr": "",
                            "csr": "mcause:%016x;mtval:%016x" % (r.cause, r.tval),
                            "binary": "", "mode": "" if r.priv < 0 else str(r.priv),
                            "instr_str": "trap cause=0x%x" % r.cause,
                            "operand": "", "pad": ""})
                continue
            gpr = ["%s:%016x" % (XABI[k], v) for k, v in sorted(r.x.items()) if k]
            gpr += ["%s:%016x" % (FABI[k], v) for k, v in sorted(r.f.items())]
            gpr += ["v%d:%0128x" % (k, v) for k, v in sorted(r.v.items())]
            csrs = ["%s:%016x" % (CSR_NAMES.get(k, "csr%03x" % k), v)
                    for k, v in sorted(r.c.items())]
            mnem, _, ops = r.asm.partition(" ")
            w.writerow({"pc": "%016x" % r.pc, "instr": mnem,
                        "gpr": ";".join(gpr), "csr": ";".join(csrs),
                        "binary": ("%04x" if r.ilen == 2 else "%08x") % r.insn,
                        "mode": str(r.priv), "instr_str": r.asm,
                        "operand": ops.replace(" ", ""), "pad": ""})


# ---------------------------------------------------------------------
# ELF helpers
# ---------------------------------------------------------------------
def elf_symbols(elf, nm="riscv64-unknown-elf-nm"):
    out = subprocess.run([nm, elf], check=True, capture_output=True, text=True).stdout
    syms = {}
    for line in out.splitlines():
        p = line.split()
        if len(p) == 3:
            syms[p[2]] = int(p[0], 16)
    return syms


def elf_entry(elf, readelf="riscv64-unknown-elf-readelf"):
    out = subprocess.run([readelf, "-h", elf], check=True, capture_output=True,
                         text=True).stdout
    m = re.search(r"Entry point address:\s+0x([0-9a-f]+)", out)
    return int(m.group(1), 16)


def elf_disasm(elf, objdump="riscv64-unknown-elf-objdump"):
    out = subprocess.run([objdump, "-d", "-M", "no-aliases,numeric", elf],
                         check=True, capture_output=True, text=True).stdout
    asm = {}
    for line in out.splitlines():
        m = re.match(r"^\s*([0-9a-f]+):\s+[0-9a-f]+\s+(.*)$", line)
        if m:
            asm[int(m.group(1), 16)] = m.group(2).split("#")[0].strip()
    return asm


def run(elf, spike_log, dut_trace, ref_csv=None, dut_csv=None, report=None):
    """Compare one run. Returns a dict with ok, divergence, ref/dut
    record counts and whether the DUT reached the tohost store."""
    syms = elf_symbols(elf)
    tohost = syms["tohost"]
    entry = elf_entry(elf)
    ref = parse_spike(spike_log, entry, tohost)
    # Records past the reference's end only matter as "DUT continues".
    dut_all = parse_dut(dut_trace, limit=len(ref) + 16)
    dut, dut_done = truncate_at(dut_all, tohost)
    if ref_csv or dut_csv:
        asm = elf_disasm(elf)
        for r in dut:
            if r.kind == "I":
                r.asm = asm.get(r.pc, "")
        if ref_csv:
            write_csv(ref, ref_csv)
        if dut_csv:
            write_csv(dut, dut_csv)
    ok, one, detail = compare(ref, dut)
    ref_done = bool(ref) and ref[-1].kind == "I" and any(
        a == tohost for a, _, _ in ref[-1].m)
    if report:
        with open(report, "w") as fh:
            fh.write("elf %s\nspike %s\ndut %s\n" % (elf, spike_log, dut_trace))
            fh.write("ref records %d (tohost reached: %s), dut records %d "
                     "(tohost reached: %s)\n" % (len(ref), ref_done, len(dut), dut_done))
            fh.write("\n".join(detail) + "\n")
            fh.write("RESULT %s\n" % ("MATCH" if ok else "MISMATCH"))
    ref_exit = None
    if ref_done:
        ref_exit = [d for a, _, d in ref[-1].m if a == tohost][0]
    return {"ok": ok, "divergence": one, "ref_records": len(ref),
            "dut_records": len(dut), "ref_tohost": ref_done, "dut_tohost": dut_done,
            "ref_exit": ref_exit}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--elf", required=True)
    ap.add_argument("--spike", required=True, help="spike -l --log-commits log")
    ap.add_argument("--dut", required=True, help="core_tb +sigil_trace file")
    ap.add_argument("--ref-csv")
    ap.add_argument("--dut-csv")
    ap.add_argument("--report")
    a = ap.parse_args()
    try:
        res = run(a.elf, a.spike, a.dut, a.ref_csv, a.dut_csv, a.report)
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as e:
        print("error: %s" % e, file=sys.stderr)
        return 2
    print("%s ref=%d dut=%d %s" % ("MATCH" if res["ok"] else "MISMATCH",
                                    res["ref_records"], res["dut_records"],
                                    res["divergence"]))
    return 0 if res["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
