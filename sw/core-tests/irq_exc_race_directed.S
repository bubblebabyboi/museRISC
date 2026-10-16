// Timer interrupt raised while synchronous exceptions keep firing:
// a run of misaligned loads, each trapping to a handler that skips
// it. `make core-test` raises the machine-timer IRQ at every offset
// over a window that spans several of these traps, so in some runs
// the IRQ becomes pending in the cycles where an older load's
// exception is taken first. The interrupt must still be taken
// exactly once (core_tb clears its IRQ line only on an interrupt
// trap; it used to clear it on any trap and lose the interrupt).
// Convention: t0 = test number, exit store 0 = pass.
// s8 = exception count, s9 = interrupt count (handler uses t4/t5).
    .option norvc
    .text
    .globl _start
_start:
    la t1, handler
    csrw mtvec, t1
    li s8, 0
    li s9, 0
    li a0, (1 << 7)               // MTIE
    csrs mie, a0
    csrsi mstatus, 0x8            // MIE
    la t6, misaligned
    .rept 12
    ld t3, 1(t6)                  // misaligned: traps, skipped
    addi a1, a1, 1
    .endr
    // Give a late IRQ time to arrive before checking.
    li a2, 200
1:  addi a2, a2, -1
    bnez a2, 1b

    // ---- 1: all 12 exceptions taken.
    li t0, 1
    li a2, 12
    bne s8, a2, fail
    // ---- 2: exactly one interrupt taken.
    li t0, 2
    li a2, 1
    bne s9, a2, fail

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
    csrr t4, mcause
    bltz t4, 1f
    csrr t5, mepc                 // synchronous: skip the faulting load
    addi t5, t5, 4
    csrw mepc, t5
    addi s8, s8, 1
    mret
1:  addi s9, s9, 1
    mret

    .data
    .balign 8
misaligned: .dword 0x1122334455667788, 0
