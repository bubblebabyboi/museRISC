// Extension of irq_seip_rmw (issue #21 Linux bring-up):
// CSRRSI/CSRRCI on mip with both S pins high, CSRRW on mip with
// the pin high, and the sip alias from S-mode. IRQ_CTL drives the
// core_tb interrupt pins; exit store 0 = pass, t0 = subtest.
    .option norvc
    .equ EXIT,    0x10000000
    .equ IRQ_CTL, 0x10000008
    .text
    .globl _start
_start:
    la t1, trap
    csrw mtvec, t1
    li s0, IRQ_CTL
    li s1, 0x200            // SEIP
    li s2, 0x020            // STIP
    li s3, 0x220            // SEIP|STIP pins

    // 1-2: csrrsi/csrrci on mip with both S pins high
    li t0, 1
    sd s3, 0(s0)
    call settle
    csrrsi t2, mip, 2       // set SSIP; rd must show pins
    and t3, t2, s3
    bne t3, s3, fail
    li t0, 2
    csrrci t2, mip, 2
    and t3, t2, s3
    bne t3, s3, fail
    andi t3, t2, 2          // SSIP was set by csrrsi
    beqz t3, fail
    li t0, 3
    sd x0, 0(s0)
    call settle
    csrr t2, mip
    and t3, t2, s3
    bnez t3, fail           // neither SEIP nor STIP latched
    andi t3, t2, 2
    bnez t3, fail           // SSIP cleared

    // 4: csrrw mip: sets the SW bits as written, rd shows pins
    li t0, 4
    sd s1, 0(s0)
    call settle
    csrrw t2, mip, x0
    and t3, t2, s1
    beqz t3, fail
    sd x0, 0(s0)
    call settle
    csrr t2, mip
    and t3, t2, s1
    bnez t3, fail
    li t0, 5
    csrw mip, s1            // SW SEIP = 1 with pin low
    csrr t2, mip
    and t3, t2, s1
    beqz t3, fail
    csrw mip, x0
    csrr t2, mip
    and t3, t2, s1
    bnez t3, fail

    // 6+: sip from S-mode with pins high
    li t0, 6
    li t1, -1
    csrw pmpaddr0, t1
    li t1, 0x1f
    csrw pmpcfg0, t1
    li t1, 0x222
    csrw mideleg, t1
    li t1, 0x1800
    csrc mstatus, t1
    li t1, 0x0800           // MPP = S
    csrs mstatus, t1
    la t1, smode
    csrw mepc, t1
    sd s3, 0(s0)
    call settle
    mret
smode:
    li t0, 7
    csrr t2, sip
    and t3, t2, s3
    bne t3, s3, fail_s      // sip shows both pins
    li t0, 8
    li t1, 2
    csrrs t2, sip, t1
    and t3, t2, s3
    bne t3, s3, fail_s
    csrrc t2, sip, t1
    csrrsi t2, sip, 2
    and t3, t2, s3
    bne t3, s3, fail_s
    csrrci t2, sip, 2
    li t0, 9
    ecall                   // back to M (cause 9)
back_in_m:
    li t0, 10
    sd x0, 0(s0)
    call settle
    csrr t2, mip
    and t3, t2, s3
    bnez t3, fail
    andi t3, t2, 2
    bnez t3, fail
    j pass

settle:
    nop; nop; nop; nop; nop; nop
    ret
trap:
    csrr t1, mcause
    li t2, 9
    bne t1, t2, bad
    la t1, back_in_m
    jr t1
bad:
    addi t0, t0, 100
    j fail
fail_s:
    j fail
pass:
    li t1, EXIT
    sd x0, 0(t1)
1:  j 1b
fail:
    li t1, EXIT
    sd t0, 0(t1)
1:  j 1b
