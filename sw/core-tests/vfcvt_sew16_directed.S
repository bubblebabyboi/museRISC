// int16 <-> f32 vector conversions at SEW=16 (issue #8, riscv-dv
// review). Zve32f/Zve64d define every vector FP instruction whose FP
// operands are EEW=32/64, so at SEW=16 (no Zvfh/Zvfhmin) these six
// are legal: vfwcvt.f.x.v, vfwcvt.f.xu.v (int16 -> f32) and
// vfncvt.x.f.w, vfncvt.xu.f.w, vfncvt.rtz.x.f.w, vfncvt.rtz.xu.f.w
// (f32 -> int16); every form with a 16-bit FP operand, and every FP
// form at SEW=8, stays reserved. Out-of-range f32 -> int16 results
// saturate and raise NV alone (an inexact 32-bit rounding step is
// not reported), as for scalar FCVT.
//  1: vfwcvt.f.x.v e16 m1: values, no flags.
//  2: vfwcvt.f.xu.v e16 m1: values, no flags.
//  3: vfncvt.x.f.w RNE: exact, inexact, saturating values; flags
//     per subset (NX only / NV only, incl. 32767.5 -> NV alone).
//  4: vfncvt.xu.f.w RNE: the same for uint16 (-1.0 -> 0 NV, -0.4
//     -> 0 NX, 65535.6 -> 65535 NV alone).
//  5: vfncvt.rtz.x.f.w / rtz.xu.f.w ignore frm.
//  6: vfncvt.x.f.w under frm RDN, RUP, RMM.
//  7: masked (mu) and tail (tu) elements unchanged.
//  8: LMUL 4 (widening into m8, narrowing from m8), last element;
//     LMUL 1/4 (widening into mf2).
//  9: still reserved: the forms with a 16-bit FP operand at e16,
//     every FP conversion at e8, widening at LMUL 8, narrowing from
//     LMUL 8 (e16 m8), misaligned vd groups, mstatus.FS = Off.
// Expected values follow the spec; the same program runs on Spike
// when assembled with -DSPIKE_HTIF (tohost exit) and passes there.
// Before the SEW=16 conversions were enabled (RTL up to 4958c3f)
// Sigil trapped all six and failed at test 1.
// Convention: t0 = test number, exit store 0 = pass.
    .option arch, +v
    .option norvc  // norvc last: gas 13 .option arch resets it

#ifdef SPIKE_HTIF
#define EXIT_PASS li t1, 1; la t2, tohost; sd t1, 0(t2); 1: j 1b
#define EXIT_FAIL slli t1, t0, 1; ori t1, t1, 1; la t2, tohost; sd t1, 0(t2); 1: j 1b
#else
#define EXIT_PASS li t1, 0x10000000; sd x0, 0(t1); 1: j 1b
#define EXIT_FAIL li t1, 0x10000000; sd t0, 0(t1); 1: j 1b
#endif

// 16-bit element \idx of the group stored from \vreg (vs8r.v: the
// register and the seven after it) must equal \val.
.macro CHK16 vreg, idx, val
    la a1, dout
    vs8r.v \vreg, (a1)
    li a2, \idx*2
    add a2, a2, a1
    lhu a0, 0(a2)
    li a2, \val
    bne a0, a2, fail
.endm
.macro CHK32 vreg, idx, val
    la a1, dout
    vs8r.v \vreg, (a1)
    li a2, \idx*4
    add a2, a2, a1
    lwu a0, 0(a2)
    li a2, \val
    bne a0, a2, fail
.endm
.macro CHKFLAGS val
    csrr a0, fflags
    li a2, \val
    bne a0, a2, fail
    csrw fflags, x0
.endm
// \insn must raise an illegal-instruction exception.
.macro TRAPS insn:vararg
    la a1, trap_cause
    sd x0, 0(a1)
    \insn
    la a1, trap_cause
    ld a0, 0(a1)
    li a2, 2
    bne a0, a2, fail
.endm
// \insn must not trap.
.macro NOTRAP insn:vararg
    la a1, trap_cause
    sd x0, 0(a1)
    \insn
    la a1, trap_cause
    ld a0, 0(a1)
    bnez a0, fail
.endm
// Load \n 32-bit words from \label into \vreg at e32 (vl = \n),
// then restore e16 with vl = \n.
.macro LDF32 vreg, label, n
    li a1, \n
    vsetvli x0, a1, e32, m1, tu, mu
    la a1, \label
    vle32.v \vreg, (a1)
    li a1, \n
    vsetvli x0, a1, e16, mf2, tu, mu
.endm

    .text
    .globl _start
_start:
    la sp, stack_top
    la t1, handler_m
    csrw mtvec, t1
    la t1, trap_stack_top
    addi t1, t1, -64
    csrw mscratch, t1
    li t1, (3 << 13) | (3 << 9)   // FS, VS = Dirty
    csrs mstatus, t1
    csrwi frm, 0
    csrw fflags, x0

    // 1: vfwcvt.f.x.v, int16 -> f32
    li t0, 1
    li a1, 8
    vsetvli x0, a1, e16, m1, tu, mu
    la a1, i16src
    vle16.v v4, (a1)
    NOTRAP vfwcvt.f.x.v v8, v4
    CHK32 v8, 0, 0x00000000
    CHK32 v8, 1, 0x3f800000
    CHK32 v8, 2, 0xbf800000
    CHK32 v8, 3, 0x46fffe00
    CHK32 v8, 4, 0xc7000000
    CHK32 v8, 5, 0x4640e400
    CHK32 v8, 6, 0xc0000000
    CHK32 v8, 7, 0xc6fffe00
    CHKFLAGS 0

    // 2: vfwcvt.f.xu.v, uint16 -> f32
    li t0, 2
    la a1, u16src
    vle16.v v4, (a1)
    NOTRAP vfwcvt.f.xu.v v8, v4
    CHK32 v8, 0, 0x00000000
    CHK32 v8, 1, 0x3f800000
    CHK32 v8, 2, 0x477fff00
    CHK32 v8, 3, 0x46fffe00
    CHK32 v8, 4, 0x47000000
    CHK32 v8, 5, 0x4640e400
    CHK32 v8, 6, 0x477ffe00
    CHK32 v8, 7, 0x47000100
    CHKFLAGS 0

    // 3: vfncvt.x.f.w, f32 -> int16, RNE
    li t0, 3
    LDF32 v4, f2i_a, 8
    li a1, 8
    vsetvli x0, a1, e16, mf2, tu, mu
    NOTRAP vfncvt.x.f.w v8, v4
    CHK16 v8, 0, 2                 // 1.5
    CHK16 v8, 1, 0xfffe            // -2.5 -> -2 (ties to even)
    CHK16 v8, 2, 0x7fff            // 32767.0
    CHK16 v8, 3, 0x7fff            // 32768.0: NV
    CHK16 v8, 4, 0x8000            // -32768.0
    CHK16 v8, 5, 0x8000            // -32769.0: NV
    CHK16 v8, 6, 0x7fff            // qNaN: NV
    CHK16 v8, 7, 0x8000            // -inf: NV
    CHKFLAGS 0x11
    li a1, 3                       // 1.5, -2.5, 32767.0: NX only
    vsetvli x0, a1, e16, mf2, tu, mu
    vfncvt.x.f.w v8, v4
    CHKFLAGS 0x01
    LDF32 v4, f2i_b, 4
    vfncvt.x.f.w v8, v4
    CHK16 v8, 0, 0x7fff            // 32767.5 -> 32768: NV alone
    CHK16 v8, 1, 0x7fff            // 32767.4 -> 32767: NX
    CHK16 v8, 2, 0x8000            // -32768.5 -> -32768 (even): NX
    CHK16 v8, 3, 0x8000            // -32768.6 -> -32769: NV alone
    CHKFLAGS 0x11
    li a1, 1
    vsetvli x0, a1, e16, mf2, tu, mu
    vfncvt.x.f.w v8, v4            // 32767.5 alone
    CHKFLAGS 0x10
    li a1, 4
    vsetvli x0, a1, e32, m1, tu, mu
    vslidedown.vi v12, v4, 3
    li a1, 1
    vsetvli x0, a1, e16, mf2, tu, mu
    vfncvt.x.f.w v8, v12           // -32768.6 alone
    CHK16 v8, 0, 0x8000
    CHKFLAGS 0x10

    // 4: vfncvt.xu.f.w, f32 -> uint16, RNE
    li t0, 4
    LDF32 v4, f2u_a, 8
    vfncvt.xu.f.w v8, v4
    CHK16 v8, 0, 0xffff            // 65535.0
    CHK16 v8, 1, 0xffff            // 65536.0: NV
    CHK16 v8, 2, 0x0000            // -1.0: NV
    CHK16 v8, 3, 0x0000            // -0.4: NX
    CHK16 v8, 4, 0xffff            // qNaN: NV
    CHK16 v8, 5, 0xffff            // +inf: NV
    CHK16 v8, 6, 2                 // 1.5: NX
    CHK16 v8, 7, 0xffff            // 65535.6 -> 65536: NV
    CHKFLAGS 0x11
    li a1, 2
    vsetvli x0, a1, e32, m1, tu, mu
    vslidedown.vi v12, v4, 6
    li a1, 2
    vsetvli x0, a1, e16, mf2, tu, mu
    vfncvt.xu.f.w v8, v12          // 1.5, 65535.6
    CHK16 v8, 0, 2
    CHK16 v8, 1, 0xffff
    CHKFLAGS 0x11
    li a1, 1
    vsetvli x0, a1, e32, m1, tu, mu
    vslidedown.vi v12, v4, 7
    vsetvli x0, a1, e16, mf2, tu, mu
    vfncvt.xu.f.w v8, v12          // 65535.6 alone: NV alone
    CHKFLAGS 0x10
    li a1, 1
    vsetvli x0, a1, e32, m1, tu, mu
    vslidedown.vi v12, v4, 3
    vsetvli x0, a1, e16, mf2, tu, mu
    vfncvt.xu.f.w v8, v12          // -0.4 alone: NX
    CHK16 v8, 0, 0
    CHKFLAGS 0x01

    // 5: rtz forms (frm = RUP, ignored)
    li t0, 5
    csrwi frm, 3
    LDF32 v4, rtz_a, 8
    vfncvt.rtz.x.f.w v8, v4
    CHK16 v8, 0, 2                 // 2.9
    CHK16 v8, 1, 0xfffe            // -2.9
    CHK16 v8, 2, 0x7fff            // 40000.0: NV
    CHK16 v8, 3, 0x0000            // -0.9
    CHK16 v8, 4, 0x7fff            // 65535.9: NV
    CHK16 v8, 5, 0x8000            // -40000.0: NV
    CHKFLAGS 0x11
    vfncvt.rtz.xu.f.w v8, v4
    CHK16 v8, 0, 2                 // 2.9
    CHK16 v8, 1, 0x0000            // -2.9: NV
    CHK16 v8, 2, 40000             // 40000.0
    CHK16 v8, 3, 0x0000            // -0.9: NX
    CHK16 v8, 4, 0xffff            // 65535.9 -> 65535: NX
    CHK16 v8, 5, 0x0000            // -40000.0: NV
    CHKFLAGS 0x11
    csrwi frm, 0

    // 6: dynamic rounding modes
    li t0, 6
    LDF32 v4, rm_a, 4              // 1.5, -1.5, 2.5, -2.5
    csrwi frm, 2                   // RDN
    vfncvt.x.f.w v8, v4
    CHK16 v8, 0, 1
    CHK16 v8, 1, 0xfffe
    CHK16 v8, 2, 2
    CHK16 v8, 3, 0xfffd
    csrwi frm, 3                   // RUP
    vfncvt.x.f.w v8, v4
    CHK16 v8, 0, 2
    CHK16 v8, 1, 0xffff
    CHK16 v8, 2, 3
    CHK16 v8, 3, 0xfffe
    csrwi frm, 4                   // RMM
    vfncvt.x.f.w v8, v4
    CHK16 v8, 0, 2
    CHK16 v8, 1, 0xfffe
    CHK16 v8, 2, 3
    CHK16 v8, 3, 0xfffd
    csrwi frm, 1                   // RTZ
    vfncvt.xu.f.w v8, v4
    CHK16 v8, 0, 1
    CHK16 v8, 1, 0                 // -1.5: NV
    CHK16 v8, 2, 2
    CHK16 v8, 3, 0
    CHKFLAGS 0x11
    csrwi frm, 0

    // 7: masked and tail elements undisturbed
    li t0, 7
    vsetvli t1, x0, e16, m2, tu, mu  // vl = VLMAX: all of v8-v9
    li a1, 0x5555
    vmv.v.x v8, a1                 // old vd
    li a1, 16
    vsetvli x0, a1, e16, m1, tu, mu
    li a1, 0x15                    // v0 = elements 0, 2, 4
    vmv.s.x v0, a1
    la a1, i16src
    vle16.v v4, (a1)
    li a1, 5
    vsetvli x0, a1, e16, m1, tu, mu
    vfwcvt.f.x.v v8, v4, v0.t
    CHK32 v8, 0, 0x00000000
    CHK32 v8, 1, 0x55555555        // masked off
    CHK32 v8, 2, 0xbf800000
    CHK32 v8, 3, 0x55555555        // masked off
    CHK32 v8, 4, 0xc7000000
    CHK32 v8, 5, 0x55555555        // tail
    CHK32 v8, 31, 0x55555555       // tail (v9)
    li a1, 16
    vsetvli x0, a1, e16, m1, tu, mu
    vmv.v.x v8, a1                 // old vd = 16
    LDF32 v4, f2i_a, 8
    li a1, 5
    vsetvli x0, a1, e16, mf2, tu, mu
    vfncvt.x.f.w v8, v4, v0.t      // elements 0, 2, 4
    CHK16 v8, 0, 2
    CHK16 v8, 1, 16
    CHK16 v8, 2, 0x7fff
    CHK16 v8, 3, 16
    CHK16 v8, 4, 0x8000
    CHK16 v8, 5, 16
    CHKFLAGS 0x01                  // 1.5, 32767.0, -32768.0

    // 8: LMUL 4 (m8 wide group) and LMUL 1/4
    li t0, 8
    li a1, 128
    vsetvli x0, a1, e16, m4, tu, mu
    vid.v v4                       // 0..127
    vrsub.vi v4, v4, 0             // 0, -1, ..., -127
    vfwcvt.f.x.v v8, v4            // v8-v15
    CHK32 v8, 0, 0x00000000
    CHK32 v8, 127, 0xc2fe0000      // -127.0
    vfwcvt.f.xu.v v16, v4          // v16-v23
    CHK32 v16, 127, 0x477f8100     // 65409.0
    vfncvt.x.f.w v24, v8           // back from m8 into v24-v27
    CHK16 v24, 127, 0xff81
    CHK16 v24, 1, 0xffff
    vfncvt.rtz.xu.f.w v0, v16      // v0-v3 (unmasked)
    CHK16 v0, 127, 0xff81
    CHK16 v0, 1, 0xffff
    CHKFLAGS 0
    li a1, 8
    vsetvli x0, a1, e16, mf4, tu, mu
    la a1, i16src
    vle16.v v4, (a1)
    vfwcvt.f.x.v v8, v4            // e32 mf2: vl 8
    CHK32 v8, 3, 0x46fffe00
    CHK32 v8, 7, 0xc6fffe00

    // 9: still reserved
    li t0, 9
    li a1, 8
    vsetvli x0, a1, e16, m1, tu, mu
    TRAPS vfwcvt.f.f.v v8, v4
    TRAPS vfwcvt.x.f.v v8, v4
    TRAPS vfwcvt.xu.f.v v8, v4
    TRAPS vfwcvt.rtz.x.f.v v8, v4
    TRAPS vfwcvt.rtz.xu.f.v v8, v4
    TRAPS vfncvt.f.f.w v8, v4
    TRAPS vfncvt.rod.f.f.w v8, v4
    TRAPS vfncvt.f.x.w v8, v4
    TRAPS vfncvt.f.xu.w v8, v4
    TRAPS vfcvt.f.x.v v8, v4
    TRAPS vfcvt.x.f.v v8, v4
    TRAPS vfcvt.rtz.xu.f.v v8, v4
    TRAPS vfadd.vv v8, v4, v4
    TRAPS vfsqrt.v v8, v4
    TRAPS vfmv.v.f v8, fa0
    TRAPS vfwadd.vv v8, v4, v4
    TRAPS vfredusum.vs v8, v4, v4
    TRAPS vfwcvt.f.x.v v9, v4      // vd group (2 regs) misaligned
    TRAPS vfncvt.x.f.w v8, v5      // vs2 group (2 regs) misaligned
    li a1, 8
    vsetvli x0, a1, e16, m8, tu, mu
    TRAPS vfwcvt.f.x.v v8, v0      // e32 m16
    TRAPS vfncvt.x.f.w v8, v16     // e32 m16 source
    li a1, 8
    vsetvli x0, a1, e8, m1, tu, mu
    TRAPS vfwcvt.f.x.v v8, v4      // int8 -> f16
    TRAPS vfwcvt.f.xu.v v8, v4
    TRAPS vfncvt.x.f.w v8, v4      // f16 -> int8
    TRAPS vfncvt.rtz.xu.f.w v8, v4
    li a1, 8
    vsetvli x0, a1, e16, m1, tu, mu
    li a1, 0x5555
    vmv.v.x v8, a1
    li t1, 3 << 13                 // mstatus.FS = Off
    csrc mstatus, t1
    TRAPS vfwcvt.f.x.v v8, v4
    TRAPS vfncvt.x.f.w v8, v4
    li t1, 3 << 13
    csrs mstatus, t1
    CHK32 v8, 0, 0x55555555        // nothing written

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
    EXIT_PASS
fail:
    EXIT_FAIL

    .data
#ifdef SPIKE_HTIF
    .align 6
    .globl tohost
tohost: .dword 0
    .align 6
    .globl fromhost
fromhost: .dword 0
#endif
    .align 3
trap_cause: .dword 0
    .align 6
dout:   .skip 512
    .align 4
// 0, 1, -1, 32767, -32768, 12345, -2, -32767
i16src: .half 0x0000, 0x0001, 0xffff, 0x7fff, 0x8000, 0x3039, 0xfffe, 0x8001
// 0, 1, 65535, 32767, 32768, 12345, 65534, 32769
u16src: .half 0x0000, 0x0001, 0xffff, 0x7fff, 0x8000, 0x3039, 0xfffe, 0x8001
    .align 4
// 1.5, -2.5, 32767.0, 32768.0, -32768.0, -32769.0, qNaN, -inf
f2i_a:  .word 0x3fc00000, 0xc0200000, 0x46fffe00, 0x47000000
        .word 0xc7000000, 0xc7000100, 0x7fc00000, 0xff800000
// 32767.5, 32767.4, -32768.5, -32768.6
f2i_b:  .word 0x46ffff00, 0x46fffecd, 0xc7000080, 0xc700009a
// 65535.0, 65536.0, -1.0, -0.4, qNaN, +inf, 1.5, 65535.6
f2u_a:  .word 0x477fff00, 0x47800000, 0xbf800000, 0xbecccccd
        .word 0x7fc00000, 0x7f800000, 0x3fc00000, 0x477fff9a
// 2.9, -2.9, 40000.0, -0.9, 65535.9, -40000.0, 0.0, 0.0
rtz_a:  .word 0x4039999a, 0xc039999a, 0x471c4000, 0xbf666666
        .word 0x477fffe6, 0xc71c4000, 0x00000000, 0x00000000
// 1.5, -1.5, 2.5, -2.5
rm_a:   .word 0x3fc00000, 0xbfc00000, 0x40200000, 0xc0200000
    .align 3
    .skip 512
stack_top:
    .skip 512
trap_stack_top:
