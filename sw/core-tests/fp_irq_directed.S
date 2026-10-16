// Machine timer interrupt arriving while multi-cycle FP ops
// (fdiv/fsqrt/FMA) are in flight (fpu-multicycle). Run by
// `make core-test` once per IRQ offset over a window wider than
// the longest FP op, so the interrupt lands in every phase of
// an in-flight divide/sqrt/FMA. The interrupt is taken
// precisely between instructions (the held op completes first),
// and the interrupted chain must produce exactly the results
// and flags of a reference run of the same chain with
// interrupts disabled.
// Convention: t0 = test number, exit store 0 = pass.
// s9 = interrupt count, s10 = mcause, s11 = mepc (handler only
// touches these integer registers: no FP state).
    .option norvc
    .text
    .globl _start
_start:
    la t1, handler
    csrw mtvec, t1
    li t1, (1 << 13)              // FS=Initial
    csrs mstatus, t1
    li s9, 0
    li a0, (1 << 7)               // MTIE
    csrs mie, a0
    csrsi mstatus, 0x8            // MIE: the harness raises the IRQ
    la a4, run_out
    jal ra, chain                 // interrupted run
    csrci mstatus, 0x8
    csrw mie, x0
    la a4, ref_out
    jal ra, chain                 // reference run, no interrupts

    // ---- 1: exactly one machine-timer interrupt, taken inside
    //      the chain.
    li t0, 1
    li a2, 1
    bne s9, a2, fail
    li a2, 0x8000000000000007
    bne s10, a2, fail
    la a2, chain
    bltu s11, a2, fail
    la a2, chain_end
    bgeu s11, a2, fail

    // ---- 2: interrupted results == reference results.
    li t0, 2
    la a0, run_out
    la a1, ref_out
    li a3, 16
1:  ld a2, 0(a0)
    ld a5, 0(a1)
    bne a2, a5, fail
    addi a0, a0, 8
    addi a1, a1, 8
    addi a3, a3, -1
    bnez a3, 1b

pass:
    li t1, 0x10000000
    sd x0, 0(t1)
1:  j 1b
fail:
    li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b

    .balign 4
handler:
    csrr s10, mcause
    csrr s11, mepc
    addi s9, s9, 1
    mret

// Dependent FP chain dominated by long ops; results and the
// accrued flags are stored at a4.
chain:
    fsflags zero
    li a0, 0x4008000000000000     // 3.0
    fmv.d.x f1, a0
    li a0, 0x401C000000000000     // 7.0
    fmv.d.x f2, a0
    li a0, 0x3FE0000000000000     // 0.5
    fmv.d.x f4, a0
    li a0, 0x40400000             // 3.0f
    fmv.w.x f10, a0
    li a5, 0
    .rept 12
    fdiv.d  f1, f1, f2            // 32 cycles
    fsqrt.d f3, f1                // 32 cycles
    fmadd.d f1, f3, f2, f4        // 7 cycles
    fdiv.s  f10, f10, f10         // 17 cycles
    fsqrt.s f11, f10
    fcvt.w.d a6, f1               // 3 cycles
    add a5, a5, a6
    fadd.d  f2, f2, f4            // 5 cycles
    .endr
chain_end:
    fsd f1, 0(a4)
    fsd f2, 8(a4)
    fsd f3, 16(a4)
    fsd f4, 24(a4)
    fsd f10, 32(a4)
    fsd f11, 40(a4)
    sd a5, 48(a4)
    frflags a6
    sd a6, 56(a4)
    ret

    .data
    .balign 8
run_out: .skip 128
ref_out: .skip 128
