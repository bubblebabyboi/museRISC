// FP vector directed test (issue #29 stage 9b): core
// integration of the OPF classes -- VS/FS gating, .vf
// scalar operand from the FP regfile, dynamic frm, accrued
// fflags, vfmv moves, masked/widening/reduction forms at
// LMUL>1, and illegal-SEW behavior. Element arithmetic
// bit-exactness is covered by the vec unit TB and (via the
// shared fp_eval) the FPU TB vs SoftFloat.
// Convention: t0 = test number, exit store 0 = pass.
    .option arch, +v
    .option norvc  // norvc last: gas 13 .option arch resets it
    .text
    .globl _start
_start:
    la sp, stack_top
    la t1, handler_m
    csrw mtvec, t1
    la t1, trap_stack_top
    addi t1, t1, -64
    csrw mscratch, t1

    // 1: FP vector op with VS on but FS=Off traps illegal.
    li t0, 1
    li t1, (1 << 9)               // VS=Initial
    csrs mstatus, t1
    li a1, 4
    vsetvli a0, a1, e32, m1, ta, ma
    vfadd.vv v8, v9, v10          // FS=Off -> cause 2
    la a1, trap_cause
    ld a1, 0(a1)
    li a2, 2
    bne a1, a2, fail
    li t1, (1 << 13)              // FS=Initial
    csrs mstatus, t1

    // 2: vfadd.vv e32 + vfmv.f.s readback (NaN-boxed).
    li t0, 2
    li a1, 0x3fc00000             // 1.5f
    fmv.w.x fa0, a1
    vfmv.v.f v8, fa0
    li a1, 0x40200000             // 2.5f
    fmv.w.x fa1, a1
    vfmv.v.f v9, fa1
    vfadd.vv v10, v8, v9          // 4.0f
    vfmv.f.s fa2, v10
    fmv.x.w a0, fa2
    li a2, 0x40800000             // 4.0f, sign-extended by fmv.x.w
    bne a0, a2, fail

    // 3: .vf scalar operand + fflags accrual (1/0 -> DZ).
    li t0, 3
    csrw fflags, x0
    li a1, 0                      // +0.0f
    fmv.w.x fa0, a1
    vfdiv.vf v10, v8, fa0         // 1.5/0 = +inf, DZ
    csrr a0, fflags
    li a2, 0x08                   // DZ only
    bne a0, a2, fail
    vfmv.f.s fa2, v10
    fmv.x.w a0, fa2
    li a2, 0x7f800000             // +inf
    bne a0, a2, fail

    // 4: dynamic frm (RTZ) applies to vector ops:
    // 1.0 + 2^-24 rounds to 1.0 under RTZ and to
    // 1.0000001 (0x3f800001) under RNE? No: halfway case
    // 2^-24 is exactly half-ulp of 1.0, RNE -> 1.0 too.
    // Use 1.0 + 3*2^-25 (0.75 ulp): RNE -> 0x3f800001,
    // RTZ -> 0x3f800000.
    li t0, 4
    li a1, 0x3f800000             // 1.0f
    fmv.w.x fa0, a1
    vfmv.v.f v8, fa0
    li a1, 0x33c00000             // 3*2^-25
    fmv.w.x fa1, a1
    csrwi frm, 0                  // RNE
    vfadd.vf v10, v8, fa1
    vfmv.f.s fa2, v10
    fmv.x.w a0, fa2
    li a2, 0x3f800001
    bne a0, a2, fail
    csrwi frm, 1                  // RTZ
    vfadd.vf v10, v8, fa1
    vfmv.f.s fa2, v10
    fmv.x.w a0, fa2
    li a2, 0x3f800000
    bne a0, a2, fail
    csrwi frm, 0

    // 5: reserved frm (5) makes a rounding FP vector op
    // illegal, but vfsgnj (no rounding) stays legal.
    li t0, 5
    csrwi frm, 5
    sd x0, trap_cause, t1
    vfadd.vv v10, v8, v9          // must trap
    la a1, trap_cause
    ld a1, 0(a1)
    li a2, 2
    bne a1, a2, fail
    vfsgnj.vv v10, v8, v9         // legal under frm=5
    csrwi frm, 0

    // 6: e16 FP vector is illegal (no Zfh).
    li t0, 6
    li a1, 4
    vsetvli a0, a1, e16, m1, ta, ma
    sd x0, trap_cause, t1
    vfadd.vv v10, v8, v9          // must trap
    la a1, trap_cause
    ld a1, 0(a1)
    li a2, 2
    bne a1, a2, fail

    // 7: e64 double math at LMUL=2 via memory round-trip:
    // buf = {1.5, 2.5, -0.5, 4.0}; vfmul by 2.0, vfredusum.
    li t0, 7
    li a1, 4
    vsetvli a0, a1, e64, m2, ta, ma
    la a1, dbuf
    vle64.v v8, (a1)
    li a1, 0x4000000000000000     // 2.0
    fmv.d.x fa0, a1
    vfmul.vf v10, v8, fa0         // {3, 5, -1, 8}
    la a1, dout
    vse64.v v10, (a1)
    ld a0, 8(a1)
    li a2, 0x4014000000000000     // 5.0
    bne a0, a2, fail
    vfmv.v.f v12, fa0             // seed vector (elem0 = 2.0)
    vfredusum.vs v14, v10, v12    // 2+3+5-1+8 = 17
    vfmv.f.s fa2, v14
    fmv.x.d a0, fa2
    li a2, 0x4031000000000000     // 17.0
    bne a0, a2, fail

    // 8: widening convert + narrowing round trip:
    // ints {3, -2} e32 -> vfwcvt.f.x.v (double) -> store;
    // doubles {2.5, -2.5} -> vfncvt.x.f.w e32 -> {2, -2} RNE.
    li t0, 8
    li a1, 2
    vsetvli a0, a1, e32, m1, ta, ma
    la a1, ibuf
    vle32.v v8, (a1)
    vfwcvt.f.x.v v10, v8
    la a1, dout
    vse64.v v10, (a1)             // EEW=64 store, EMUL=2
    ld a0, 0(a1)
    li a2, 0x4008000000000000     // 3.0
    bne a0, a2, fail
    ld a0, 8(a1)
    li a2, 0xc000000000000000     // -2.0
    bne a0, a2, fail
    la a1, dbuf2
    vle64.v v10, (a1)             // EEW=64 under e32 vtype
    vfncvt.x.f.w v12, v10
    vmv.x.s a0, v12
    li a2, 2                      // RNE(2.5) = 2
    bne a0, a2, fail

    // 9: masked vmflt.vf writes only mask-active bits;
    // old mask value preserved elsewhere.
    li t0, 9
    li a1, 8
    vsetvli a0, a1, e32, m1, ta, ma
    la a1, ibuf8
    vle32.v v8, (a1)              // raw words 0..7 as floats
    vfcvt.f.x.v v8, v8            // {0.,1.,...,7.}
    li a1, 0x40800000             // 4.0f
    fmv.w.x fa0, a1
    li a1, 0x55                   // mask bits 0,2,4,6 set
    vmv.v.x v0, a1                // mask bits 0,2,4,6 set
    vmv.v.i v16, -1               // old mask dest = all ones
    vmflt.vf v16, v8, fa0, v0.t   // bits<4 at active: 0,2 true
    vmv.x.s a0, v16
    li a2, 0xffffffffffffffaf     // bit4,6 cleared; others kept
    bne a0, a2, fail

    // 10: vfslide1down.vf pulls the FP scalar into the top
    // element; vfmerge.vfm selects per mask.
    li t0, 10
    la a1, ibuf8
    vle32.v v8, (a1)
    vfcvt.f.x.v v8, v8            // {0.,...,7.}
    li a1, 0x41200000             // 10.0f
    fmv.w.x fa0, a1
    vfslide1down.vf v10, v8, fa0  // {1,2,3,4,5,6,7,10}
    la a1, dout
    vse32.v v10, (a1)
    lw a0, 28(a1)
    li a2, 0x41200000
    bne a0, a2, fail
    lw a0, 0(a1)
    li a2, 0x3f800000             // 1.0f
    bne a0, a2, fail

    // 11: at SEW=32 an f register that is not a NaN-boxed single
    // reads as the canonical NaN in every .vf form, including the
    // moves, merge and slides that bypass the FPU (riscv-dv
    // regression, issue #8: they took the low 32 bits).
    li t0, 11
    li a1, 4
    vsetvli a0, a1, e32, m1, tu, mu
    li a1, 0x123456783f800000     // upper half not all ones
    fmv.d.x fa0, a1
    li a2, 0x7fc00000             // canonical NaN
    vfmv.v.f v8, fa0
    vmv.x.s a0, v8
    bne a0, a2, fail
    vmv.v.i v9, 0
    vfmv.s.f v9, fa0
    vmv.x.s a0, v9
    bne a0, a2, fail
    vmv.v.i v0, 1                 // mask: element 0 active
    vmv.v.i v10, 0
    vfmerge.vfm v10, v10, fa0, v0
    vmv.x.s a0, v10
    bne a0, a2, fail
    vfslide1up.vf v11, v10, fa0
    vmv.x.s a0, v11
    bne a0, a2, fail
    li a1, 0xffffffff3f800000     // NaN-boxed 1.0f: used as is
    fmv.d.x fa1, a1
    vfmv.v.f v8, fa1
    vmv.x.s a0, v8
    li a2, 0x3f800000
    bne a0, a2, fail

    j pass

handler_m:
    csrrw sp, mscratch, sp
    sd t1, 0(sp)
    sd t2, 8(sp)
    la t2, trap_cause
    csrr t1, mcause
    sd t1, 0(t2)
    csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
    ld t1, 0(sp)
    ld t2, 8(sp)
    csrrw sp, mscratch, sp
    mret

pass:
    li t1, 0x10000000
    sd x0, 0(t1)
1:  j 1b
fail:
    li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b

    .data
    .align 3
trap_cause: .dword 0
    .align 3
dout:   .skip 512
    .align 3
dbuf:   .dword 0x3ff8000000000000, 0x4004000000000000
        .dword 0xbfe0000000000000, 0x4010000000000000
        .skip 480
    .align 3
dbuf2:  .dword 0x4004000000000000, 0xc004000000000000
        .skip 496
    .align 2
ibuf:   .word 3, -2
        .skip 504
    .align 2
ibuf8:  .word 0, 1, 2, 3, 4, 5, 6, 7
        .skip 480
    .skip 512
stack_top:
    .skip 512
trap_stack_top:
