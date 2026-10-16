// Traps and interrupts around multi-cycle M-unit ops
// (muldiv-multicycle). Run by `make core-test` once per timer-IRQ
// offset over a window wider than the longest divide (a full 64-bit
// quotient holds EX for 35 cycles), so the interrupt arrives in
// every cycle of an in-flight divide and of the multiplies around
// it. The interrupt is taken precisely between instructions (the
// held op completes first). Each chain iteration also starts a long
// divide right behind a misaligned load: the load's exception kills
// the divide while it is in flight (kill_i), the handler skips the
// load, and the divide re-executes from scratch. The interrupted
// chain must produce exactly the results of a reference run with
// interrupts disabled (which takes the same load exceptions).
// Convention: t0 = test number, exit store 0 = pass.
// s8 = exception count, s9 = interrupt count, s10 = mcause,
// s11 = mepc (handler touches only t4/t5 and these).
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
    csrsi mstatus, 0x8            // MIE: the harness raises the IRQ
    la a7, run_out
    jal ra, chain                 // interrupted run
    csrci mstatus, 0x8
    csrw mie, x0
    la a7, ref_out
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

    // ---- 2: every misaligned load trapped once per run (2 x 8).
    li t0, 2
    li a2, 16
    bne s8, a2, fail

    // ---- 3: interrupted results == reference results.
    li t0, 3
    la a0, run_out
    la a1, ref_out
    li a3, 8
1:  ld a2, 0(a0)
    ld a5, 0(a1)
    bne a2, a5, fail
    addi a0, a0, 8
    addi a1, a1, 8
    addi a3, a3, -1
    bnez a3, 1b

    // ---- 4: spot-check the reference against known values
    //      (guards against both runs being wrong the same way).
    li t0, 4
    la a1, ref_out
    ld a2, 8(a1)                  // last divu: (2^64-1) / 17
    li a5, 0x0f0f0f0f0f0f0f0f
    bne a2, a5, fail
    ld a2, 16(a1)                 // last div: (2^63-1) / 17
    li a5, 0x0787878787878787
    bne a2, a5, fail

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
1:  mv s10, t4
    csrr s11, mepc
    addi s9, s9, 1
    mret

// Dependent integer chain dominated by full-length divides; results
// are stored at a7.
chain:
    li a0, -1                     // 2^64-1
    li a2, 0x7fffffffffffffff
    li a1, 3
    li s0, 0
    la t6, misaligned
    .rept 8
    ld t3, 1(t6)                  // misaligned: traps, kills the divu
    divu a3, a0, a1               // 64-bit quotient: 35 EX cycles
    add s0, s0, a3
    div a4, a2, a1                // 63-bit quotient
    mulh a5, a4, a3
    xor s0, s0, a5
    mul a6, a3, a4
    remu t3, a6, a1
    add s0, s0, t3
    divw t3, s0, a1
    add s0, s0, t3
    addi a1, a1, 2
    .endr
chain_end:
    sd s0, 0(a7)
    sd a3, 8(a7)
    sd a4, 16(a7)
    sd a5, 24(a7)
    sd a6, 32(a7)
    sd a1, 40(a7)
    sd t3, 48(a7)
    sd x0, 56(a7)
    ret

    .data
    .balign 8
misaligned: .dword 0x1122334455667788, 0
run_out: .skip 64
ref_out: .skip 64
