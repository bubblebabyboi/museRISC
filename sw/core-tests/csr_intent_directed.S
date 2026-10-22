// Read-only CSR write attempts next to stalls and older traps (#53
// review). With FPGA_TIMING the read-only check uses the static write
// intent (CSRRW/CSRRWI, or a nonzero rs1/uimm), not the committed
// write enable, so the check can see the attempt while EX is held
// (older access parked in MEM, vector load/store sequencing) or while
// an older instruction is about to trap. Checks: which instruction
// traps (mcause/mepc), that read-only accesses without write intent
// stay legal, and that the M/FP op and vector load around the
// attempt neither run early nor get lost.
// t0 = test number; exit store 0 = pass.
    .option arch, +v
    .option norvc
    .text
    .globl _start
.equ EXIT, 0x10000000
.macro EXPECT cause, label
    la t2, m_cause
    ld t1, 0(t2)
    li t3, \cause
    bne t1, t3, fail
    sd x0, 0(t2)
    ld t1, 8(t2)
    la t3, \label
    bne t1, t3, fail
.endm
.macro NOTRAP
    la t2, m_cause
    ld t1, 0(t2)
    bnez t1, fail
.endm
_start:
    la sp, stack_top
    la t1, handler
    csrw mtvec, t1
    li t1, (1 << 9) | (1 << 13)   // VS, FS = Initial
    csrs mstatus, t1
    // 1: reads without write intent are legal; any intent traps.
    li t0, 1
    csrrs a0, cycle, x0
    csrrc a0, instret, x0
    csrrsi a0, time, 0
    csrrci a0, cycle, 0
    NOTRAP
i1: csrrwi a0, cycle, 0
    EXPECT 2, i1
i2: csrrw x0, instret, x0
    EXPECT 2, i2
i3: csrrsi a0, cycle, 1
    EXPECT 2, i3
    // 2: behind a load that misses the D$ (MEM parked).
    li t0, 2
    la a1, far
    li a3, 5
i4: ld a2, 0(a1)
i5: csrw cycle, a3
    EXPECT 2, i5
    li t3, 0x1234
    bne a2, t3, fail
    // 3: an older load fault wins over the younger attempt.
    li t0, 3
    li a1, 1
    slli a1, a1, 60               // PA >= 2^56: access fault
i6: ld a2, 0(a1)
i7: csrw cycle, a3
    EXPECT 5, i6
    // (the attempt itself was skipped by the handler; nothing else)
    NOTRAP
    // 4: M and FP ops right after the attempt do not run.
    li t0, 4
    li a4, 77
    li a5, 7
    fmv.d.x f2, a4
    fmv.d.x f3, a5
    csrw fflags, x0
i8: csrw instret, a3
    div a4, a4, a5                // skipped? no: runs after the handler
    EXPECT 2, i8
    li t3, 11
    bne a4, t3, fail              // exactly one divide
    la a1, far
    li a6, 3
i9: ld a2, 0(a1)
i10: csrw cycle, a3
    mul a6, a6, a6
    EXPECT 2, i10
    li t3, 9
    bne a6, t3, fail
    li a4, 1
    fcvt.d.l f2, a4
    li a4, 3
    fcvt.d.l f3, a4
    csrw fflags, x0
i11: csrrs a0, cycle, a3
    fdiv.d f4, f2, f3             // inexact: NX after the handler
    EXPECT 2, i11
    csrr a0, fflags
    li t3, 1
    bne a0, t3, fail
    // 5: next to a vector load in MEM (EX held until it ends).
    li t0, 5
    vsetivli x0, 8, e64, m1, ta, ma
    la a1, vdata
    vmv.v.i v1, 0
    vle64.v v1, (a1)
i12: csrw cycle, a3
    EXPECT 2, i12
    vmv.x.s a0, v1
    li t3, 0x100
    bne a0, t3, fail
    vslidedown.vi v2, v1, 7
    vmv.x.s a0, v2
    li t3, 0x107
    bne a0, t3, fail
    // vector load that faults, then the attempt: the load's fault
    li a1, 1
    slli a1, a1, 60
i13: vle64.v v1, (a1)
i14: csrw cycle, a3
    EXPECT 5, i13
    csrw vstart, x0
pass:
    li t1, EXIT
    sd x0, 0(t1)
1:  j 1b
fail:
    li t1, EXIT
    sd t0, 0(t1)
1:  j 1b

// record mcause/mepc of the first trap since the last check and
// skip the instruction (test 3: the older load fault must be the
// first trap, before the younger attempt's)
handler:
    csrr t1, mcause
    bltz t1, 2f
    la t2, m_cause
    ld t3, 0(t2)
    bnez t3, 1f                   // keep the first trap of a pair
    sd t1, 0(t2)
    csrr t1, mepc
    sd t1, 8(t2)
1:  csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
2:  mret

    .data
    .align 6
vdata: .dword 0x100, 0x101, 0x102, 0x103, 0x104, 0x105, 0x106, 0x107
    .align 12
far:   .dword 0x1234
    .skip 512
stack_top:
m_cause: .dword 0, 0
