# Directed program for the riscv-dv flow (issue #8): the scalar operand
# of every vector-scalar FP (.vf) instruction, against Spike. An f
# register read as a single (SEW=32) must be NaN-boxed (upper 32 bits
# all ones), otherwise it is the canonical NaN 0x7fc00000; SEW=64 reads
# it raw; FP at SEW 8/16 is reserved (no Zvfh). Seeded with RDV_SEED.
#
# 1. Matrix: each scalar of `scalars` (boxed and unboxed singles, NaN
#    payloads, doubles, near-boxed patterns) and 6 PRNG scalars (half
#    boxed) x every vtype of `vtypes` (e32 m1..m8 and mf2, e64 m1..m8,
#    e16 m1/m2, e8 m1) with random ta/ma, AVL (VLMAX or random), frm,
#    mask and data: every .vf instruction, masked and unmasked -- FPU
#    arithmetic, FMA, compares, vfmv.v.f, vfmerge.vfm, vfmv.s.f,
#    vfslide1up/down.vf, the widening .vf/.wf forms -- plus vfmv.f.s,
#    and fflags read back. Illegal forms (FP at SEW 8/16, widening at
#    SEW=64 or LMUL=8) must trap like Spike.
# 2. Producer -> consumer: every kind of f-register write (FP loads incl.
#    C.FLD, moves, single and double arithmetic, conversions, sign
#    injection with unboxed inputs, vfmv.f.s) followed by a .vf
#    instruction after 0-3 other instructions (EX/MEM, MEM/WB and
#    register-file paths), at SEW 32 and 64.
# 3. vtype changes (vsetvli/vsetivli/vsetvl, including vill) right
#    before a .vf instruction.
# 4. Scalar F instructions with unboxed operands (must be unaffected:
#    canonical NaN in arithmetic, raw bits for FMV.X.W and FSW).
# 5. Self-checks of the spec values (fail code in tohost on either
#    side): the program also fails on Spike if Spike disagrees.
#
# A trap resumes after the trapping instruction; every trap is compared
# with the reference (cause, epc, tval).

#ifndef RDV_SEED
#define RDV_SEED 1
#endif
#define NSCAL_FIXED 22
#define NSCAL (NSCAL_FIXED + 6)
#define NVT 12

# s0 PRNG state, s1 scalar index, s2/s3 source buffers A/B (1 KiB),
# s4 scratch buffer O, s5 vtype index, s8 vl, s9 VLMAX.
# fa0 is the scalar under test. t0 is the PRNG's temporary, t4 the
# self-check id, t5/t6 belong to the trap handler.

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

        # Overwrite 16 random dwords of a 1 KiB buffer with corner values.
        .macro SPECIALS base
        li      a7, 16
1:      RND     a5
        andi    a6, a5, 127
        slli    a6, a6, 3
        add     a6, a6, \base
        srli    a5, a5, 7
        andi    a5, a5, 15
        slli    a5, a5, 3
        la      a4, specials
        add     a4, a4, a5
        ld      a4, 0(a4)
        sd      a4, 0(a6)
        addi    a7, a7, -1
        bnez    a7, 1b
        .endm

        # Self-check: \reg must equal \val (check id \id).
        .macro EXPECT reg, val, id
        li      t4, \id
        li      t1, \val
        bne     \reg, t1, fail
        .endm

        # Every .vf instruction once or twice, with scalar \f.
        # v8/v24 sources, v16 destination group, v4-v7 mask results.
        .macro VFBLOCK f
        vfadd.vf    v16, v8, \f
        vfadd.vf    v16, v24, \f, v0.t
        vfsub.vf    v16, v8, \f
        vfrsub.vf   v16, v24, \f, v0.t
        vfmul.vf    v16, v8, \f
        vfdiv.vf    v16, v8, \f, v0.t
        vfrdiv.vf   v16, v24, \f
        vfmin.vf    v16, v8, \f
        vfmax.vf    v16, v24, \f, v0.t
        vfmax.vf    v16, v8, \f
        vfsgnj.vf   v16, v8, \f
        vfsgnj.vf   v16, v24, \f, v0.t
        vfsgnjn.vf  v16, v8, \f
        vfsgnjx.vf  v16, v24, \f
        vfsgnjx.vf  v16, v8, \f, v0.t
        vfmacc.vf   v16, \f, v8
        vfnmacc.vf  v16, \f, v24, v0.t
        vfmsac.vf   v16, \f, v8
        vfnmsac.vf  v16, \f, v24
        vfmadd.vf   v16, \f, v8, v0.t
        vfnmadd.vf  v16, \f, v24
        vfmsub.vf   v16, \f, v8
        vfnmsub.vf  v16, \f, v24, v0.t
        vmfeq.vf    v4, v8, \f
        vmfne.vf    v5, v24, \f, v0.t
        vmflt.vf    v6, v8, \f
        vmfle.vf    v7, v24, \f, v0.t
        vmfgt.vf    v4, v8, \f
        vmfge.vf    v5, v24, \f
        vfmv.v.f    v16, \f
        vmfeq.vf    v6, v16, \f
        vmfne.vf    v7, v16, \f, v0.t
        vfmerge.vfm v16, v8, \f, v0
        vfmv.s.f    v16, \f
        vfmv.s.f    v3, \f
        vfmv.f.s    fa5, v16
        vfmv.f.s    fa6, v8
        vfslide1up.vf   v16, v8, \f
        vfslide1up.vf   v16, v24, \f, v0.t
        vfslide1down.vf v16, v8, \f
        vfslide1down.vf v16, v24, \f, v0.t
        vfwadd.vf   v16, v8, \f
        vfwsub.vf   v16, v24, \f, v0.t
        vfwadd.wf   v16, v24, \f
        vfwsub.wf   v16, v24, \f, v0.t
        vfwmul.vf   v16, v8, \f
        vfwmacc.vf  v16, \f, v8
        vfwnmacc.vf v16, \f, v24, v0.t
        vfwmsac.vf  v16, \f, v8
        vfwnmsac.vf v16, \f, v24, v0.t
        csrr        a0, fflags
        .endm

        # f-register producer \p (writes fa0) then consumer \c (reads
        # fa0) after 0, 1, 2 and 3 other instructions.
        .macro PAIR p, c
        \p
        \c
        \p
        addi    a0, a0, 1
        \c
        \p
        addi    a0, a0, 1
        addi    a0, a0, 1
        \c
        \p
        addi    a0, a0, 1
        addi    a0, a0, 1
        addi    a0, a0, 1
        \c
        .endm

        # Every producer with a rotating consumer (current vtype).
        .macro PRODUCERS
        la      a1, fsrc
        PAIR    "flw fa0, 0(a1)",          "vfmv.v.f v16, fa0"
        PAIR    "flw fa0, 4(a1)",          "vfadd.vf v16, v8, fa0"
        PAIR    "fld fa0, 8(a1)",          "vfmv.v.f v16, fa0"
        PAIR    "fld fa0, 16(a1)",         "vfmerge.vfm v16, v8, fa0, v0"
        PAIR    "c.fld fa0, 24(a1)",       "vfslide1down.vf v16, v8, fa0"
        PAIR    "c.fld fa0, 0(a1)",        "vfmv.s.f v16, fa0"
        PAIR    "fmv.w.x fa0, a2",         "vfslide1up.vf v16, v8, fa0"
        PAIR    "fmv.d.x fa0, a3",         "vfmv.v.f v16, fa0"
        PAIR    "fmv.d.x fa0, a4",         "vmfeq.vf v4, v8, fa0"
        PAIR    "fadd.s fa0, fa1, fa2",    "vfmv.v.f v16, fa0"
        PAIR    "fsub.s fa0, fa1, fa7",    "vfmerge.vfm v16, v8, fa0, v0"
        PAIR    "fmul.s fa0, fa1, fa2",    "vfwadd.vf v16, v8, fa0"
        PAIR    "fdiv.s fa0, fa2, fa1",    "vfslide1down.vf v16, v8, fa0"
        PAIR    "fsqrt.s fa0, fa2",        "vfmv.s.f v16, fa0"
        PAIR    "fmadd.s fa0, fa1, fa2, fa1", "vfmv.v.f v16, fa0"
        PAIR    "fnmsub.s fa0, fa1, fa2, fa7", "vfmacc.vf v16, fa0, v8"
        PAIR    "fmin.s fa0, fa1, fa7",    "vfmv.v.f v16, fa0"
        PAIR    "fmax.s fa0, fa7, fa7",    "vfslide1up.vf v16, v8, fa0"
        PAIR    "fsgnj.s fa0, fa1, fa2",   "vfmv.v.f v16, fa0"
        PAIR    "fsgnjn.s fa0, fa7, fa2",  "vfmerge.vfm v16, v8, fa0, v0"
        PAIR    "fsgnjx.s fa0, fa2, fa7",  "vfmv.s.f v16, fa0"
        PAIR    "fsgnj.s fa0, fa7, fa7",   "vfmv.v.f v16, fa0"
        PAIR    "fsgnj.d fa0, fa7, fa7",   "vfmv.v.f v16, fa0"
        PAIR    "fsgnjn.d fa0, fa1, fa1",  "vfslide1down.vf v16, v8, fa0"
        PAIR    "fadd.d fa0, fa3, fa4",    "vfmv.v.f v16, fa0"
        PAIR    "fmin.d fa0, fa3, fa7",    "vfmerge.vfm v16, v8, fa0, v0"
        PAIR    "fcvt.s.d fa0, fa3",       "vfmv.v.f v16, fa0"
        PAIR    "fcvt.d.s fa0, fa1",       "vfmv.v.f v16, fa0"
        PAIR    "fcvt.s.w fa0, a2",        "vfslide1up.vf v16, v8, fa0"
        PAIR    "fcvt.s.wu fa0, a3",       "vfmv.s.f v16, fa0"
        PAIR    "fcvt.s.l fa0, a3",        "vfmv.v.f v16, fa0"
        PAIR    "fcvt.s.lu fa0, a4",       "vfadd.vf v16, v8, fa0"
        PAIR    "fcvt.d.l fa0, a3",        "vfmv.v.f v16, fa0"
        PAIR    "vfmv.f.s fa0, v8",        "vfmv.v.f v16, fa0"
        PAIR    "vfmv.f.s fa0, v24",       "vfslide1down.vf v16, v8, fa0"
        PAIR    "vfmv.f.s fa0, v8",        "vfwmacc.vf v16, fa0, v8"
        csrr    a0, fflags
        .endm

        .section .text
        .globl _start
_start:
        la      t0, trap
        csrw    mtvec, t0
        li      t0, (3 << 13) | (3 << 9)   # mstatus.FS and .VS = Dirty
        csrs    mstatus, t0
        li      s0, 0x9e3779b97f4a7c15
        li      t0, RDV_SEED
        xor     s0, s0, t0
        la      s2, buf_a
        la      s3, buf_b
        la      s4, buf_o

        # ---- 1. matrix: scalars x vtypes ---------------------------------
        li      s1, 0
scal_loop:
        FILL    s2, 128
        FILL    s3, 128
        SPECIALS s2
        SPECIALS s3
        li      t1, NSCAL_FIXED
        bgeu    s1, t1, 1f
        la      t1, scalars
        slli    t2, s1, 3
        add     t1, t1, t2
        fld     fa0, 0(t1)
        j       2f
1:      RND     a1                  # PRNG scalar, NaN-boxed half the time
        andi    t1, a1, 1
        beqz    t1, 3f
        li      t1, -1
        slli    t1, t1, 32
        or      a1, a1, t1
3:      fmv.d.x fa0, a1
2:      li      s5, 0
vt_loop:
        vl8re64.v v8, (s2)
        vl8re64.v v24, (s3)
        addi    t1, s2, 512
        vl8re64.v v16, (t1)
        RND     a1
        andi    t1, a1, 0x3f8
        add     t1, t1, s3
        vl1re64.v v0, (t1)          # random mask (8 bytes may run past
                                    # 1 KiB into buf_o: still defined)
        srli    a2, a1, 12          # frm 0-4
        andi    a2, a2, 7
        li      t1, 5
        remu    a2, a2, t1
        csrw    frm, a2
        csrw    fflags, x0
        la      a3, vtypes
        add     a3, a3, s5
        lbu     a4, 0(a3)
        srli    a5, a1, 8
        andi    a5, a5, 0xc0        # vta, vma
        or      a4, a4, a5
        vsetvl  s9, x0, a4          # VLMAX
        srli    a6, a1, 16
        andi    t1, a6, 3
        mv      a7, s9
        bnez    t1, 1f              # 3/4: AVL = VLMAX
        srli    a6, a6, 2
        addi    a7, s9, 1
        remu    a7, a6, a7          # 1/4: AVL in [0, VLMAX]
1:      vsetvl  s8, a7, a4
        VFBLOCK fa0
        addi    s5, s5, 1
        li      t1, NVT
        bltu    s5, t1, vt_loop
        addi    s1, s1, 1
        li      t1, NSCAL
        bltu    s1, t1, scal_loop

        # ---- 2. producer -> consumer -------------------------------------
        RND     a2                  # random single bits
        RND     a3                  # random dword (mostly unboxed)
        li      a4, 0xffffffff40490fdb      # boxed pi
        la      t1, fsrc
        sd      a3, 8(t1)
        flw     fa1, 0(t1)          # boxed single
        flw     fa2, 4(t1)          # boxed single
        fld     fa3, 8(t1)          # random double
        fld     fa4, 16(t1)         # another double
        li      t1, 0x123456783f800000      # unboxed 1.0f
        fmv.d.x fa7, t1
        vl8re64.v v8, (s2)
        vl8re64.v v24, (s3)
        csrw    fflags, x0
        vsetivli t1, 8, e32, m1, tu, mu
        PRODUCERS
        vsetvli t1, x0, e64, m2, ta, mu
        PRODUCERS
        vsetvli t1, x0, e32, mf2, tu, ma
        PRODUCERS

        # ---- 3. vtype changes right before a .vf -------------------------
        li      t1, 0x123456783f800000      # unboxed: raw at e64, NaN at e32
        fmv.d.x fa0, t1
        vsetvli t1, x0, e64, m1, tu, mu
        vfmv.v.f v16, fa0
        vsetvli t1, x0, e32, m1, tu, mu
        vfmv.v.f v16, fa0
        vsetivli t1, 3, e64, m2, ta, ma
        vfmv.s.f v16, fa0
        vsetivli t1, 5, e32, m2, ta, ma
        vfmv.s.f v16, fa0
        li      a5, 7
        li      a6, 0x10                    # e32 m1
        vsetvl  t1, a5, a6
        vfslide1up.vf v16, v8, fa0
        li      a6, 0x18                    # e64 m1
        vsetvl  t1, a5, a6
        vfslide1down.vf v16, v8, fa0
        li      a6, 0x10
        vsetvl  t1, a5, a6
        vfmerge.vfm v16, v8, fa0, v0
        vsetvli t1, x0, e16, m1, tu, mu
        vfmv.v.f v16, fa0                   # reserved: traps
        vsetvli t1, x0, e32, m1, tu, mu
        vfadd.vf v16, v8, fa0
        li      a6, 0x20                    # SEW=128: vill
        vsetvl  t1, a5, a6
        vfmv.v.f v16, fa0                   # vill: traps
        vsetvli t1, x0, e64, m1, tu, mu
        vfadd.vf v16, v8, fa0
        vsetvli t1, x0, e32, m1, tu, mu
        vfwmul.vf v16, v8, fa0
        vsetvli t1, x0, e64, m1, tu, mu
        vfwmul.vf v16, v8, fa0              # widening at e64: traps
        csrr    a0, fflags

        # ---- 4. scalar F with unboxed operands ---------------------------
        li      t1, 0x123456783f800000
        fmv.d.x fa6, t1
        li      t1, 0xffffffff40000000      # boxed 2.0f
        fmv.d.x fa7, t1
        csrw    fflags, x0
        fadd.s  fa0, fa6, fa7
        fsub.s  fa0, fa7, fa6
        fmul.s  fa0, fa6, fa7
        fdiv.s  fa0, fa7, fa6
        fsqrt.s fa0, fa6
        fmin.s  fa0, fa6, fa7
        fmax.s  fa0, fa7, fa6
        fsgnj.s fa0, fa6, fa7
        fsgnj.s fa0, fa7, fa6
        fsgnjn.s fa0, fa7, fa6
        fsgnjx.s fa0, fa7, fa6
        fmadd.s fa0, fa6, fa7, fa7
        fnmadd.s fa0, fa7, fa7, fa6
        feq.s   a0, fa6, fa7
        flt.s   a0, fa6, fa7
        fle.s   a0, fa7, fa6
        fclass.s a0, fa6
        fcvt.w.s a0, fa6
        fcvt.lu.s a0, fa6
        fcvt.d.s fa0, fa6
        fmv.x.w a0, fa6
        fsw     fa6, 0(s4)
        lw      a0, 0(s4)
        fmv.x.d a0, fa6
        fsd     fa6, 8(s4)
        ld      a0, 8(s4)
        csrr    a0, fflags

        # ---- 5. self-checks (spec values) --------------------------------
        li      t1, 0x123456783f800000      # unboxed (low word 1.0f)
        fmv.d.x fa0, t1
        li      t1, 0xffffffff3f800000      # boxed 1.0f
        fmv.d.x fa1, t1
        li      t1, 0xffffffff7f800001      # boxed signaling NaN
        fmv.d.x fa2, t1
        li      t1, 0xfffffffe3f800000      # one upper bit clear
        fmv.d.x fa3, t1
        li      t1, 0x00000000ffffffff      # upper half zero
        fmv.d.x fa4, t1
        li      t1, 0xbf800000              # -1.0f
        vsetivli t2, 4, e32, m1, tu, mu
        vmv.v.x v8, t1
        li      t1, 1
        vmv.v.x v0, t1                      # mask: element 0
        vfmv.v.f v16, fa0
        vmv.x.s a0, v16
        EXPECT  a0, 0x7fc00000, 1
        vmv.v.i v16, 0
        vfmv.s.f v16, fa0
        vmv.x.s a0, v16
        EXPECT  a0, 0x7fc00000, 2
        vfmerge.vfm v16, v8, fa0, v0
        vmv.x.s a0, v16
        EXPECT  a0, 0x7fc00000, 3
        vfslide1up.vf v16, v8, fa0
        vmv.x.s a0, v16
        EXPECT  a0, 0x7fc00000, 4
        vsetivli t2, 1, e32, m1, tu, mu
        vfslide1down.vf v16, v8, fa0
        vmv.x.s a0, v16
        EXPECT  a0, 0x7fc00000, 5
        vfsgnj.vf v16, v8, fa0              # sign of the canonical NaN: +
        vmv.x.s a0, v16
        EXPECT  a0, 0x3f800000, 6
        vfsgnjn.vf v16, v8, fa0
        vmv.x.s a0, v16
        EXPECT  a0, 0xffffffffbf800000, 7
        csrw    fflags, x0
        vfmin.vf v16, v8, fa0               # quiet NaN: the other operand
        vmv.x.s a0, v16
        EXPECT  a0, 0xffffffffbf800000, 8
        csrr    a0, fflags
        EXPECT  a0, 0, 9
        vmflt.vf v4, v8, fa0                # signaling compare: NV
        vmv.x.s a0, v4
        andi    a0, a0, 1
        EXPECT  a0, 0, 10
        csrr    a0, fflags
        EXPECT  a0, 0x10, 11
        vfmv.v.f v16, fa1                   # boxed: used as is
        vmv.x.s a0, v16
        EXPECT  a0, 0x3f800000, 12
        vfmv.v.f v16, fa2                   # boxed sNaN: bits kept
        vmv.x.s a0, v16
        EXPECT  a0, 0x7f800001, 13
        vfmv.v.f v16, fa3
        vmv.x.s a0, v16
        EXPECT  a0, 0x7fc00000, 14
        vfmv.v.f v16, fa4
        vmv.x.s a0, v16
        EXPECT  a0, 0x7fc00000, 15
        vfwadd.vf v16, v8, fa0              # widened canonical NaN
        vsetivli t2, 1, e64, m1, tu, mu
        vmv.x.s a0, v16
        EXPECT  a0, 0x7ff8000000000000, 16
        vfmv.v.f v16, fa0                   # e64: raw
        vmv.x.s a0, v16
        EXPECT  a0, 0x123456783f800000, 17
        vfmv.s.f v16, fa3
        vmv.x.s a0, v16
        EXPECT  a0, 0xfffffffe3f800000, 18
        vsetivli t2, 1, e32, m1, tu, mu
        vfmv.v.f v16, fa0
        vfmv.f.s fa5, v16                   # vfmv.f.s boxes
        fmv.x.d a0, fa5
        EXPECT  a0, 0xffffffff7fc00000, 19
        fmv.x.w a0, fa0                     # FMV.X.W: raw low word
        EXPECT  a0, 0x3f800000, 20
        fsgnj.s fa5, fa0, fa0               # scalar: canonical NaN
        fmv.x.d a0, fa5
        EXPECT  a0, 0xffffffff7fc00000, 21

        li      gp, 1
        la      t5, tohost
        sw      gp, 0(t5)
1:      j       1b

fail:   slli    gp, t4, 1
        ori     gp, gp, 1
        la      t5, tohost
        sw      gp, 0(t5)
1:      j       1b

        # Trap handler: resume after the 2- or 4-byte trapping instruction.
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
        # vsew << 3 | vlmul: e32 m1 m2 m4 m8 mf2, e64 m1 m2 m4 m8,
        # e16 m1 m2, e8 m1 (FP reserved at SEW 8/16).
vtypes:
        .byte 0x10, 0x11, 0x12, 0x13, 0x17, 0x18, 0x19, 0x1a, 0x1b
        .byte 0x08, 0x09, 0x00
        .align 3
scalars:
        .dword 0xffffffff3f800000   # boxed 1.0f
        .dword 0x123456783f800000   # unboxed, low word 1.0f
        .dword 0x7ff8000000000000   # canonical double NaN (unboxed)
        .dword 0xfffffffe3f800000   # bit 32 clear
        .dword 0x7fffffff3f800000   # bit 63 clear
        .dword 0xffffffff7f800001   # boxed signaling NaN
        .dword 0xffffffff7fc00001   # boxed quiet NaN with payload
        .dword 0xffffffff80000000   # boxed -0.0f
        .dword 0x00000000ffffffff   # upper half zero
        .dword 0x3ff0000000000000   # 1.0
        .dword 0xbff8000000000000   # -1.5
        .dword 0xffffffffff800000   # boxed -inf (a NaN as a double)
        .dword 0xfff0000000000001   # double signaling NaN
        .dword 0x0000000000000000   # +0.0
        .dword 0xffffffff00000000   # boxed +0.0f
        .dword 0x8000000000000000   # -0.0
        .dword 0xffffffff7f7fffff   # boxed max single
        .dword 0x7ff0000000000000   # +inf
        .dword 0xffffffff00000001   # boxed min subnormal single
        .dword 0x0000000100000000   # unboxed, low word +0.0f
        .dword 0xffffffff7fc00000   # boxed canonical NaN
        .dword 0x7fc000007fc00000   # unboxed, low word canonical NaN
specials:
        .dword 0x0000000000000000, 0xffffffffffffffff, 0x8000000000000000, 0x7fffffffffffffff
        .dword 0x7ff0000000000000, 0xfff0000000000000, 0x7ff8000000000000, 0x7ff0000000000001
        .dword 0x0000000000000001, 0x3ff0000000000000, 0xbff0000000000000, 0x0010000000000000
        .dword 0x7f800000ff800000, 0x7fc000007f800001, 0x0000000180000000, 0x3f800000c0000000
        .align 3
fsrc:   .dword 0x40490fdbbf800000, 0, 0x400921fb54442d18, 0
        .align 6
buf_a:  .zero 1024
buf_b:  .zero 1024
buf_o:  .zero 1024
