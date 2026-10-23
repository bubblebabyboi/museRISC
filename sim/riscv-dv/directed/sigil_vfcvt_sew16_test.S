# Directed program for the riscv-dv flow (issue #8): which FP vector
# conversions are legal at SEW 8 and 16 on a Zve64d core without Zvfh /
# Zvfhmin, against Spike. RVV 1.0: an encoding is reserved when the EEW
# of a floating-point operand is not a supported FP type (sec. 13);
# Zve32f/Zve64d implement all vector FP instructions for FP operands
# with EEW=32 (and 64); Zvfh adds the int8 <-> binary16 conversions at
# SEW=8 and Zvfhmin vfwcvt.f.f.v / vfncvt.f.f.w at SEW=16. At SEW=16 the
# integer <-> FP conversions whose FP side is 32 bits wide are therefore
# defined without either:
#   vfwcvt.f.x.v / vfwcvt.f.xu.v         int16 -> f32
#   vfncvt.x.f.w / vfncvt.xu.f.w and the .rtz forms   f32 -> int16
# while every form with a 16-bit FP operand (vfwcvt.f.f.v, vfwcvt.x[u].f.v,
# vfncvt.f.f.w, vfncvt.rod.f.f.w, vfncvt.f.x[u].w, all other FP at
# SEW=16) and every FP form at SEW=8 is reserved. Seeded with RDV_SEED:
# random data, mask, frm, ta/ma and AVL; e16 at LMUL mf4..m4 and e8.
# A trap resumes after the trapping instruction and is compared with
# the reference.
#
# Status: fails on the RTL as of 65a48ae (pre-existing, also on main):
# sigil_core.sv ex_fp_bad makes every FP vector instruction at SEW < 32
# illegal, so the core traps on the six legal conversions at SEW=16.

#ifndef RDV_SEED
#define RDV_SEED 1
#endif
#define ITERS 16
#define NVT 6

        .macro RND rd
        slli    t0, s0, 13
        xor     s0, s0, t0
        srli    t0, s0, 7
        xor     s0, s0, t0
        slli    t0, s0, 17
        xor     s0, s0, t0
        mv      \rd, s0
        .endm

        .macro FILL base, n
        mv      a6, \base
        li      a7, \n
1:      RND     a5
        sd      a5, 0(a6)
        addi    a6, a6, 8
        addi    a7, a7, -1
        bnez    a7, 1b
        .endm

        .section .text
        .globl _start
_start:
        la      t0, trap
        csrw    mtvec, t0
        li      t0, (3 << 13) | (3 << 9)
        csrs    mstatus, t0
        li      s0, 0x9e3779b97f4a7c15
        li      t0, RDV_SEED
        xor     s0, s0, t0
        la      s2, buf_a
        la      s3, buf_b
        li      s1, ITERS
iter:
        FILL    s2, 128
        FILL    s3, 128
        li      s5, 0
vt_loop:
        vl8re64.v v8, (s2)
        vl8re64.v v24, (s3)
        RND     a1
        andi    t1, a1, 0x3f8
        add     t1, t1, s2
        vl1re64.v v0, (t1)
        srli    a2, a1, 12
        andi    a2, a2, 7
        li      t1, 5
        remu    a2, a2, t1
        csrw    frm, a2
        csrw    fflags, x0
        la      a3, vtypes
        add     a3, a3, s5
        lbu     a4, 0(a3)
        srli    a5, a1, 8
        andi    a5, a5, 0xc0
        or      a4, a4, a5
        vsetvl  s9, x0, a4
        srli    a6, a1, 16
        andi    t1, a6, 1
        mv      a7, s9
        bnez    t1, 1f
        srli    a6, a6, 2
        addi    a7, s9, 1
        remu    a7, a6, a7
1:      vsetvl  s8, a7, a4
        # legal at SEW=16 (FP side 32 bits)
        vfwcvt.f.x.v  v16, v8
        vfwcvt.f.xu.v v16, v24, v0.t
        vfncvt.x.f.w  v16, v24
        vfncvt.xu.f.w v16, v24, v0.t
        vfncvt.rtz.x.f.w  v16, v24
        vfncvt.rtz.xu.f.w v16, v24
        # reserved at SEW=16 (a 16-bit FP operand)
        vfwcvt.f.f.v  v16, v8
        vfwcvt.x.f.v  v16, v8
        vfwcvt.xu.f.v v16, v8
        vfwcvt.rtz.x.f.v  v16, v8
        vfncvt.f.f.w  v16, v24
        vfncvt.rod.f.f.w v16, v24
        vfncvt.f.x.w  v16, v24
        vfncvt.f.xu.w v16, v24
        vfcvt.f.x.v   v16, v8
        vfadd.vv      v16, v8, v24
        csrr    a0, fflags
        addi    s5, s5, 1
        li      t1, NVT
        bltu    s5, t1, vt_loop
        addi    s1, s1, -1
        bnez    s1, iter

        li      gp, 1
        la      t5, tohost
        sw      gp, 0(t5)
1:      j       1b

        .align 2
trap:
        csrr    t6, mepc
        lhu     t5, 0(t6)
        andi    t5, t5, 3
        addi    t5, t5, -3
        addi    t6, t6, 2
        bnez    t5, 1f
        addi    t6, t6, 2
1:      csrw    mepc, t6
        mret

        .section .data
        .align 6; .global tohost; tohost: .dword 0
        .align 6; .global fromhost; fromhost: .dword 0
        # e16 m1 m2 m4 mf2 mf4, e8 m1
vtypes: .byte 0x08, 0x09, 0x0a, 0x0f, 0x0e, 0x00
        .align 6
buf_a:  .zero 1024
buf_b:  .zero 1024
buf_o:  .zero 1024
