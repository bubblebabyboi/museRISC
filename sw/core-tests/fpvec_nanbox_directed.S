// .vf scalar NaN-boxing directed test (issue #8, riscv-dv
// regression follow-up). RVV 1.0 sec. 13 and 16.2: with SEW=32
// the f-register scalar of every .vf instruction must be a
// NaN-boxed single (upper 32 bits all ones), otherwise the
// canonical NaN 0x7fc00000 is used; SEW=64 uses the register
// as is; FP at SEW 8/16 is reserved (no Zvfh). Covers each
// .vf class -- moves/merge/slides that bypass the FPU, FPU
// arithmetic, sign injection, min/max, FMA, compares (incl.
// fflags), widening .vf/.wf -- with unboxed, near-boxed and
// boxed scalars (incl. a boxed sNaN, which moves must keep);
// SEW=64 raw; vfmv.f.s boxing; f-register producers directly
// followed by a .vf (forwarding); vtype changes right before
// a .vf; scalar F instructions with unboxed operands; the
// reserved SEW 8/16 and widening forms; and vfmv.f.s /
// vfmv.s.f at vl=0.
// Expected values follow the spec; the same program runs on
// Spike when assembled with -DSPIKE_HTIF (tohost exit, link
// at 0x80000000) and passes there.
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

#define CNAN 0x7fc00000              // canonical single NaN
#define DNAN 0x7ff8000000000000      // canonical double NaN
#define UNBOXED 0x123456783f800000   // low word 1.0f, not boxed

// 32-bit element \idx of register \vreg must equal \val.
.macro CHK32 vreg, idx, val
    la a1, dout
    vs1r.v \vreg, (a1)
    lwu a0, \idx*4(a1)
    li a2, \val
    bne a0, a2, fail
.endm
// 64-bit element \idx of register \vreg must equal \val.
.macro CHK64 vreg, idx, val
    la a1, dout
    vs1r.v \vreg, (a1)
    ld a0, \idx*8(a1)
    li a2, \val
    bne a0, a2, fail
.endm
// Mask bits 0..3 of \vreg must equal \val.
.macro CHKM vreg, val
    la a1, dout
    vs1r.v \vreg, (a1)
    lbu a0, 0(a1)
    andi a0, a0, 0xf
    li a2, \val
    bne a0, a2, fail
.endm
.macro CHKFLAGS val
    csrr a0, fflags
    li a2, \val
    bne a0, a2, fail
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
.macro SETF freg, val
    li a0, \val
    fmv.d.x \freg, a0
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

    // Common state: e32 m1 vl=4; v8 = {1, -2, 3, -4} (single),
    // v0 mask = elements 0 and 2; fa0 unboxed.
    li a1, 4
    vsetvli a0, a1, e32, m1, tu, mu
    la a1, sbuf
    vle32.v v8, (a1)
    li a1, 5
    vmv.v.x v0, a1                // bits 0 and 2
    SETF fa0, UNBOXED

    // 1: vfmv.v.f: every element is the canonical NaN.
    li t0, 1
    vfmv.v.f v16, fa0
    CHK32 v16, 0, CNAN
    CHK32 v16, 3, CNAN

    // 2: vfmv.s.f: element 0 only.
    li t0, 2
    vmv.v.i v16, 0
    vfmv.s.f v16, fa0
    CHK32 v16, 0, CNAN
    CHK32 v16, 1, 0

    // 3: vfmerge.vfm: the scalar at mask-active elements.
    li t0, 3
    vfmerge.vfm v16, v8, fa0, v0
    CHK32 v16, 0, CNAN
    CHK32 v16, 1, 0xc0000000
    CHK32 v16, 2, CNAN
    CHK32 v16, 3, 0xc0800000

    // 4: vfslide1up.vf / vfslide1down.vf.
    li t0, 4
    vfslide1up.vf v16, v8, fa0
    CHK32 v16, 0, CNAN
    CHK32 v16, 1, 0x3f800000
    vfslide1down.vf v16, v8, fa0
    CHK32 v16, 2, 0xc0800000
    CHK32 v16, 3, CNAN

    // 5: FPU arithmetic: NaN results, no flags (quiet NaN).
    li t0, 5
    csrw fflags, x0
    vfadd.vf v16, v8, fa0
    CHK32 v16, 1, CNAN
    vfrsub.vf v16, v8, fa0
    CHK32 v16, 2, CNAN
    vfmul.vf v16, v8, fa0
    CHK32 v16, 3, CNAN
    vfdiv.vf v16, v8, fa0
    CHK32 v16, 0, CNAN
    vfrdiv.vf v16, v8, fa0
    CHK32 v16, 1, CNAN
    vfsub.vf v16, v8, fa0
    CHK32 v16, 2, CNAN
    CHKFLAGS 0

    // 6: min/max return the other operand; sign injection takes
    // the canonical NaN's sign (+).
    li t0, 6
    vfmin.vf v16, v8, fa0
    CHK32 v16, 1, 0xc0000000
    vfmax.vf v16, v8, fa0
    CHK32 v16, 3, 0xc0800000
    vfsgnj.vf v16, v8, fa0
    CHK32 v16, 1, 0x40000000
    vfsgnjn.vf v16, v8, fa0
    CHK32 v16, 0, 0xbf800000
    vfsgnjx.vf v16, v8, fa0
    CHK32 v16, 1, 0xc0000000
    CHKFLAGS 0

    // 7: FMA forms.
    li t0, 7
    vmv.v.v v16, v8
    vfmacc.vf v16, fa0, v8
    CHK32 v16, 0, CNAN
    vmv.v.v v16, v8
    vfmadd.vf v16, fa0, v8
    CHK32 v16, 1, CNAN
    vmv.v.v v16, v8
    vfnmsac.vf v16, fa0, v8
    CHK32 v16, 2, CNAN
    vmv.v.v v16, v8
    vfnmsub.vf v16, fa0, v8, v0.t
    CHK32 v16, 0, CNAN
    CHK32 v16, 1, 0xc0000000      // inactive: undisturbed
    CHKFLAGS 0

    // 8: compares: eq false, ne true (quiet); lt/le/gt/ge false
    // and invalid (signaling compares on a NaN).
    li t0, 8
    vmfeq.vf v4, v8, fa0
    CHKM v4, 0
    vmfne.vf v5, v8, fa0
    CHKM v5, 0xf
    CHKFLAGS 0
    vmflt.vf v6, v8, fa0
    CHKM v6, 0
    CHKFLAGS 0x10
    csrw fflags, x0
    vmfge.vf v7, v8, fa0
    CHKM v7, 0
    CHKFLAGS 0x10
    csrw fflags, x0
    vmfgt.vf v6, v8, fa0
    CHKFLAGS 0x10
    csrw fflags, x0
    vmfle.vf v7, v8, fa0
    CHKFLAGS 0x10
    csrw fflags, x0

    // 9: widening .vf / .wf: the canonical NaN widened.
    li t0, 9
    vfwadd.vf v16, v8, fa0        // e64 group v16-v17 (vl=4: in v16)
    CHK64 v16, 0, DNAN
    CHK64 v16, 3, DNAN
    vfwmul.vf v16, v8, fa0
    CHK64 v16, 1, DNAN
    la a1, dbuf
    vl2re64.v v24, (a1)           // wide vs2 for .wf
    vfwadd.wf v16, v24, fa0
    CHK64 v16, 0, DNAN
    vfwsub.wf v16, v24, fa0
    CHK64 v16, 2, DNAN
    vmv2r.v v16, v24
    vfwmacc.vf v16, fa0, v8
    CHK64 v16, 0, DNAN
    vmv2r.v v16, v24
    vfwnmsac.vf v16, fa0, v8, v0.t
    CHK64 v16, 0, DNAN
    CHK64 v16, 1, 0x4004000000000000  // inactive: undisturbed
    CHKFLAGS 0

    // 10: a boxed signaling NaN is moved bit-exact (no FP
    // operation), but is an sNaN to arithmetic.
    li t0, 10
    SETF fa1, 0xffffffff7f800001
    vfmv.v.f v16, fa1
    CHK32 v16, 2, 0x7f800001
    vmv.v.i v16, 0
    vfmv.s.f v16, fa1
    CHK32 v16, 0, 0x7f800001
    vfmerge.vfm v16, v8, fa1, v0
    CHK32 v16, 2, 0x7f800001
    vfslide1up.vf v16, v8, fa1
    CHK32 v16, 0, 0x7f800001
    vfslide1down.vf v16, v8, fa1
    CHK32 v16, 3, 0x7f800001
    CHKFLAGS 0
    vfadd.vf v16, v8, fa1
    CHK32 v16, 0, CNAN
    CHKFLAGS 0x10
    csrw fflags, x0

    // 11: near-boxed patterns are not boxed; boxed values are
    // used as is.
    li t0, 11
    SETF fa2, 0xfffffffe3f800000  // bit 32 clear
    vfmv.v.f v16, fa2
    CHK32 v16, 0, CNAN
    SETF fa2, 0x7fffffff3f800000  // bit 63 clear
    vfmerge.vfm v16, v8, fa2, v0
    CHK32 v16, 2, CNAN
    SETF fa2, 0x00000000ffffffff  // upper half zero
    vfslide1up.vf v16, v8, fa2
    CHK32 v16, 0, CNAN
    SETF fa2, 0xffffffff80000000  // boxed -0.0f
    vfmv.v.f v16, fa2
    CHK32 v16, 1, 0x80000000
    SETF fa2, 0xffffffff3f800000  // boxed 1.0f
    vfslide1down.vf v16, v8, fa2
    CHK32 v16, 3, 0x3f800000
    SETF fa2, 0x7fc000007fc00000  // canonical NaN, unboxed
    vfmv.s.f v16, fa2
    CHK32 v16, 0, CNAN

    // 12: SEW=64 reads the register raw (no boxing rule).
    li t0, 12
    li a1, 4
    vsetvli a0, a1, e64, m1, tu, mu
    la a1, dbuf
    vle64.v v8, (a1)              // {1.5, 2.5, -0.5, 4.0}
    vfmv.v.f v16, fa0
    CHK64 v16, 3, UNBOXED
    vmv.v.i v16, 0
    vfmv.s.f v16, fa0
    CHK64 v16, 0, UNBOXED
    CHK64 v16, 1, 0
    vfmerge.vfm v16, v8, fa0, v0
    CHK64 v16, 2, UNBOXED
    CHK64 v16, 1, 0x4004000000000000
    vfslide1up.vf v16, v8, fa0
    CHK64 v16, 0, UNBOXED
    vfslide1down.vf v16, v8, fa0
    CHK64 v16, 3, UNBOXED
    vmv.v.i v24, 0
    vfadd.vf v16, v24, fa0        // +0.0 + x = x
    CHK64 v16, 1, UNBOXED
    vfsgnjn.vf v16, v8, fa0       // sign bit of fa0 is 0
    CHK64 v16, 2, 0xbfe0000000000000
    vmfeq.vf v4, v16, fa1         // fa1 = 0xffffffff7f800001: a qNaN
    CHKM v4, 0
    vfmv.v.f v16, fa1             // a NaN at SEW=64: moved raw
    CHK64 v16, 0, 0xffffffff7f800001
    vfadd.vf v16, v8, fa1
    CHK64 v16, 0, DNAN
    CHKFLAGS 0

    // 13: vfmv.f.s NaN-boxes a single, moves a double raw.
    li t0, 13
    vfmv.f.s ft0, v8
    fmv.x.d a0, ft0
    li a2, 0x3ff8000000000000
    bne a0, a2, fail
    li a1, 4
    vsetvli a0, a1, e32, m1, tu, mu
    vfmv.v.f v16, fa0
    vfmv.f.s ft0, v16
    fmv.x.d a0, ft0
    li a2, 0xffffffff7fc00000
    bne a0, a2, fail

    // 14: f-register producers directly followed by a .vf
    // (forwarding from EX/MEM and MEM/WB, load-use).
    li t0, 14
    la a1, sbuf
    vle32.v v8, (a1)
    SETF ft3, UNBOXED
    SETF ft4, 0xffffffffbf800000  // boxed -1.0f
    SETF ft2, 0x4004000000000000  // 2.5
    li a3, 0x0bad0bad3f800000
    fmv.d.x ft1, a3
    vfmv.v.f v16, ft1
    CHK32 v16, 0, CNAN
    la a1, sbuf
    flw ft1, 4(a1)                // -2.0f
    vfmv.v.f v16, ft1
    CHK32 v16, 1, 0xc0000000
    la a1, dbuf
    fld ft1, 0(a1)                // 1.5 (a double)
    vfmv.v.f v16, ft1
    CHK32 v16, 2, CNAN
    fcvt.s.d ft1, ft2
    vfmv.v.f v16, ft1
    CHK32 v16, 3, 0x40200000
    fadd.d ft1, ft2, ft2          // 5.0 (a double)
    vfmerge.vfm v16, v8, ft1, v0
    CHK32 v16, 0, CNAN
    vfmv.f.s ft1, v8              // 1.0f, boxed
    vfmv.v.f v16, ft1
    CHK32 v16, 0, 0x3f800000
    fsgnj.s ft1, ft3, ft4         // NaN (unboxed rs1), sign of -1.0f
    vfmv.v.f v16, ft1
    CHK32 v16, 0, 0xffc00000
    fmv.w.x ft1, a3               // low word 1.0f, boxed
    vfslide1up.vf v16, v8, ft1
    CHK32 v16, 0, 0x3f800000
    fadd.s ft1, ft4, ft4          // -2.0f
    vfmv.s.f v16, ft1
    CHK32 v16, 0, 0xc0000000
    fcvt.d.s ft1, ft4             // -1.0 (a double)
    vfmv.v.f v16, ft1
    CHK32 v16, 0, CNAN
    fcvt.s.w ft1, t0              // 14.0f
    vfadd.vf v16, v8, ft1
    CHK32 v16, 0, 0x41700000      // 1 + 14

    // 15: vtype changes right before a .vf.
    li t0, 15
    vsetvli a0, x0, e64, m1, tu, mu
    vfmv.v.f v16, ft3
    CHK64 v16, 0, UNBOXED
    vsetvli a0, x0, e32, m1, tu, mu
    vfmv.v.f v16, ft3
    CHK32 v16, 0, CNAN
    vsetivli a0, 1, e64, m1, tu, mu
    vfmv.s.f v16, ft3
    CHK64 v16, 0, UNBOXED
    li a1, 0x10                   // e32 m1
    li a3, 4
    vsetvl a0, a3, a1
    vfmv.s.f v16, ft3
    CHK32 v16, 0, CNAN

    // 16: scalar F instructions are unaffected: FMV.X.W and FSW
    // move the raw low word, arithmetic sees the canonical NaN.
    li t0, 16
    csrw fflags, x0
    fmv.x.w a0, ft3
    li a2, 0x3f800000
    bne a0, a2, fail
    la a1, dout
    fsw ft3, 0(a1)
    lwu a0, 0(a1)
    bne a0, a2, fail
    fadd.s ft1, ft3, ft4
    fmv.x.d a0, ft1
    li a2, 0xffffffff7fc00000
    bne a0, a2, fail
    fclass.s a0, ft3
    li a2, 0x200                  // quiet NaN
    bne a0, a2, fail
    fcvt.d.s ft1, ft3
    fmv.x.d a0, ft1
    li a2, DNAN
    bne a0, a2, fail
    feq.s a0, ft3, ft3
    bnez a0, fail
    CHKFLAGS 0

    // 17: FP at SEW=16 and SEW=8 is reserved: every .vf class
    // and vfmv.f.s trap.
    li t0, 17
    vsetvli a0, x0, e16, m1, tu, mu
    TRAPS vfmv.v.f v16, ft3
    TRAPS vfmv.s.f v16, ft3
    TRAPS vfmerge.vfm v16, v8, ft3, v0
    TRAPS vfslide1up.vf v16, v8, ft3
    TRAPS vfslide1down.vf v16, v8, ft3
    TRAPS vfadd.vf v16, v8, ft3
    TRAPS vfsgnj.vf v16, v8, ft3
    TRAPS vmfeq.vf v4, v8, ft3
    TRAPS vfmacc.vf v16, ft3, v8
    TRAPS vfwadd.vf v16, v8, ft3
    TRAPS vfwadd.wf v16, v24, ft3
    TRAPS vfmv.f.s ft1, v8
    vsetvli a0, x0, e8, m1, tu, mu
    TRAPS vfmv.v.f v16, ft3
    TRAPS vfmv.s.f v16, ft3
    TRAPS vfslide1down.vf v16, v8, ft3
    TRAPS vfadd.vf v16, v8, ft3
    TRAPS vfwmul.vf v16, v8, ft3

    // 18: widening .vf is reserved at SEW=64 and at LMUL=8.
    li t0, 18
    vsetvli a0, x0, e64, m1, tu, mu
    TRAPS vfwadd.vf v16, v8, ft3
    TRAPS vfwmacc.vf v16, ft3, v8
    vsetvli a0, x0, e32, m8, tu, mu
    TRAPS vfwsub.wf v16, v24, ft3
    TRAPS vfwmul.vf v16, v8, ft3

    // 19: vl=0: vfmv.f.s still writes f[rd] (NaN-boxed),
    // vfmv.s.f updates nothing.
    li t0, 19
    vsetivli a0, 4, e32, m1, tu, mu
    la a1, sbuf
    vle32.v v8, (a1)
    vmv.v.i v16, 0
    vsetivli a0, 0, e32, m1, tu, mu
    fmv.d.x ft1, x0
    vfmv.f.s ft1, v8
    fmv.x.d a0, ft1
    li a2, 0xffffffff3f800000
    bne a0, a2, fail
    vfmv.s.f v16, ft4
    vsetivli a0, 4, e32, m1, tu, mu
    CHK32 v16, 0, 0

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
    .align 3
sbuf:   .word 0x3f800000, 0xc0000000, 0x40400000, 0xc0800000
    .align 3
dbuf:   .dword 0x3ff8000000000000, 0x4004000000000000
        .dword 0xbfe0000000000000, 0x4010000000000000
        .skip 96
    .align 3
    .skip 512
stack_top:
    .skip 512
trap_stack_top:
