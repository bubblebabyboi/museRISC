// Interrupt trap conditions right after a CSR write (#53 review,
// precise interrupts). Priv spec 3.1.9: the conditions for an
// interrupt trap "must also be evaluated immediately following ...
// an explicit write to a CSR on which these interrupt trap conditions
// expressly depend (including mip, mie, mstatus, and mideleg)".
// Each case makes an interrupt pending and enabled with one CSR write
// and (cases 1-3, 5-6) disables it again with the very next one:
//  1: M, csrsi mip.SSIP then csrci mstatus.MIE: the interrupt must be
//     taken with MIE = 1 (mstatus.MPIE = 1 in the handler), i.e.
//     never after the csrci retired.
//  2: the same case: mepc = the csrci (taken right after the csrsi).
//  3: M, SSIP pending, MIE = 1, csrsi mie.SSIE then csrci mie.SSIE:
//     mepc = the csrci.
//  4: M, SSIP pending and enabled in mie, csrsi mstatus.MIE then an
//     addi: mepc = the addi, which has not run (s5 = 0 at entry).
//  5: S (SSI delegated), csrsi sip.SSIP then csrci sstatus.SIE: SPIE
//     = 1 in the handler.
//  6: the same case: sepc = the csrci.
//  7: one interrupt per case (4 in all).
// Exit value: bit i set = check i failed (0 = pass); 99 = an
// unexpected trap.
    .option norvc
    .text
    .globl _start
.equ EXIT, 0x10000000

// Set bit \bit of s11 when \br \ra, \rb branches.
.macro FAILIF br, ra, rb, bit
    \br \ra, \rb, 1f
    j 2f
1:  li t4, 1 << \bit
    or s11, s11, t4
2:
.endm

_start:
    la sp, stack_top
    la t1, handler_m
    csrw mtvec, t1
    la t1, handler_s
    csrw stvec, t1
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1
    csrw mideleg, x0
    csrw mie, x0
    csrci mip, 2
    li t1, 2
    csrw mie, t1                 // mie.SSIE only
    li s1, 0                     // interrupts taken (all cases)
    li s11, 0                    // failed checks

    // Cases 1-2.
    csrsi mstatus, 8             // MIE = 1, nothing pending
    li s5, 0
    csrsi mip, 2                 // SSIP pending: taken here
c12_n1:
    csrci mstatus, 8             // MIE = 0
    addi s5, s5, 1
    la t1, rec_m
    ld t2, 8(t1)                 // mstatus at entry
    andi t2, t2, 0x80            // MPIE
    FAILIF beq, t2, x0, 1
    ld t2, 0(t1)                 // mepc
    la t3, c12_n1
    FAILIF bne, t2, t3, 2

    // Case 3: SSIP pending, MIE = 1, enable then disable in mie.
    csrw mie, x0
    csrsi mip, 2
    csrsi mstatus, 8
    csrsi mie, 2                 // enabled: taken here
c3_n1:
    csrci mie, 2
    addi s5, s5, 1
    csrci mstatus, 8
    csrci mip, 2
    la t1, rec_m
    ld t2, 0(t1)
    la t3, c3_n1
    FAILIF bne, t2, t3, 3

    // Case 4: SSIP pending and enabled, then MIE set.
    li t1, 2
    csrw mie, t1
    csrsi mip, 2
    li s5, 0
    csrsi mstatus, 8             // taken here
c4_n1:
    addi s5, s5, 1
    csrci mstatus, 8
    csrci mip, 2
    la t1, rec_m
    ld t2, 0(t1)
    la t3, c4_n1
    FAILIF bne, t2, t3, 4
    ld t2, 24(t1)                // s5 at entry
    FAILIF bne, t2, x0, 4

    // Cases 5-6 in S: SSI delegated, sie.SSIE, SIE toggled.
    li t1, 2
    csrw mideleg, t1
    csrw mie, t1
    la t1, s_code
    csrw mepc, t1
    li t1, (3 << 11)
    csrc mstatus, t1
    li t1, (1 << 11)             // MPP = S
    csrs mstatus, t1
    mret

s_code:
    csrsi sstatus, 2             // SIE = 1
    li s5, 0
    csrsi sip, 2                 // pending: taken here
c56_n1:
    csrci sstatus, 2             // SIE = 0
    addi s5, s5, 1
    csrci sip, 2
    la t1, rec_s
    ld t2, 8(t1)                 // sstatus at entry
    andi t2, t2, 0x20            // SPIE
    FAILIF beq, t2, x0, 5
    ld t2, 0(t1)
    la t3, c56_n1
    FAILIF bne, t2, t3, 6
    li t1, 4
    FAILIF bne, s1, t1, 7
    li t1, EXIT
    sd s11, 0(t1)
1:  j 1b

    .balign 64
handler_m:
    csrr t2, mcause
    li t3, 1
    slli t3, t3, 63
    ori t3, t3, 1
    bne t2, t3, unexpected
    la t3, rec_m
    csrr t2, mepc
    sd t2, 0(t3)
    csrr t2, mstatus
    sd t2, 8(t3)
    csrr t2, mie
    sd t2, 16(t3)
    sd s5, 24(t3)
    addi s1, s1, 1
    csrci mip, 2                 // clear SSIP
    mret

    .balign 64
handler_s:
    csrr t2, scause
    li t3, 1
    slli t3, t3, 63
    ori t3, t3, 1
    bne t2, t3, unexpected
    la t3, rec_s
    csrr t2, sepc
    sd t2, 0(t3)
    csrr t2, sstatus
    sd t2, 8(t3)
    sd s5, 24(t3)
    addi s1, s1, 1
    csrci sip, 2
    sret

unexpected:
    li t1, EXIT
    li t2, 99
    sd t2, 0(t1)
1:  j 1b

    .data
    .align 3
rec_m: .quad 0, 0, 0, 0
rec_s: .quad 0, 0, 0, 0
    .align 4
stack: .skip 512
stack_top:
