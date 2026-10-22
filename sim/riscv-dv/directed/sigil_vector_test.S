# Directed program for the riscv-dv flow (issue #8): RVV (Sigil:
# Zve64d, VLEN 512), which riscv-dv's pygen cannot generate, through
# the same Spike vs DUT commit-trace comparison. Whole vector registers
# are compared after every vector instruction that writes them, scalar
# results of vmv.x.s / vfmv.f.s / vsetvli as register writes. Vector
# stores are checked by loading the data back (the DUT trace logs
# scalar stores only).
        .section .text
        .globl _start
_start:
        li      t0, (3 << 13) | (3 << 9)   # mstatus.FS and .VS = Dirty
        csrs    mstatus, t0
        la      a0, vin
        la      a1, vout

        # e32, LMUL 1: integer arithmetic, reduction, masks
        li      t1, 16
        vsetvli t2, t1, e32, m1, ta, ma
        vle32.v v1, (a0)
        addi    a2, a0, 64
        vle32.v v2, (a2)
        vadd.vv v3, v1, v2
        vmul.vv v4, v1, v2
        vxor.vv v5, v3, v4
        vsll.vi v6, v5, 3
        vmv.v.i v7, 0
        vredsum.vs v7, v6, v7
        vmv.x.s s0, v7
        vmsltu.vv v0, v1, v2
        vadd.vv v8, v1, v2, v0.t
        vmerge.vvm v9, v1, v2, v0
        vse32.v v8, (a1)
        vle32.v v10, (a1)
        ld      s1, 0(a1)
        ld      s2, 56(a1)

        # e64, LMUL 2: wider groups, slides, FP
        li      t1, 12
        vsetvli t2, t1, e64, m2, tu, mu
        vle64.v v12, (a0)
        vslideup.vi v14, v12, 3
        vslidedown.vi v16, v12, 2
        vid.v   v18
        vadd.vx v18, v18, t2
        vrgather.vv v20, v12, v18
        vfcvt.f.xu.v v22, v18
        vfadd.vv v24, v22, v22
        vfmul.vv v26, v24, v22
        vfredosum.vs v28, v26, v22
        vfmv.f.s fa0, v28
        vmfeq.vv v0, v22, v24
        vcpop.m s3, v0
        vfirst.m s4, v0

        # e8, LMUL 8: VLMAX = 512 elements
        vsetvli t2, zero, e8, m8, ta, ma
        vid.v   v8
        vadd.vi v16, v8, 7
        vredmaxu.vs v24, v16, v8
        vmv.x.s s5, v24
        csrr    s6, vl
        csrr    s7, vtype

        li      gp, 1
        la      t5, tohost
        sw      gp, 0(t5)
1:      j       1b

        .section .data
        .align 6; .global tohost; tohost: .dword 0
        .align 6; .global fromhost; fromhost: .dword 0
        .align 6
vin:
        .dword 0x0123456789abcdef, 0xfedcba9876543210, 0x0f1e2d3c4b5a6978, 0x8796a5b4c3d2e1f0
        .dword 0x1111111122222222, 0x3333333344444444, 0x5555555566666666, 0x7777777788888888
        .dword 0x9999999aaaaaaaab, 0xbbbbbbbccccccccd, 0xdddddddeeeeeeeef, 0x0000000100000002
        .dword 0x8000000000000001, 0x7fffffffffffffff, 0x00000000ffffffff, 0xffffffff00000000
        .dword 0x243f6a8885a308d3, 0x13198a2e03707344, 0xa4093822299f31d0, 0x082efa98ec4e6c89
        .dword 0x452821e638d01377, 0xbe5466cf34e90c6c, 0xc0ac29b7c97c50dd, 0x3f84d5b5b5470917
        .align 6
vout:   .zero 256
