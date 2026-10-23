# Random RVV program for the riscv-dv flow (issue #8). riscv-dv's
# pygen has no vector instructions, so this program stands in for its
# vector tests: a xorshift64 PRNG seeded with RDV_SEED (the driver
# assembles it with -DRDV_SEED=<gen_seed>) picks, every iteration,
#   - fresh random source data (with FP/integer corner values mixed in),
#   - a random legal vtype (SEW 8..64, LMUL mf8..m8, ta/ma) and a random
#     AVL in [0, VLMAX],
#   - random vxrm and frm, and random scalar operands (some f operands
#     not NaN-boxed),
# then runs a block of vector instructions for that SEW: unit-stride,
# strided (positive, negative, zero), indexed, segment, fault-only-first,
# mask and whole-register loads and stores; integer, fixed-point,
# widening, narrowing, extension, mask, permutation, reduction and
# (SEW 32/64) FP arithmetic, masked and unmasked. Every vector register
# write is compared with Spike, scalar results as register writes,
# vl/vtype/vstart/vxsat/vcsr/fflags by reading them, vector store data
# by loading it back, and at the end of each iteration all 32 vector
# registers by storing and reloading them.
#
# Only architecturally defined behaviour is exercised: AVL <= VLMAX,
# no fractional LMUL with SEW > LMUL*ELEN (Sigil supports those, Spike
# sets vill: implementation-defined), no vfredusum (unordered), no
# stride-0 or unordered-indexed stores, no vstart != 0, all accesses
# element-aligned and inside the buffers. Sigil: Zve64d, VLEN 512.
#
# A trap (none expected) resumes after the trapping instruction, so a
# trap the reference does not take shows up as a trap record mismatch.

#ifndef RDV_SEED
#define RDV_SEED 1
#endif
#define ITERS 24

# s0 PRNG state, s1 iterations left, s2/s3 source buffers A/B (1 KiB),
# s4 store buffer O (1 KiB), s6 SEW code, s7 LMUL code, s8 vl,
# s9 VLMAX, s10 vtype.
# t0 is the PRNG's temporary; t5/t6 belong to the trap handler.

        .macro RND rd
        slli    t0, s0, 13
        xor     s0, s0, t0
        srli    t0, s0, 7
        xor     s0, s0, t0
        slli    t0, s0, 17
        xor     s0, s0, t0
        mv      \rd, s0
        .endm

        # Fill n dwords at base with PRNG output.
        .macro FILL base, n
        mv      a6, \base
        li      a7, \n
1:      RND     a5
        sd      a5, 0(a6)
        addi    a6, a6, 8
        addi    a7, a7, -1
        bnez    a7, 1b
        .endm

        # Overwrite 8 random dwords of a 1 KiB buffer with corner values.
        .macro SPECIALS base
        li      a7, 8
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

        # Store a register group and load it back: the reload logs all
        # eight registers, so the whole vector state is compared.
        .macro DUMP g
        vs8r.v  \g, (s4)
        vl8re64.v \g, (s4)
        .endm

        # The block of vector instructions for one SEW (the encoded EEW of
        # the memory instructions equals SEW, so EMUL = LMUL).
        # Register groups: v8, v16, v24 (aligned for LMUL 8); v0 is the
        # mask; v1-v7 are single-register operands/results.
        .macro OPS sew
        .if \sew == 8
        .set EB, 1
        .set IDXMASK, 0xff
        .elseif \sew == 16
        .set EB, 2
        .set IDXMASK, 0x3fe
        .elseif \sew == 32
        .set EB, 4
        .set IDXMASK, 0x3fc
        .else
        .set EB, 8
        .set IDXMASK, 0x3f8
        .endif
        RND     a1
        RND     a2
        srli    a3, a1, 3          # random slide offsets / scalars
        andi    a3, a3, 0x3ff
        # --- loads -------------------------------------------------------
        vle\sew\().v v8, (s2)
        vle\sew\().v v16, (s3), v0.t
        li      a0, EB
        andi    t1, a1, 1
        beqz    t1, .Lst1\@
        slli    a0, a0, 1
.Lst1\@:
        vlse\sew\().v v24, (s2), a0
        li      t1, 1024 - EB
        add     t1, t1, s3
        li      t2, -EB
        vlse\sew\().v v16, (t1), t2, v0.t
        vlse\sew\().v v24, (s3), x0
        li      t1, IDXMASK
        vand.vx v16, v8, t1        # in-bounds, element-aligned offsets
        vluxei\sew\().v v24, (s2), v16
        vloxei\sew\().v v24, (s3), v16, v0.t
        vle\sew\()ff.v v8, (s3)
        csrr    a4, vl
        vlm.v   v4, (s2)
        vl1re\sew\().v v3, (s3)
        vl2re\sew\().v v6, (s2)
        # --- stores (read back below) -----------------------------------
        vse\sew\().v v24, (s4)
        vsse\sew\().v v8, (s4), a0, v0.t
        vsoxei\sew\().v v24, (s4), v16
        vsm.v   v4, (s4)
        vs1r.v  v3, (s4)
        li      t1, 3               # LMUL m8: no 2-field segments
        beq     s7, t1, .Lnoseg\@
        vlseg2e\sew\().v v8, (s2)
        vsseg2e\sew\().v v16, (s4), v0.t
        vlsseg2e\sew\().v v24, (s3), a0
.Lnoseg\@:
        vl8re64.v v24, (s4)
        addi    t1, s4, 512
        vl8re64.v v24, (t1)
        # --- integer ------------------------------------------------------
        vle\sew\().v v8, (s2)
        vle\sew\().v v24, (s3)
        vadd.vv v16, v8, v24
        vsub.vx v16, v8, a1, v0.t
        vrsub.vi v16, v24, -7
        vand.vv v16, v8, v24
        vor.vx  v16, v8, a2
        vxor.vi v16, v24, 5, v0.t
        vsll.vv v16, v8, v24
        vsrl.vx v16, v8, a3
        vsra.vi v16, v24, 3
        vminu.vv v16, v8, v24, v0.t
        vmin.vx v16, v8, a1
        vmaxu.vx v16, v24, a2
        vmax.vv v16, v8, v24
        vmul.vv v16, v8, v24
        vmulh.vv v16, v8, v24
        vmulhu.vx v16, v8, a1, v0.t
        vmulhsu.vv v16, v24, v8
        vdivu.vv v16, v8, v24
        vdiv.vx v16, v8, a2
        vremu.vv v16, v24, v8, v0.t
        vrem.vv v16, v8, v24
        vmacc.vv v16, v8, v24
        vnmsac.vx v16, a1, v24
        vmadd.vv v16, v8, v24, v0.t
        vnmsub.vx v16, a2, v8
        vadc.vvm v16, v8, v24, v0
        vsbc.vxm v16, v8, a1, v0
        vmadc.vvm v5, v8, v24, v0
        vmsbc.vv v6, v8, v24
        vmerge.vvm v16, v8, v24, v0
        vmerge.vxm v16, v24, a1, v0
        vmv.v.v v24, v8
        vmv.v.x v16, a2
        vmv.v.i v16, -3
        vle\sew\().v v24, (s3)
        # compares (single-register mask results), then a fresh v0
        vmseq.vv v4, v8, v24
        vmsne.vx v5, v8, a1
        vmsltu.vv v6, v8, v24, v0.t
        vmslt.vx v7, v24, a2
        vmsleu.vi v4, v8, 9
        vmsle.vv v5, v24, v8
        vmsgtu.vx v6, v8, a1
        vmsgt.vi v7, v24, -2, v0.t
        vmslt.vv v0, v8, v24
        # fixed point (vxrm random)
        vsaddu.vv v16, v8, v24
        vsadd.vx v16, v8, a1, v0.t
        vssubu.vv v16, v8, v24
        vssub.vx v16, v24, a2
        vaaddu.vv v16, v8, v24
        vaadd.vx v16, v8, a1
        vasubu.vv v16, v24, v8, v0.t
        vasub.vv v16, v8, v24
        vsmul.vv v16, v8, v24
        vssrl.vv v16, v8, v24
        vssra.vx v16, v8, a3, v0.t
        # mask logical and mask-manipulation
        vmand.mm v5, v4, v0
        vmnand.mm v6, v4, v7
        vmandn.mm v5, v6, v4
        vmxor.mm v6, v4, v0
        vmor.mm v7, v5, v6
        vmnor.mm v5, v4, v7
        vmorn.mm v6, v0, v5
        vmxnor.mm v7, v4, v6
        vcpop.m a4, v4
        vcpop.m a5, v5, v0.t
        vfirst.m a6, v6
        vmsbf.m v5, v4
        vmsif.m v6, v4
        vmsof.m v7, v4
        viota.m v16, v4
        viota.m v24, v5, v0.t
        vid.v   v16
        # permutation
        vslideup.vx v16, v8, a3
        vslideup.vi v24, v8, 5, v0.t
        vslidedown.vx v16, v8, a3
        vslidedown.vi v24, v8, 3
        vslide1up.vx v16, v8, a1
        vslide1down.vx v24, v8, a2, v0.t
        vle\sew\().v v24, (s3)
        slli    t1, s9, 1           # indices in [0, 2*VLMAX)
        addi    t1, t1, -1
        vand.vx v24, v24, t1
        vrgather.vv v16, v8, v24
        vrgather.vx v16, v24, a3
        vrgather.vi v16, v8, 7, v0.t
        vcompress.vm v16, v8, v4
        vmv.x.s a4, v8
        vmv.s.x v3, a1
        vmv8r.v v16, v8
        # reductions
        vredsum.vs v1, v8, v3
        vredmaxu.vs v2, v8, v3, v0.t
        vredmax.vs v1, v24, v2
        vredminu.vs v2, v8, v1
        vredmin.vs v1, v24, v3
        vredand.vs v2, v8, v3
        vredor.vs v1, v24, v2, v0.t
        vredxor.vs v2, v8, v1
        # widening, narrowing, gather with 16-bit indices (EMUL 2*LMUL
        # for SEW 8): not with LMUL 8
        li      t1, 3
        beq     s7, t1, .Lnowide\@
        .if \sew <= 32
        vwaddu.vv v16, v8, v24
        vwadd.vx v16, v8, a1, v0.t
        vwsubu.vv v16, v24, v8
        vwsub.wv v16, v16, v8
        vwaddu.wx v16, v16, a2
        vwmul.vv v16, v8, v24
        vwmulu.vx v16, v8, a1
        vwmulsu.vv v16, v24, v8, v0.t
        vwmacc.vv v16, v8, v24
        vwmaccu.vx v16, a2, v8
        vwmaccsu.vv v16, v8, v24
        vwmaccus.vx v16, a1, v24, v0.t
        vnsrl.wv v8, v16, v24
        vnsra.wx v24, v16, a3
        vnsrl.wi v8, v16, 9, v0.t
        vnclipu.wv v8, v16, v24
        vnclip.wx v24, v16, a3, v0.t
        vle\sew\().v v8, (s2)
        vle\sew\().v v24, (s3)
        .endif
        # 16-bit gather indices in [0, 2*VLMAX), made at e16, then back
        # to this iteration's vtype and vl
        vsetvli t3, x0, e16, m8, tu, mu
        vle16.v v16, (s2)
        slli    t1, s9, 1
        addi    t1, t1, -1
        vand.vx v16, v16, t1
        vsetvl  t3, s8, s10
        vrgatherei16.vv v24, v8, v16
        vrgatherei16.vv v24, v8, v16, v0.t
.Lnowide\@:
        .if \sew <= 32
        vwredsumu.vs v1, v8, v2
        vwredsum.vs v2, v24, v1, v0.t
        .endif
        .if \sew >= 16
        vzext.vf2 v16, v8
        vsext.vf2 v24, v8, v0.t
        .endif
        .if \sew >= 32
        vzext.vf4 v16, v24
        vsext.vf4 v16, v8
        .endif
        .if \sew == 64
        vzext.vf8 v24, v8
        vsext.vf8 v16, v24, v0.t
        .endif
        .if \sew >= 32
        # --- floating point (frm random; fa1 random bits, often not a
        # NaN-boxed single; fa2 a NaN-boxed single) -----------------------
        vfadd.vv v16, v8, v24
        vfsub.vf v16, v8, fa1
        vfrsub.vf v16, v24, fa2, v0.t
        vfmul.vv v16, v8, v24
        vfdiv.vv v16, v8, v24, v0.t
        vfrdiv.vf v16, v24, fa2
        vfsqrt.v v16, v8
        vfmin.vv v16, v8, v24
        vfmax.vf v16, v24, fa1, v0.t
        vfsgnj.vv v16, v8, v24
        vfsgnjn.vf v16, v8, fa2
        vfsgnjx.vv v16, v24, v8
        vfmacc.vv v16, v8, v24
        vfnmacc.vf v16, fa2, v24, v0.t
        vfmsac.vv v16, v24, v8
        vfnmsac.vv v16, v8, v24
        vfmadd.vv v16, v8, v24
        vfnmadd.vf v16, fa1, v8
        vfmsub.vv v16, v24, v8, v0.t
        vfnmsub.vv v16, v8, v24
        vfclass.v v16, v8
        vfcvt.xu.f.v v16, v8
        vfcvt.x.f.v v16, v24, v0.t
        vfcvt.rtz.x.f.v v16, v8
        vfcvt.rtz.xu.f.v v16, v24
        vfcvt.f.xu.v v16, v8
        vfcvt.f.x.v v24, v24
        vfrec7.v v16, v8
        vfrsqrt7.v v16, v24, v0.t
        vmfeq.vv v4, v8, v24
        vmfne.vf v5, v8, fa2
        vmflt.vv v6, v24, v8, v0.t
        vmfle.vf v7, v8, fa1
        vmfgt.vf v4, v24, fa2
        vmfge.vf v5, v8, fa2
        vfmerge.vfm v16, v8, fa2, v0
        vfmv.v.f v16, fa1
        vfmv.s.f v3, fa2
        vfmv.s.f v2, fa1
        vfmv.f.s fa3, v8
        vfslide1up.vf v16, v8, fa1
        vfslide1down.vf v24, v8, fa2, v0.t
        vfslide1down.vf v16, v24, fa1
        vfmerge.vfm v24, v8, fa1, v0
        vfredosum.vs v1, v8, v3
        vfredmax.vs v2, v24, v1, v0.t
        vfredmin.vs v1, v8, v2
        .endif
        .if \sew == 32
        li      t1, 3
        beq     s7, t1, .Lnofw\@
        vfwadd.vv v16, v8, v24
        vfwsub.vf v16, v8, fa2, v0.t
        vfwadd.wv v16, v16, v24
        vfwsub.wf v16, v16, fa2
        vfwmul.vv v16, v8, v24
        vfwmacc.vv v16, v24, v8
        vfwnmacc.vf v16, fa2, v8
        vfwmsac.vv v16, v8, v24, v0.t
        vfwnmsac.vf v16, fa2, v24
        vfwcvt.f.f.v v16, v8
        vfwcvt.f.x.v v16, v24, v0.t
        vfwcvt.f.xu.v v16, v8
        vfwcvt.xu.f.v v16, v24
        vfwcvt.rtz.x.f.v v16, v8
        vfncvt.f.f.w v8, v16
        vfncvt.rod.f.f.w v24, v16, v0.t
        vfncvt.x.f.w v8, v16
        vfncvt.rtz.xu.f.w v24, v16
        vfncvt.f.x.w v8, v16
        vfncvt.f.xu.w v24, v16, v0.t
.Lnofw\@:
        vfwredosum.vs v1, v8, v2
        .endif
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
        li      s1, ITERS
        la      s2, buf_a
        la      s3, buf_b
        la      s4, buf_o

iter:
        FILL    s2, 128
        FILL    s3, 128
        SPECIALS s2
        SPECIALS s3
        vl8re64.v v0, (s2)
        vl8re64.v v8, (s3)
        addi    t1, s2, 512
        vl8re64.v v16, (t1)
        addi    t1, s3, 512
        vl8re64.v v24, (t1)

        # random vxrm, frm (0-4), occasionally clear vxsat and fflags
        RND     a1
        andi    a2, a1, 3
        csrw    vxrm, a2
        srli    a2, a1, 2
        andi    a2, a2, 7
        li      t1, 5
        remu    a2, a2, t1
        csrw    frm, a2
        andi    a3, a1, 0x300
        bnez    a3, 1f
        csrwi   vxsat, 0
        csrw    fflags, x0
1:
        # scalar FP operands: fa1 random 64 bits, fa2 a NaN-boxed single
        srli    a2, a1, 12
        andi    a2, a2, 0x3f8
        add     a2, a2, s2
        fld     fa1, 0(a2)
        flw     fa2, 4(a2)

        # random legal vtype, then AVL in [0, VLMAX]
        RND     a1
        andi    a2, a1, 31
        la      a3, vtypes
        add     a3, a3, a2
        lbu     a4, 0(a3)
        srli    a5, a1, 8
        andi    a5, a5, 0xc0       # vta, vma
        or      a4, a4, a5
        vsetvl  s9, x0, a4         # s9 = VLMAX
        srli    a1, a1, 16
        addi    a7, s9, 1
        remu    a7, a1, a7
        vsetvl  s8, a7, a4
        mv      s10, a4
        csrr    a5, vtype
        srli    s6, a4, 3
        andi    s6, s6, 7
        andi    s7, a4, 7

        li      t1, 1
        beqz    s6, sew8
        beq     s6, t1, sew16
        li      t1, 2
        beq     s6, t1, sew32
        j       sew64
sew8:   OPS     8
        j       iter_end
sew16:  OPS     16
        j       iter_end
sew32:  OPS     32
        j       iter_end
sew64:  OPS     64
iter_end:
        csrr    a0, vl
        csrr    a1, vtype
        csrr    a2, vstart
        csrr    a3, vxsat
        csrr    a4, vxrm
        csrr    a5, vcsr
        frflags a6
        frrm    a7
        DUMP    v0
        DUMP    v8
        DUMP    v16
        DUMP    v24
        addi    s1, s1, -1
        bnez    s1, iter

        li      gp, 1
        la      t5, tohost
        sw      gp, 0(t5)
1:      j       1b

        # Trap handler (no trap is expected): resume after the 2- or
        # 4-byte trapping instruction.
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
        # Legal vtypes (vsew << 3 | vlmul), 32 entries: every SEW with
        # LMUL 1, 2, 4, 8 and the fractional LMULs with SEW <= LMUL*64.
vtypes:
        .byte 0x00, 0x01, 0x02, 0x03, 0x05, 0x06, 0x07     # e8  m1 m2 m4 m8 mf8 mf4 mf2
        .byte 0x08, 0x09, 0x0a, 0x0b, 0x0e, 0x0f           # e16 m1 m2 m4 m8 mf4 mf2
        .byte 0x10, 0x11, 0x12, 0x13, 0x17                 # e32 m1 m2 m4 m8 mf2
        .byte 0x18, 0x19, 0x1a, 0x1b                       # e64 m1 m2 m4 m8
        .byte 0x10, 0x11, 0x12, 0x18, 0x19, 0x1a, 0x13     # extra FP-capable SEWs
        .byte 0x09, 0x02, 0x17, 0x1b
        .align 3
specials:
        .dword 0x0000000000000000, 0xffffffffffffffff, 0x8000000000000000, 0x7fffffffffffffff
        .dword 0x7ff0000000000000, 0xfff0000000000000, 0x7ff8000000000000, 0x7ff0000000000001
        .dword 0x0000000000000001, 0x3ff0000000000000, 0xbff0000000000000, 0x0010000000000000
        .dword 0x7f800000ff800000, 0x7fc000007f800001, 0x0000000180000000, 0x3f800000c0000000
        .align 6
buf_a:  .zero 1024
buf_b:  .zero 1024
buf_o:  .zero 1024
