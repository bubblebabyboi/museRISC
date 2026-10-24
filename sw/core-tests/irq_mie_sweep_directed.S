// Machine timer interrupt against a short MIE window (#53 review,
// precise interrupts). Run with --irq-timer-after N over a range of
// N: the loop opens the window (csrsi mstatus.MIE), runs one
// instruction, closes it (csrci) and runs a few more, so the timer
// line rises at every pipeline position of the window over the sweep.
// The interrupt may only be taken while MIE = 1:
//  1: mcause = machine timer interrupt.
//  2: mstatus.MPIE = 1 at entry (taken with MIE set).
//  3: mepc = the instruction after the csrsi or the csrci itself (the
//     only instructions that start while MIE = 1).
//  4: exactly one interrupt in the run (core_tb drops the line once
//     an interrupt trap is taken).
// t0 = test number; exit store 0 = pass.
    .option norvc
    .text
    .globl _start
.equ EXIT, 0x10000000

_start:
    la t1, handler
    csrw mtvec, t1
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1
    csrci mstatus, 8
    li t1, 0x80
    csrw mie, t1                 // MTIE only
    li s0, 4000
    li s1, 0
loop:
    csrsi mstatus, 8
w_a:
    addi s2, s2, 1
w_b:
    csrci mstatus, 8
    addi s3, s3, 1
    addi s4, s4, 1
    addi s0, s0, -1
    bnez s0, loop
    li t0, 4
    li t1, 1
    bne s1, t1, fail
    li t1, EXIT
    sd x0, 0(t1)
1:  j 1b

    .balign 64
handler:
    li t0, 1
    csrr t2, mcause
    li t3, 1
    slli t3, t3, 63
    ori t3, t3, 7
    bne t2, t3, fail
    li t0, 2
    csrr t2, mstatus
    andi t2, t2, 0x80
    beqz t2, fail
    li t0, 3
    csrr t2, mepc
    la t3, w_a
    beq t2, t3, 1f
    la t3, w_b
    bne t2, t3, fail
1:  addi s1, s1, 1
    mret
fail:
    la t1, dbg
    csrr t2, mepc
    sd t2, 0(t1)
    li t1, EXIT
    sd t0, 0(t1)
1:  j 1b

    .data
    .align 3
dbg: .quad 0
