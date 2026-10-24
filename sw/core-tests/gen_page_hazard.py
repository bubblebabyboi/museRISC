#!/usr/bin/env python3
"""Generate pipe53_page_hazard_directed.S (#53 review, pipeline lens).

Pipeline hazards cut by a code-page boundary. Each hazard kernel (a
short straight-line sequence: load-use, M/FP multi-cycle results, CSR
read-after-write, store->load, AMO, LR/SC, branches/jumps, AGU operands
forwarded from loads/M/CSR/FP/vector results, vector ops, FENCE.I,
SFENCE.VMA, RVC straddles) is emitted once per boundary position: the
instructions before the boundary end a 4 KiB code page and the rest
starts the next one. With FPGA_TIMING a translated fetch reloads the
fetch page register at every boundary (+1 cycle), so the bubble lands
between every producer/consumer pair of every kernel. Every other
variant starts with SFENCE.VMA (cold TLB: fetch and data walks).

The chain of variants runs three times, from one M-mode driver:
  M  (bare: the reference), S (Sv39, 4K identity pages), VS (vsatp Sv39
  identity under hgatp Sv39x4 identity: two-stage fetch and data).
Each variant stores its two result registers and its instret delta
(read after a jump, with MEM/WB drained, so exact); the S and VS
results must equal the M results (the delta is not compared for the
one variant an interrupt landed in). Interrupt-transparent (an M
timer interrupt at any point returns to the interrupted instruction),
so the test is also run with --irq-timer-after N sweeps.
Exit store 0 = pass; else (mode << 16) | (variant + 1), mode 1 = S,
2 = VS (+ 0x100 when only the instret delta differs); 0xE000 | mcause
on an unexpected trap; 0xF000 | mode if a run did not store every
result.
"""
import sys

PAGE = 4096

# Four-byte kernels: (name, [instructions]); the boundary is placed after
# each position 0..n-2. Labels: {u} is replaced by a unique tag.
K4 = [
    ("ld_use", ["ld a1, 0(s1)", "add a2, a1, a1", "add a4, a2, a1"]),
    ("ld_use2", ["ld a1, 8(s1)", "addi a5, x0, 1", "add a2, a1, a5",
                 "sub a4, a2, a1"]),
    ("lbu_use", ["lbu a1, 3(s1)", "slli a2, a1, 3", "or a4, a2, a1"]),
    ("lw_br", ["lw a1, 12(s1)", "bne a1, a3, L1{u}", "addi a2, x0, 7",
               "jal x0, L2{u}", "L1{u}: addi a2, x0, 9",
               "L2{u}: add a4, a2, a1"]),
    ("ptr2", ["ld a1, 64(s1)", "ld a2, 0(a1)", "ld a4, 8(a2)"]),
    ("ptr_wb", ["ld a1, 0(s1)", "addi a6, x0, 3", "ld a2, 0(a1)",
                "add a4, a2, a1"]),
    ("fld_use", ["fld f1, 8(s1)", "fadd.d f5, f1, f1", "fmv.x.d a2, f5",
                 "fmv.x.d a4, f1"]),
    ("fld_fsd", ["fld f1, 8(s1)", "fsd f1, 24(s1)", "ld a2, 24(s1)",
                 "fmv.x.d a4, f1"]),
    ("flw_box", ["flw f1, 12(s1)", "fmv.x.d a2, f1", "fadd.s f5, f1, f1",
                 "fmv.x.w a4, f5"]),
    ("st_fwd", ["add a1, a3, a4", "sd a1, 32(s1)", "ld a2, 32(s1)",
                "add a4, a2, a1"]),
    ("st_ld", ["sd a3, 40(s1)", "ld a2, 40(s1)", "addi a4, a2, 1"]),
    ("sb_ld", ["sb a3, 41(s1)", "ld a2, 40(s1)", "sh a4, 46(s1)",
               "ld a4, 40(s1)"]),
    ("amo_d", ["addi a5, s1, 48", "amoadd.d a2, a3, (a5)", "ld a4, 0(a5)",
               "add a4, a4, a2"]),
    ("amo_w", ["addi a5, s1, 52", "amoswap.w a2, a3, (a5)", "lw a4, 0(a5)",
               "xor a4, a4, a2"]),
    ("lrsc", ["addi a5, s1, 56", "L1{u}: lr.d a2, (a5)", "sc.d a4, a3, (a5)",
              "bne a4, x0, L1{u}", "ld a6, 0(a5)", "add a4, a4, a6"]),
    ("sc_nores", ["addi a5, s1, 24", "sc.d a2, a3, (a5)", "ld a4, 0(a5)",
                  "add a4, a4, a2"]),
    ("mul_use", ["mul a1, a3, a4", "add a2, a1, a3", "mulh a4, a1, a2"]),
    ("div_use", ["div a1, a3, a4", "add a2, a1, a1", "rem a4, a3, a4"]),
    ("div_div", ["divu a1, a3, a4", "remu a2, a1, a4", "addi a4, a2, 3"]),
    ("mulw_div", ["mulw a1, a3, a4", "divw a2, a1, a4", "remw a4, a1, a3"]),
    ("fdiv_sqrt", ["fdiv.d f1, f2, f3", "fsqrt.d f5, f1", "fmv.x.d a2, f5",
                   "fmv.x.d a4, f1"]),
    ("fflags", ["csrw fflags, x0", "fdiv.d f1, f2, f3", "csrr a2, fflags",
                "fadd.d f5, f1, f3", "csrr a4, fflags"]),
    ("fma", ["fmadd.d f1, f2, f3, f4", "fmsub.d f5, f1, f2, f3",
             "fmv.x.d a2, f5", "fmv.x.d a4, f1"]),
    ("frm", ["csrwi frm, 2", "fdiv.d f1, f2, f3", "fmv.x.d a2, f1",
             "csrwi frm, 0", "fdiv.d f5, f2, f3", "fmv.x.d a4, f5"]),
    ("csr_raw", ["csrw sscratch, a3", "csrr a2, sscratch",
                 "csrrw a4, sscratch, a2", "csrr a4, sscratch"]),
    ("csr_mul", ["csrrw a1, sscratch, a4", "mul a2, a1, a3",
                 "csrrs a4, sscratch, x0"]),
    ("csr_agu", ["csrw sscratch, s1", "csrr a1, sscratch", "ld a2, 8(a1)",
                 "add a4, a2, a1"]),
    ("mul_agu", ["addi a1, x0, 8", "mul a1, a1, a1", "add a5, s1, a1",
                 "ld a2, 0(a5)", "ld a4, 8(a2)"]),
    ("fp_agu", ["fmv.d.x f1, s1", "fmv.x.d a1, f1", "ld a2, 8(a1)",
                "add a4, a2, a1"]),
    ("br_taken", ["beq a3, a3, L1{u}", "addi a2, x0, 1", "addi a2, x0, 2",
                  "L1{u}: addi a4, x0, 4", "addi a2, a4, 3"]),
    ("br_nt", ["bne a3, a3, L1{u}", "addi a2, a3, 5", "L1{u}: addi a4, a2, 1"]),
    ("br_loop", ["addi a6, x0, 2", "L1{u}: addi a6, a6, -1", "add a2, a2, a6",
                 "bne a6, x0, L1{u}", "addi a4, a2, 1"]),
    ("jal_far", ["jal ra, farfn_a", "add a2, a2, a1", "addi a4, a2, 1"]),
    ("jalr_fwd", ["addi a5, a6, 0", "jalr ra, 0(a5)", "add a2, a2, a1",
                  "addi a4, a2, 1"]),
    ("jalr_ld", ["ld a5, 16(s1)", "jalr ra, 0(a5)", "add a2, a2, a1",
                 "addi a4, a2, 1"]),
    ("auipc", ["auipc a1, 0", "addi a2, a1, 12", "auipc a4, 0",
               "sub a4, a4, a1"]),
    ("fencei", ["sd a3, 24(s1)", "fence.i", "ld a2, 24(s1)", "addi a4, a2, 1"]),
    ("sfence", ["ld a1, 0(s1)", "sfence.vma x0, x0", "ld a2, 8(a1)",
                "add a4, a2, a1"]),
    ("fence", ["sd a3, 32(s1)", "fence rw, rw", "ld a2, 32(s1)",
               "addi a4, a2, 2"]),
    ("vle_use", ["vle64.v v1, (s1)", "vmv.x.s a2, v1", "vadd.vv v2, v1, v1",
                 "vslidedown.vi v3, v2, 3", "vmv.x.s a4, v3"]),
    ("vse_ld", ["vadd.vx v2, v1, a3", "addi a5, s1, 32", "vse64.v v2, (a5)",
                "ld a2, 40(s1)", "ld a4, 56(s1)"]),
    ("vidx", ["vluxei64.v v3, (s1), v4", "vmv.x.s a2, v3",
              "vslidedown.vi v5, v3, 1", "vmv.x.s a4, v5"]),
    ("vset_raw", ["vsetivli a1, 2, e32, m1, ta, ma", "vadd.vv v2, v1, v1",
                  "vmv.x.s a2, v2", "csrr a4, vl",
                  "vsetivli x0, 4, e64, m1, ta, ma"]),
    ("vset_ld", ["vsetivli x0, 3, e64, m1, ta, ma", "vle64.v v1, (s1)",
                 "vmv.x.s a2, v1", "csrr a4, vl",
                 "vsetivli x0, 4, e64, m1, ta, ma"]),
    ("ld_vx", ["ld a1, 8(s1)", "vadd.vx v2, v1, a1", "vmv.x.s a2, v2",
               "add a4, a2, a1"]),
    ("vmvxs_agu", ["vmv.x.s a1, v1", "add a2, a1, a3", "ld a4, 8(a1)"]),
    ("fcvt", ["fcvt.l.d a1, f2", "add a2, a1, a3", "fcvt.d.l f5, a2",
              "fmv.x.d a4, f5"]),
    ("ld2", ["ld a1, 0(s1)", "ld a2, 8(s1)", "add a4, a1, a2", "sub a2, a2, a1"]),
    ("ld_x0", ["ld x0, 0(s1)", "add a2, x0, a3", "addi a4, x0, 5"]),
    ("st_amo_ld", ["sd a4, 48(s1)", "addi a5, s1, 48", "amomax.d a2, a3, (a5)",
                   "ld a4, 48(s1)"]),
    ("wfi", ["addi a2, a3, 1", "wfi", "addi a4, a2, 1"]),
    # scalar results into vector operands (load-use and multi-cycle
    # producers feeding .vx/.vf, strides, bases, AVL) and back
    ("fld_vf", ["fld f1, 8(s1)", "vfadd.vf v2, v1, f1", "vmv.x.s a2, v2",
                "vslidedown.vi v3, v2, 1", "vmv.x.s a4, v3"]),
    ("flw_vf32", ["vsetivli x0, 4, e32, m1, ta, ma", "flw f1, 12(s1)",
                  "vfmul.vf v2, v1, f1", "vmv.x.s a2, v2",
                  "vsetivli x0, 4, e64, m1, ta, ma", "vmv.x.s a4, v2"]),
    ("fdiv_vf", ["fdiv.d f1, f2, f3", "vfmv.v.f v2, f1", "vmv.x.s a2, v2",
                 "fmv.x.d a4, f1"]),
    ("mul_vx", ["mul a1, a3, a4", "vadd.vx v2, v1, a1", "vmv.x.s a2, v2",
                "add a4, a1, a2"]),
    ("csr_vx", ["csrw sscratch, a3", "csrr a1, sscratch", "vadd.vx v2, v1, a1",
                "vmv.x.s a2, v2", "add a4, a2, a1"]),
    ("vfmvfs", ["vfmv.f.s f1, v1", "fadd.d f5, f1, f1", "fmv.x.d a2, f5",
                "fmv.x.d a4, f1"]),
    ("ld_vlse", ["lbu a1, 3(s1)", "andi a1, a1, 0x38", "vlse64.v v2, (s1), a1",
                 "vmv.x.s a2, v2", "vslidedown.vi v3, v2, 3", "vmv.x.s a4, v3"]),
    ("ld_vbase", ["ld a1, 0(s1)", "vle64.v v2, (a1)", "vmv.x.s a2, v2",
                  "vslidedown.vi v3, v2, 2", "vmv.x.s a4, v3"]),
    ("ld_vidx", ["ld a1, 64(s1)", "vluxei64.v v3, (a1), v4", "vmv.x.s a2, v3",
                 "vslidedown.vi v5, v3, 3", "vmv.x.s a4, v5"]),
    ("ld_avl", ["lbu a1, 3(s1)", "andi a1, a1, 3",
                "vsetvli a5, a1, e64, m1, ta, ma", "vadd.vv v2, v1, v1",
                "vmv.x.s a2, v2", "add a4, a5, a2",
                "vsetivli x0, 4, e64, m1, ta, ma"]),
    ("fcsr_raw", ["andi a1, a3, 0x7f", "csrw fcsr, a1", "csrr a2, fcsr",
                  "fadd.d f5, f2, f3", "csrrw a4, fcsr, x0"]),
]

# RVC kernels: (name, [(instr, size)], pre_len): pre_len bytes end the
# page (a 32-bit instruction at byte pre_len-2 straddles).
KC = [
    ("c_ld_add", [("ld a1, 0(s1)", 4), ("c.mv a2, a1", 2),
                  ("add a4, a2, a1", 4)], 8),
    ("c_ld_mul", [("c.ld a1, 8(s1)", 2), ("mul a2, a1, a3", 4),
                  ("c.add a2, a1", 2), ("c.mv a4, a2", 2)], 4),
    ("c_lw_br", [("c.lw a1, 4(s1)", 2), ("beq a1, a1, L1{u}", 4),
                 ("c.li a2, 1", 2), ("L1{u}: c.addi a2, 3", 2),
                 ("c.mv a4, a1", 2)], 4),
    ("c_j", [("c.li a2, 5", 2), ("c.j L1{u}", 2), ("c.li a2, 7", 2),
             ("L1{u}: c.addi a2, 1", 2), ("c.mv a4, a2", 2)], 4),
    ("c_agu", [("c.ld a1, 0(s1)", 2), ("c.mv a5, a1", 2), ("ld a2, 8(a5)", 4),
               ("c.add a2, a1", 2), ("c.mv a4, a5", 2)], 6),
    ("c_jalr", [("c.mv a5, a6", 2), ("c.jalr a5", 2), ("c.add a2, a1", 2),
                ("c.mv a4, a2", 2)], 4),
    ("c_fld", [("c.fld fs1, 8(s1)", 2), ("fadd.d f5, fs1, fs1", 4),
               ("fmv.x.d a2, f5", 4), ("fmv.x.d a4, fs1", 4)], 4),
    ("c_csr", [("c.mv a4, a3", 2), ("csrrw a1, sscratch, a4", 4),
               ("csrr a2, sscratch", 4), ("c.add a4, a1", 2)], 4),
    ("c_div", [("c.addi a4, 3", 2), ("div a2, a3, a4", 4), ("c.mv a4, a2", 2)],
     4),
    ("c_vle", [("c.mv a5, s1", 2), ("vle64.v v1, (a5)", 4),
               ("vmv.x.s a2, v1", 4), ("c.mv a4, a5", 2)], 4),
    ("c_amo", [("c.mv a5, s1", 2), ("c.addi a5, 16", 2),
               ("amoadd.d a2, a3, (a5)", 4), ("c.ld a4, 16(s1)", 2)], 6),
    ("c_lrsc", [("L1{u}: lr.d a2, (a5)", 4), ("c.nop", 2),
                ("sc.d a4, a3, (a5)", 4), ("bne a4, x0, L1{u}", 4),
                ("c.ld a4, 24(s1)", 2)], 8),
    ("c_fencei", [("c.nop", 2), ("fence.i", 4), ("c.li a2, 3", 2),
                  ("c.ld a4, 8(s1)", 2)], 4),
    ("c_sfence", [("c.nop", 2), ("sfence.vma x0, x0", 4),
                  ("c.ld a2, 8(s1)", 2), ("c.mv a4, a2", 2)], 4),
    ("c_vset", [("c.li a5, 3", 2), ("vsetvli a1, a5, e64, m1, ta, ma", 4),
                ("vadd.vv v2, v1, v1", 4), ("vmv.x.s a2, v2", 4),
                ("csrr a4, vl", 4), ("vsetivli x0, 4, e64, m1, ta, ma", 4)], 4),
]

DATA = 0x300000
RES = 0x3C0000


def main():
    out = []
    w = out.append
    variants = []  # (name, pre lines [(text,size)], post lines, pre_len)
    for name, ins in K4:
        for j in range(len(ins) - 1):
            pre = [(t, 4) for t in ins[:j + 1]]
            post = [(t, 4) for t in ins[j + 1:]]
            variants.append((f"{name}@{j}", pre, post, 4 * (j + 1)))
    for name, ins, pre_len in KC:
        # split so the pre part holds pre_len bytes (a straddler counts
        # entirely in pre; the assembler places it across the line)
        acc = 0
        pre, post = [], []
        for t, s in ins:
            if acc < pre_len:
                pre.append((t, s))
            else:
                post.append((t, s))
            acc += s
        variants.append((name, pre, post, pre_len))
    n = len(variants)

    w("// GENERATED by sw/core-tests/gen_page_hazard.py (#53 review, pipeline")
    w("// lens). Do not edit; regenerate.")
    for line in __doc__.strip().splitlines():
        w("// " + line if line else "//")
    w(f"// {n} variants.")
    w("    .option arch, +v")
    w("    .option arch, +h")
    w("    .option norvc")
    w("    .option norelax")
    w("    .text")
    w("    .globl _start")
    w(f".equ NVAR, {n}")
    w(f".equ DATA, {DATA:#x}")
    w(f".equ RES, {RES:#x}")
    w("""
.equ EXIT,   0x10000000
.equ ROOT,   0x390000           // Sv39 (satp and vsatp): identity 4K, VA 0..4M
.equ L1,     0x391000
.equ L0A,    0x392000
.equ L0B,    0x393000
.equ GROOT,  0x3A0000           // Sv39x4 (16 KiB): identity 4K, GPA 0..4M
.equ GL1,    0x3A4000
.equ GL0A,   0x3A5000
.equ GL0B,   0x3A6000
.equ MSTACK, 0x3F0000
.equ TSTACK, 0x3F8000

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
    // clear the root/L1 tables (the L0 tables are written in full)
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
    // Sv39: ROOT[0] -> L1; L1[0] -> L0A, L1[1] -> L0B, L1[128] = EXIT 2M
    li t1, (L1 >> 2) | 1
    li t2, ROOT
    sd t1, 0(t2)
    li t2, L1
    li t1, (L0A >> 2) | 1
    sd t1, 0(t2)
    li t1, (L0B >> 2) | 1
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
    // Sv39x4: GROOT[0] -> GL1; GL1[0] -> GL0A, GL1[1] -> GL0B, GL1[128] EXIT
    li t1, (GL1 >> 2) | 1
    li t2, GROOT
    sd t1, 0(t2)
    li t2, GL1
    li t1, (GL0A >> 2) | 1
    sd t1, 0(t2)
    li t1, (GL0B >> 2) | 1
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
    csrw mcounteren, t1            // S and VS read cycle/time/instret
    csrw hcounteren, t1
    li s9, 0                       // mode 0 = M, 1 = S, 2 = VS
run_mode:
    call init_data
    li s10, RES
    slli t1, s9, 14
    add s10, s10, t1
    la t1, m_cont
    la t2, after_run
    sd t2, 0(t1)
    sd sp, 8(t1)
    li t1, (3 << 11) | (1 << 39)
    csrc mstatus, t1               // MPP = U, MPV = 0
    li t1, (3 << 11)
    beqz s9, 2f
    li t1, (1 << 11)
    li t2, 1
    beq s9, t2, 2f
    li t1, (1 << 11) | (1 << 39)
2:  csrs mstatus, t1
    la t1, chain_start
    csrw mepc, t1
    mret
after_run:
    li t1, RES + NVAR * 32
    slli t2, s9, 14
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
    // compare S and VS against M
    li s9, 1
cmp_mode:
    li a0, RES
    slli a1, s9, 14
    add a1, a1, a0
    li a2, 0
1:  ld t1, 0(a0)
    ld t2, 0(a1)
    bne t1, t2, mismatch
    ld t1, 8(a0)
    ld t2, 8(a1)
    bne t1, t2, mismatch
    // instret delta, except in the variant an interrupt landed in
    la t1, irq_rec
    ld t2, 0(t1)
    bne t2, s9, 2f
    ld t2, 8(t1)
    beq t2, a1, 3f
2:  ld t1, 16(a0)
    ld t2, 16(a1)
    bne t1, t2, mismatch_ir
3:  addi a0, a0, 32
    addi a1, a1, 32
    addi a2, a2, 1
    li t1, NVAR
    blt a2, t1, 1b
    addi s9, s9, 1
    li t1, 3
    blt s9, t1, cmp_mode
    li t1, EXIT
    sd x0, 0(t1)
1:  j 1b
mismatch_ir:
    li t1, 0x100
    add a2, a2, t1
mismatch:
    slli t1, s9, 16
    addi a2, a2, 1
    or t1, t1, a2
    li t2, EXIT
    sd t1, 0(t2)
1:  j 1b

// data: 16 pages from DATA, first 1 KiB of each, copied from the
// pristine image (data_img); word j of page p is a pointer (to a word
// with the same property) when j % 8 == 0
init_data:
    la a0, data_img
    li a2, 0                       // page
1:  slli a1, a2, 12
    li t1, DATA
    add a1, a1, t1
    addi a3, a1, 1024
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

// M trap handler: interrupts return at once (transparent); an ECALL
// from the chain ends the run; anything else fails the test.
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
1:  la t1, irq_rec               // the variant it landed in
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
    li s0, 0
    j page_0
""")
    # far functions live on their own pages after the chain
    for k, (name, pre, post, pre_len) in enumerate(variants):
        cold = (k % 2) == 1
        p = DATA + (k % 16) * PAGE + ((k // 16) % 4) * 128
        if k == 0:
            w("    .balign 4096")
            w("bnd_start:")
        w(f"page_{k}:")
        if k > 0:
            emit_post(w, variants[k - 1], k - 1)
        w(f"    // variant {k}: {name}{' (cold)' if cold else ''}")
        if cold:
            w("    sfence.vma x0, x0")
        w("    j 1f")                       # drain: the read is exact
        w("1:  csrr s7, instret")
        c1 = (0x9E3779B97F4A7C15 * (k + 1)) & 0xFFFFFFFFFFFF
        c2 = ((k * 7919) % 997) + 3
        w(f"    li a3, {c1:#x}")
        w(f"    li a4, {c2}")
        w("    li a1, 0")
        w("    li a2, 0")
        w("    li a6, 0")
        w(f"    li s1, {p:#x}")
        w("    addi a5, s1, 24")
        w("    fcvt.d.l f2, a3")
        w("    fcvt.d.l f3, a4")
        w("    fcvt.d.l f4, a2")
        w("    vsetivli x0, 4, e64, m1, ta, ma")
        w("    vle64.v v1, (s1)")
        w("    vid.v v4")
        w("    vsll.vi v4, v4, 3")
        w("    la a6, farfn_b" if (k % 3 == 0) else "    la a6, farfn_a")
        w("    la t1, farfn_a")
        w("    sd t1, 16(s1)")
        w(f"    j pre_{k}")
        base = "bnd_start" if k == 0 else f"bnd_{k - 1}"
        w(f"    .org {base} + {PAGE - pre_len}")
        w(f"pre_{k}:")
        w(f"    .set bnd_{k}, pre_{k} + {pre_len}")
        for t, s in pre:
            emit_ins(w, t, s, k)
    w(f"page_{n}:")
    emit_post(w, variants[n - 1], n - 1)
    w("    ecall")
    w("1:  j 1b")
    for fn in ("farfn_a", "farfn_b"):
        w("    .balign 4096")
        w("    .skip 4000")
        w(f"{fn}:")
        w("    add a1, ra, x0")
        w("    addi a2, a3, 1")
        w("    ret")
    w("    .data")
    w("    .balign 64")
    w("data_img:")
    for pg in range(16):
        for j in range(128):
            if j % 8 == 0:
                v = DATA + ((pg + 5) % 16) * PAGE + ((j * 8 + 192) % 1024)
            else:
                v = ((0x0101010101010101 * j) ^ (pg << 48) ^ 0x123456789ABC) \
                    & 0xFFFFFFFFFFFFFFFF
            w(f"    .dword {v:#x}")
    sys.stdout.write("\n".join(out) + "\n")


def emit_ins(w, t, s, k):
    t = t.replace("{u}", f"_{k}")
    if s == 2:
        w("    .option rvc")
        w(f"    {t}")
        w("    .option norvc")
    else:
        w(f"    {t}")


def emit_post(w, v, k):
    name, pre, post, pre_len = v
    for t, s in post:
        emit_ins(w, t, s, k)
    w("    j 1f")
    w("1:  csrr t3, instret")
    w("    sub t3, t3, s7")
    w("    sd a2, 0(s10)")
    w("    sd a4, 8(s10)")
    w("    sd t3, 16(s10)")
    w("    addi s10, s10, 32")
    w("    slli t1, s0, 5")
    w("    sub s0, t1, s0")
    w("    add s0, s0, a2")
    w("    xor s0, s0, a4")


if __name__ == "__main__":
    main()
