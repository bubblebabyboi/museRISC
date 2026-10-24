#!/usr/bin/env python3
"""Generate pipe53_page_rand_<seed>_directed.S (#53 review, pipeline lens).

Random instruction blocks cut by a code-page boundary, run in M (bare,
the reference), S (Sv39) and VS (vsatp Sv39 under hgatp Sv39x4), all
identity-mapped 4K pages, and compared register for register. Each
block is a random mix of ALU/Zb*/Zicond, M (multi-cycle), loads and
stores (two data pages per block), pointer chases (an address from a
load), AMOs, LR/SC, FP (multi-cycle, dynamic rounding, flags), CSR
(sscratch, fflags, frm), vector (arithmetic, loads/stores, indexed,
vmv.x.s), forward branches and calls, FENCE.I/SFENCE.VMA/WFI and RVC
forms; its first part ends a code page and the rest starts the next
one, at a random instruction (sometimes with a 32-bit instruction
straddling the boundary). With FPGA_TIMING the translated fetch
reloads the fetch page register there (+1 cycle) and cold blocks
(SFENCE.VMA first, one in three) walk for fetch and data, so the
bubbles land at random points of random dependence chains.

Data: 16 pages from 0x300000, the first 2 KiB of each initialized; every
8th doubleword is a pointer to another such doubleword, the others are
values (stores never hit pointers). Each block stores x11-x17, x28-x31, f1-f4, its instret delta (drained
reads, exact) and v1, v2; S and VS must equal M (the instret delta is
not compared for the block an interrupt landed in: the test is
interrupt-transparent and also runs with --irq-timer-after sweeps).
Exit store 0 = pass; else (mode << 16) | (block + 1) (+ 0x8000 when
only the instret delta differs), mode 1 = S, 2 = VS; 0xE000 | mcause
on an unexpected trap; 0xF000 | mode if a run stored too few results.

With --hlv the modes are M, HS (Sv39) and U (Sv39, U pages, hstatus.HU)
and the blocks add HLV/HSV/HLVX (vsatp Sv39 + hgatp Sv39x4 identity,
hstatus.SPVP = 1), without sscratch, SFENCE.VMA, WFI or cold blocks.

With --vu the modes are M, VS and VU (vsatp: a U-page table for VU),
with the same user-safe vocabulary (no HLV).

Usage: gen_page_rand.py SEED [NBLOCKS] [--hlv | --vu]
"""
import random
import sys

PAGE = 4096
DATA = 0x300000
RES = 0x3C0000
STRIDE = 192

POOL = ["a1", "a2", "a3", "a4", "a5", "a6", "a7", "t3", "t4", "t5", "t6"]
CPOOL = ["a1", "a2", "a3", "a4", "a5"]          # x11-x15 (RVC rd'/rs')
FPOOL = ["f1", "f2", "f3", "f4", "f5", "f6", "f7"]
VDST = ["v1", "v2", "v3", "v5"]                  # v4 holds the indices
VSRC = ["v1", "v2", "v3", "v4", "v5"]


class Gen:
    def __init__(self, seed, hlv=False, vu=False):
        self.r = random.Random(seed)
        self.lab = 0
        self.hlv_mode = hlv or vu     # user-mode safe vocabulary
        self.hlv_ops = hlv

    def label(self):
        self.lab += 1
        return f"R{self.lab}"

    def reg(self):
        return self.r.choice(POOL)

    def creg(self):
        return self.r.choice(CPOOL)

    def base(self):
        return self.r.choice(["s1", "s5"])

    def doff(self, size, store, limit=1016):
        while True:
            off = self.r.randrange(0, limit + 1, size)
            if store and (off // 8) % 8 == 0:
                continue
            return off

    def alu(self):
        r = self.r
        k = r.randrange(6)
        d, a, b = self.reg(), self.reg(), self.reg()
        if k == 0:
            op = r.choice(["add", "sub", "xor", "or", "and", "sll", "srl",
                           "sra", "slt", "sltu", "addw", "subw", "sllw",
                           "srlw", "sraw"])
            return [(f"{op} {d}, {a}, {b}", 4)]
        if k == 1:
            op = r.choice(["addi", "xori", "ori", "andi", "slti", "addiw"])
            return [(f"{op} {d}, {a}, {r.randrange(-2048, 2048)}", 4)]
        if k == 2:
            op = r.choice(["slli", "srli", "srai"])
            return [(f"{op} {d}, {a}, {r.randrange(64)}", 4)]
        if k == 3:
            op = r.choice(["sh1add", "sh2add", "sh3add", "andn", "orn", "xnor",
                           "min", "max", "minu", "maxu", "rol", "ror",
                           "czero.eqz", "czero.nez", "bset", "bclr", "binv",
                           "bext", "clmul", "clmulh", "add.uw"])
            return [(f"{op} {d}, {a}, {b}", 4)]
        if k == 4:
            op = r.choice(["clz", "ctz", "cpop", "clzw", "cpopw", "rev8",
                           "orc.b", "sext.b", "sext.h", "zext.h"])
            return [(f"{op} {d}, {a}", 4)]
        return [(f"lui {d}, {r.randrange(1 << 20)}", 4)]

    def muldiv(self):
        op = self.r.choice(["mul", "mulh", "mulhu", "mulhsu", "mulw", "div",
                            "divu", "rem", "remu", "divw", "divuw", "remw",
                            "remuw"])
        return [(f"{op} {self.reg()}, {self.reg()}, {self.reg()}", 4)]

    def load(self):
        r = self.r
        op, sz = r.choice([("lb", 1), ("lh", 2), ("lw", 4), ("ld", 8),
                           ("lbu", 1), ("lhu", 2), ("lwu", 4), ("ld", 8)])
        return [(f"{op} {self.reg()}, {self.doff(sz, False)}({self.base()})", 4)]

    def store(self):
        op, sz = self.r.choice([("sb", 1), ("sh", 2), ("sw", 4), ("sd", 8)])
        return [(f"{op} {self.reg()}, {self.doff(sz, True)}({self.base()})", 4)]

    def chase(self):
        r = self.r
        p = self.reg()
        x = self.reg()
        out = [(f"ld {p}, {64 * r.randrange(1, 15)}(s1)", 4)]
        for _ in range(r.randrange(3)):
            out.append((f"addi {r.choice([q for q in POOL if q != p])}, "
                        f"{self.reg()}, {r.randrange(-64, 64)}", 4))
        op = r.choice(["ld", "lw", "lbu", "sd"])
        if op == "sd":
            out.append((f"sd {x}, {8 * r.randrange(1, 8)}({p})", 4))
        else:
            out.append((f"{op} {x}, {8 * r.randrange(1, 8)}({p})", 4))
        return out

    def amo(self):
        r = self.r
        a = self.reg()
        w = r.choice(["w", "d"])
        off = self.doff(4 if w == "w" else 8, True, 1016)
        op = r.choice(["amoadd", "amoswap", "amoxor", "amoand", "amoor",
                       "amomin", "amomax", "amominu", "amomaxu"])
        d = self.reg()
        s = self.reg()
        return [(f"addi {a}, {self.base()}, {off}", 4),
                (f"{op}.{w} {d}, {s}, ({a})", 4)]

    def lrsc(self):
        r = self.r
        regs = r.sample(POOL, 4)
        a, d, t, s = regs
        off = self.doff(8, True)
        lb = self.label()
        return [(f"addi {a}, {self.base()}, {off}", 4),
                (f"{lb}: lr.d {d}, ({a})", 4),
                (f"sc.d {t}, {s}, ({a})", 4),
                (f"bne {t}, x0, {lb}", 4)]

    def fp(self):
        r = self.r
        k = r.randrange(9)
        f = lambda: r.choice(FPOOL)
        if k == 0:
            return [(f"fcvt.d.l {f()}, {self.reg()}", 4)]
        if k == 1:
            op = r.choice(["fadd.d", "fsub.d", "fmul.d", "fdiv.d", "fmin.d",
                           "fmax.d", "fsgnjx.d"])
            return [(f"{op} {f()}, {f()}, {f()}", 4)]
        if k == 2:
            return [(f"fsqrt.d {f()}, {f()}", 4)]
        if k == 3:
            op = r.choice(["fmadd.d", "fmsub.d", "fnmadd.d", "fnmsub.d"])
            return [(f"{op} {f()}, {f()}, {f()}, {f()}", 4)]
        if k == 4:
            return [(f"fmv.x.d {self.reg()}, {f()}", 4)]
        if k == 5:
            return [(f"fmv.d.x {f()}, {self.reg()}", 4)]
        if k == 6:
            op = r.choice(["fcvt.l.d", "fcvt.lu.d", "fcvt.w.d"])
            return [(f"{op} {self.reg()}, {f()}", 4)]
        if k == 7:
            op = r.choice(["feq.d", "flt.d", "fle.d"])
            return [(f"{op} {self.reg()}, {f()}, {f()}", 4)]
        op, sz, st = r.choice([("fld", 8, False), ("flw", 4, False),
                               ("fsd", 8, True), ("fsw", 4, True)])
        return [(f"{op} {f()}, {self.doff(sz, st)}({self.base()})", 4)]

    def csr(self):
        r = self.r
        k = r.randrange(3, 6) if self.hlv_mode else r.randrange(6)
        if k == 0:
            return [(f"csrw sscratch, {self.reg()}", 4)]
        if k == 1:
            return [(f"csrr {self.reg()}, sscratch", 4)]
        if k == 2:
            return [(f"csrrw {self.reg()}, sscratch, {self.reg()}", 4)]
        if k == 3:
            return [(f"csrrs {self.reg()}, fflags, x0", 4)]
        if k == 4:
            return [(f"csrwi frm, {r.randrange(5)}", 4)]
        return [(f"csrrw {self.reg()}, fflags, {self.reg()}", 4)]

    def vec(self):
        r = self.r
        k = r.randrange(8)
        vd = r.choice(VDST)
        if k == 0:
            return [(f"vadd.vv {vd}, {r.choice(VSRC)}, {r.choice(VSRC)}", 4)]
        if k == 1:
            return [(f"vadd.vx {vd}, {r.choice(VSRC)}, {self.reg()}", 4)]
        if k == 2:
            return [(f"vmv.x.s {self.reg()}, {r.choice(VSRC)}", 4)]
        if k == 3:
            return [(f"vmv.v.x {vd}, {self.reg()}", 4)]
        if k == 4:
            return [(f"vle64.v {vd}, ({self.base()})", 4)]
        if k == 5:
            a = self.reg()
            return [(f"addi {a}, {self.base()}, 8", 4),
                    (f"vse64.v {r.choice(VSRC)}, ({a})", 4)]
        if k == 6:
            return [(f"vluxei64.v {vd}, ({self.base()}), v4", 4)]
        return [(f"vredsum.vs {vd}, {r.choice(VSRC)}, {r.choice(VSRC)}", 4)]

    def branch(self):
        r = self.r
        lb = self.label()
        op = r.choice(["beq", "bne", "blt", "bge", "bltu", "bgeu"])
        out = [(f"{op} {self.reg()}, {self.reg()}, {lb}", 4)]
        for _ in range(r.randrange(1, 4)):
            out += self.alu()
        out.append((f"{lb}: addi {self.reg()}, {self.reg()}, 1", 4))
        return out

    def call(self):
        if self.r.random() < 0.5:
            return [("jal ra, farfn", 4)]
        return [("jalr ra, 0(s6)", 4)]

    def misc(self):
        if self.hlv_mode:   # also runs in U: no SFENCE.VMA/WFI
            return [(self.r.choice(["fence", "fence.i", "nop"]), 4)]
        return [(self.r.choice(["fence", "fence.i", "sfence.vma x0, x0",
                                "wfi", "nop"]), 4)]

    def hlv(self):
        r = self.r
        a = self.reg()
        k = r.randrange(5)
        if k < 2:
            op, sz = r.choice([("hlv.b", 1), ("hlv.bu", 1), ("hlv.h", 2),
                               ("hlv.hu", 2), ("hlv.w", 4), ("hlv.wu", 4),
                               ("hlv.d", 8)])
            return [(f"addi {a}, {self.base()}, {self.doff(sz, False)}", 4),
                    (f"{op} {self.reg()}, ({a})", 4)]
        if k < 4:
            op, sz = r.choice([("hsv.b", 1), ("hsv.h", 2), ("hsv.w", 4),
                               ("hsv.d", 8)])
            return [(f"addi {a}, {self.base()}, {self.doff(sz, True)}", 4),
                    (f"{op} {self.reg()}, ({a})", 4)]
        op, sz = r.choice([("hlvx.hu", 2), ("hlvx.wu", 4)])
        return [(f"addi {a}, {self.base()}, {self.doff(sz, False)}", 4),
                (f"{op} {self.reg()}, ({a})", 4)]

    def rvc(self):
        r = self.r
        k = r.randrange(10)
        d = self.reg()
        c = self.creg()
        if k == 0:
            return [(f"c.addi {d}, {r.choice([i for i in range(-32, 32) if i])}", 2)]
        if k == 1:
            return [(f"c.mv {d}, {self.reg()}", 2)]
        if k == 2:
            return [(f"c.add {d}, {self.reg()}", 2)]
        if k == 3:
            return [(f"c.ld {c}, {self.doff(8, False, 248)}(s1)", 2)]
        if k == 4:
            return [(f"c.sd {c}, {self.doff(8, True, 248)}(s1)", 2)]
        if k == 5:
            return [(f"c.li {d}, {r.randrange(-32, 32)}", 2)]
        if k == 6:
            op = r.choice(["c.sub", "c.xor", "c.or", "c.and", "c.addw"])
            return [(f"{op} {c}, {self.creg()}", 2)]
        if k == 7:
            lb = self.label()
            return [(f"c.bnez {c}, {lb}", 2), (f"c.addi {d}, 3", 2),
                    (f"{lb}: c.nop", 2)]
        if k == 8:
            lb = self.label()
            return [(f"c.j {lb}", 2), (f"c.li {d}, 7", 2), (f"{lb}: c.nop", 2)]
        return [(f"c.slli {d}, {r.randrange(1, 64)}", 2)]

    def body(self, n):
        r = self.r
        kinds = [(self.alu, 18), (self.muldiv, 8), (self.load, 12),
                 (self.store, 8), (self.chase, 5), (self.amo, 3),
                 (self.lrsc, 2), (self.fp, 10), (self.csr, 5), (self.vec, 7),
                 (self.branch, 4), (self.call, 2), (self.misc, 1),
                 (self.rvc, 10)]
        if self.hlv_ops:
            kinds.append((self.hlv, 10))
        fns = [k for k, _ in kinds]
        wts = [w for _, w in kinds]
        out = []
        while len(out) < n:
            out += r.choices(fns, wts)[0]()
        return out


def driver(w, n, hlv=False, vu=False):
    w(f".equ NVAR, {n}")
    w(f".equ DATA, {DATA:#x}")
    w(f".equ RES, {RES:#x}")
    w(f".equ STRIDE, {STRIDE}")
    if hlv:
        utable = """    // U-mode table (ROOTU): identity 4K with U, VA 0..4M
    li t1, ROOTU
    li t2, L1U + 0x1000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    li t1, (L1U >> 2) | 1
    li t2, ROOTU
    sd t1, 0(t2)
    li t2, L1U
    li t1, (L0U >> 2) | 1
    sd t1, 0(t2)
    li t1, ((L0U + 0x1000) >> 2) | 1
    sd t1, 8(t2)
    li t1, 0xDF                 // V R W X U A D
    li t2, L0U
    li a0, 1024
1:  sd t1, 0(t2)
    li a1, (0x1000 >> 2)
    add t1, t1, a1
    addi t2, t2, 8
    addi a0, a0, -1
    bnez a0, 1b
    li t1, (1 << 9) | (1 << 8)     // hstatus.HU, SPVP: HLV/HSV from U, as VS
    csrs hstatus, t1
    li t1, 7
    csrw scounteren, t1"""
        modesel = """    li t1, (3 << 11) | (1 << 39)
    csrc mstatus, t1
    li t1, (8 << 60) | (ROOT >> 12)
    li t2, 2
    bne s9, t2, 1f
    li t1, (8 << 60) | (ROOTU >> 12)
1:  csrw satp, t1
    sfence.vma
    li t1, (3 << 11)               // 0: M, 1: HS (Sv39), 2: U (Sv39, U pages)
    beqz s9, 2f
    li t1, (1 << 11)
    li t2, 1
    beq s9, t2, 2f
    li t1, 0
2:  csrs mstatus, t1"""
    elif vu:
        utable = """    // VU table (ROOTU, as vsatp in mode 2): identity 4K with U
    li t1, ROOTU
    li t2, L1U + 0x1000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    li t1, (L1U >> 2) | 1
    li t2, ROOTU
    sd t1, 0(t2)
    li t2, L1U
    li t1, (L0U >> 2) | 1
    sd t1, 0(t2)
    li t1, ((L0U + 0x1000) >> 2) | 1
    sd t1, 8(t2)
    li t1, 0xDF                 // V R W X U A D
    li t2, L0U
    li a0, 1024
1:  sd t1, 0(t2)
    li a1, (0x1000 >> 2)
    add t1, t1, a1
    addi t2, t2, 8
    addi a0, a0, -1
    bnez a0, 1b
    li t1, 7
    csrw scounteren, t1"""
        modesel = """    li t1, (3 << 11) | (1 << 39)
    csrc mstatus, t1
    li t1, (8 << 60) | (ROOT >> 12)
    li t2, 2
    bne s9, t2, 1f
    li t1, (8 << 60) | (ROOTU >> 12)
1:  csrw vsatp, t1
    hfence.vvma
    li t1, (3 << 11)               // 0: M, 1: VS (two-stage), 2: VU (U pages)
    beqz s9, 2f
    li t1, (1 << 11) | (1 << 39)
    li t2, 1
    beq s9, t2, 2f
    li t1, (1 << 39)
2:  csrs mstatus, t1"""
    else:
        utable = ""
        modesel = """    li t1, (3 << 11) | (1 << 39)
    csrc mstatus, t1
    li t1, (3 << 11)               // 0: M, 1: S (Sv39), 2: VS (two-stage)
    beqz s9, 2f
    li t1, (1 << 11)
    li t2, 1
    beq s9, t2, 2f
    li t1, (1 << 11) | (1 << 39)
2:  csrs mstatus, t1"""
    w("""
.equ EXIT,   0x10000000
.equ ROOT,   0x390000           // Sv39 (satp and vsatp): identity 4K, VA 0..4M
.equ L1,     0x391000
.equ L0A,    0x392000
.equ GROOT,  0x3A0000           // Sv39x4 (16 KiB): identity 4K, GPA 0..4M
.equ GL1,    0x3A4000
.equ GL0A,   0x3A5000
.equ ROOTU,  0x398000           // U-mode table (--hlv)
.equ L1U,    0x399000
.equ L0U,    0x39A000
.equ MSTACK, 0x3FC000
.equ TSTACK, 0x3FF000

_start:
    li sp, MSTACK
    li t1, TSTACK
    csrw mscratch, t1
    la t1, handler_m
    csrw mtvec, t1
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1
    li t1, ROOT
    li t2, L1 + 0x1000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    li t1, GROOT
    li t2, GL1 + 0x1000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    li t1, (L1 >> 2) | 1
    li t2, ROOT
    sd t1, 0(t2)
    li t2, L1
    li t1, (L0A >> 2) | 1
    sd t1, 0(t2)
    li t1, ((L0A + 0x1000) >> 2) | 1
    sd t1, 8(t2)
    li t1, (EXIT >> 2) | 0xC7
    sd t1, 128 * 8(t2)
    li t1, 0xCF                 // V R W X A D
    li t2, L0A
    li a0, 1024
1:  sd t1, 0(t2)
    li a1, (0x1000 >> 2)
    add t1, t1, a1
    addi t2, t2, 8
    addi a0, a0, -1
    bnez a0, 1b
    li t1, (GL1 >> 2) | 1
    li t2, GROOT
    sd t1, 0(t2)
    li t2, GL1
    li t1, (GL0A >> 2) | 1
    sd t1, 0(t2)
    li t1, ((GL0A + 0x1000) >> 2) | 1
    sd t1, 8(t2)
    li t1, (EXIT >> 2) | 0xD7
    sd t1, 128 * 8(t2)
    li t1, 0xDF                 // V R W X U A D
    li t2, GL0A
    li a0, 1024
1:  sd t1, 0(t2)
    li a1, (0x1000 >> 2)
    add t1, t1, a1
    addi t2, t2, 8
    addi a0, a0, -1
    bnez a0, 1b
    li t1, (8 << 60) | (ROOT >> 12)
    csrw satp, t1
    csrw vsatp, t1
@UTABLE@
    li t1, (8 << 60) | (GROOT >> 12)
    csrw hgatp, t1
    sfence.vma
    hfence.gvma
    hfence.vvma
    li t1, (1 << 13) | (1 << 9)    // FS, VS = Initial
    csrs mstatus, t1
    csrs vsstatus, t1
    csrw medeleg, x0
    csrw mideleg, x0
    li t1, (1 << 7)
    csrw mie, t1                   // MTIE (taken in S/VS)
    li t1, 7
    csrw mcounteren, t1
    csrw hcounteren, t1
    li s9, 0                       // mode 0 = M, 1 = S, 2 = VS
run_mode:
    call init_data
    csrw fcsr, x0
    csrw sscratch, x0
    csrw vsscratch, x0
    li s10, RES
    slli t1, s9, 16
    add s10, s10, t1
    la t1, m_cont
    la t2, after_run
    sd t2, 0(t1)
    sd sp, 8(t1)
@MODESEL@
    la t1, chain_start
    csrw mepc, t1
    mret
after_run:
    li t1, RES + NVAR * STRIDE
    slli t2, s9, 16
    add t1, t1, t2
    beq s10, t1, 1f
    li t1, 0xF000
    or t1, t1, s9
    li t2, EXIT
    sd t1, 0(t2)
2:  j 2b
1:  addi s9, s9, 1
    li t1, 3
    blt s9, t1, run_mode
    li s9, 1
cmp_mode:
    li a0, RES
    slli a1, s9, 16
    add a1, a1, a0
    li a2, 0
1:  li a3, 0                       // byte offset in the record
    la t1, irq_rec
    ld t2, 0(t1)
    li a4, -1                      // offset exempt from the compare
    bne t2, s9, 2f
    ld t2, 8(t1)
    bne t2, a1, 2f
    li a4, 120                     // instret delta
2:  add t1, a0, a3
    ld t1, 0(t1)
    add t2, a1, a3
    ld t2, 0(t2)
    beq a3, a4, 3f
    beq t1, t2, 3f
    li t1, 120
    bne a3, t1, mismatch
    li t1, 0x8000
    add a2, a2, t1
    j mismatch
3:  addi a3, a3, 8
    li t1, STRIDE
    blt a3, t1, 2b
    addi a0, a0, STRIDE
    addi a1, a1, STRIDE
    addi a2, a2, 1
    li t1, NVAR
    blt a2, t1, 1b
    addi s9, s9, 1
    li t1, 3
    blt s9, t1, cmp_mode
    li t1, EXIT
    sd x0, 0(t1)
1:  j 1b
mismatch:
    slli t1, s9, 16
    addi a2, a2, 1
    or t1, t1, a2
    li t2, EXIT
    sd t1, 0(t2)
1:  j 1b

init_data:
    la a0, data_img
    li a2, 0
1:  slli a1, a2, 12
    li t1, DATA
    add a1, a1, t1
    li t1, 2048
    add a3, a1, t1
2:  ld t1, 0(a0)
    ld t2, 8(a0)
    sd t1, 0(a1)
    sd t2, 8(a1)
    addi a0, a0, 16
    addi a1, a1, 16
    blt a1, a3, 2b
    addi a2, a2, 1
    li t1, 16
    blt a2, t1, 1b
    ret

handler_m:
    csrrw sp, mscratch, sp
    sd t1, 0(sp)
    sd t2, 8(sp)
    csrr t1, mcause
    bltz t1, 1f
    addi t2, t1, -8
    bltz t2, 2f
    addi t2, t1, -11
    bgtz t2, 2f
    csrrw sp, mscratch, sp
    la t1, m_cont
    ld sp, 8(t1)
    ld t1, 0(t1)
    jr t1
1:  la t1, irq_rec
    sd s9, 0(t1)
    sd s10, 8(t1)
    ld t1, 0(sp)
    ld t2, 8(sp)
    csrrw sp, mscratch, sp
    mret
2:  li t2, 0xE000
    or t1, t1, t2
    li t2, EXIT
    sd t1, 0(t2)
3:  j 3b

    .balign 8
m_cont: .dword 0, 0
irq_rec: .dword -1, 0

chain_start:
    la s6, farfn
    j page_0
""".replace("@UTABLE@", utable).replace("@MODESEL@", modesel))


def emit(w, t, s, k):
    if s == 2:
        w("    .option rvc")
        w(f"    {t}")
        w("    .option norvc")
    else:
        w(f"    {t}")


def emit_tail(w, post, k):
    for t, s in post:
        emit(w, t, s, k)
    w("    j 1f")
    w("1:  csrr a0, instret")
    w("    sub a0, a0, s7")
    for i, rg in enumerate(POOL):
        w(f"    sd {rg}, {8 * i}(s10)")
    for i in range(4):
        w(f"    fsd f{i + 1}, {88 + 8 * i}(s10)")
    w("    sd a0, 120(s10)")
    w("    addi a0, s10, 128")
    w("    vse64.v v1, (a0)")
    w("    addi a0, s10, 160")
    w("    vse64.v v2, (a0)")
    w(f"    addi s10, s10, {STRIDE}")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    hlv = "--hlv" in sys.argv[1:]
    vu = "--vu" in sys.argv[1:]
    seed = int(args[0])
    nblk = int(args[1]) if len(args) > 1 else 250
    g = Gen(seed, hlv, vu)
    out = []
    w = out.append
    w(f"// GENERATED by sw/core-tests/gen_page_rand.py {seed} {nblk}"
      f"{' --hlv' if hlv else ''}{' --vu' if vu else ''} (#53 review,")
    w("// pipeline lens). Do not edit; regenerate.")
    for line in __doc__.strip().splitlines():
        w("// " + line if line else "//")
    w("    .option arch, +v")
    w("    .option arch, +h")
    w("    .option arch, +zba, +zbb, +zbc, +zbs, +zicond")
    w("    .option norvc")
    w("    .option norelax")
    w("    .text")
    w("    .globl _start")
    driver(w, nblk, hlv, vu)
    prev_post = None
    for k in range(nblk):
        r = g.r
        body = g.body(r.randrange(8, 25))
        # boundary after instruction j (0 <= j < len-1); a following
        # 32-bit instruction may straddle it
        j = r.randrange(len(body) - 1)
        pre_len = sum(s for _, s in body[:j + 1])
        split = j + 1
        if body[j + 1][1] == 4 and r.random() < 0.35:
            pre_len += 2
            split = j + 2
        pre, post = body[:split], body[split:]
        if k == 0:
            w("    .balign 4096")
            w("bnd_start:")
        w(f"page_{k}:")
        if prev_post is not None:
            emit_tail(w, prev_post, k - 1)
        cold = (k % 3 == 2) and not (hlv or vu)
        w(f"    // block {k}{' (cold)' if cold else ''}")
        if cold:
            w("    sfence.vma x0, x0")
        for rg in POOL:
            v = r.getrandbits(64) - (1 << 63) if r.random() < 0.6 \
                else r.randrange(-40, 40)
            w(f"    li {rg}, {v}")
        p1 = DATA + r.randrange(16) * PAGE + r.randrange(8) * 128
        p2 = DATA + r.randrange(16) * PAGE + r.randrange(8) * 128
        w(f"    li s1, {p1:#x}")
        w(f"    li s5, {p2:#x}")
        for i in range(1, 8):
            w(f"    fcvt.d.l f{i}, {POOL[i - 1]}")
        w("    vsetivli x0, 4, e64, m1, ta, ma")
        w("    vle64.v v1, (s1)")
        w("    vle64.v v2, (s5)")
        w("    vmv.v.x v3, a3")
        w("    vmv.v.x v5, a4")
        w("    vid.v v4")
        w("    vsll.vi v4, v4, 3")
        w("    j 1f")
        w("1:  csrr s7, instret")
        w(f"    j pre_{k}")
        base = "bnd_start" if k == 0 else f"bnd_{k - 1}"
        w(f"    .org {base} + {PAGE - pre_len}")
        w(f"pre_{k}:")
        w(f"    .set bnd_{k}, pre_{k} + {pre_len}")
        for t, s in pre:
            emit(w, t, s, k)
        prev_post = post
    w(f"page_{nblk}:")
    emit_tail(w, prev_post, nblk - 1)
    w("    ecall")
    w("1:  j 1b")
    w("    .balign 4096")
    w("    .skip 3000")
    w("farfn:")
    w("    addi a7, a7, 1")
    w("    ret")
    w("    .data")
    w("    .balign 64")
    w("data_img:")
    for pg in range(16):
        for jj in range(256):
            if jj % 8 == 0:
                v = DATA + ((pg + 5) % 16) * PAGE + ((jj * 8 + 192) % 1024)
            else:
                v = ((0x0101010101010101 * jj) ^ (pg << 48) ^ 0x123456789ABC) \
                    & 0xFFFFFFFFFFFFFFFF
            w(f"    .dword {v:#x}")
    sys.stdout.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
