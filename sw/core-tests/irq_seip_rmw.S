// Regression (found by the soc_tb Linux boot, issue #21): a
// CSRRS/CSRRC on mip must not latch the external interrupt pins
// into the software-writable SEIP/STIP bits. The privileged spec
// says the read-modify-write uses only the software SEIP bit;
// reads (the rd value, csrr) still see pin | software bit.
//
// Before the fix, OpenSBI's `csr_set/csr_clear(mip, MIP_STIP)`
// on a timer event while the PLIC S-context line was high stuck
// mip.SEIP at 1 forever: Linux then took S-external interrupts
// back to back, every PLIC claim returned 0, and the boot
// livelocked right after /init started writing to the tty.
//
// core_tb drives the IRQ pins from stores to IRQ_CTL (mip bit
// layout). Handled mode; exit store 0 = pass, t0 = failing
// subtest number. Any trap is a failure.
    .option norvc
    .equ EXIT,    0x10000000
    .equ IRQ_CTL, 0x10000008
    .equ SEIP,    0x200
    .equ STIP,    0x020
    .text
    .globl _start
_start:
    la t1, unexpected_trap
    csrw mtvec, t1
    li s0, IRQ_CTL
    li s1, SEIP
    li s2, STIP

    // 1: pin high is visible in mip.
    li t0, 1
    sd s1, 0(s0)             // irq_s_ext_i = 1
    call settle
    csrr t2, mip
    and t2, t2, s1
    beqz t2, fail

    // 2: RMW on another mip bit (OpenSBI's STIP set/clear)
    //    while the pin is high; rd of csrrs sees the pin.
    li t0, 2
    csrrs t2, mip, s2        // set STIP
    and t2, t2, s1
    beqz t2, fail
    csrc mip, s2             // clear STIP
    li t0, 3                 // STIP cleared again
    csrr t2, mip
    and t2, t2, s2
    bnez t2, fail

    // 4: drop the pin; SEIP must follow (no latched SW bit).
    li t0, 4
    sd x0, 0(s0)
    call settle
    csrr t2, mip
    and t2, t2, s1
    bnez t2, fail

    // 5: same for STIP with the S-timer pin high during a
    //    SEIP RMW.
    li t0, 5
    sd s2, 0(s0)             // irq_s_timer_i = 1
    call settle
    csrs mip, s1
    csrc mip, s1
    sd x0, 0(s0)
    call settle
    csrr t2, mip
    and t2, t2, s2
    bnez t2, fail

    // 6: the software SEIP bit itself still works, and a
    //    csrc while the pin is high clears it.
    li t0, 6
    csrs mip, s1
    csrr t2, mip
    and t2, t2, s1
    beqz t2, fail
    li t0, 7
    sd s1, 0(s0)             // pin high
    call settle
    csrc mip, s1             // clears the SW bit only
    csrr t2, mip             // pin keeps it visible
    and t2, t2, s1
    beqz t2, fail
    li t0, 8
    sd x0, 0(s0)
    call settle
    csrr t2, mip
    and t2, t2, s1
    bnez t2, fail

    // 9: the Linux symptom: after an RMW with the pin high and
    //    the pin dropped, enabling SEIE with MIE=1 must not trap
    //    (SEI is not delegated, so it would trap to M here).
    li t0, 9
    sd s1, 0(s0)
    call settle
    csrs mip, s2
    csrc mip, s2
    sd x0, 0(s0)
    call settle
    csrw mie, s1
    csrsi mstatus, 0x8       // MIE
    nop
    nop
    nop
    nop
    csrci mstatus, 0x8
    csrw mie, x0
    j pass

// Lets an IRQ_CTL store reach the pins before the next CSR read.
settle:
    nop
    nop
    nop
    nop
    nop
    nop
    ret

unexpected_trap:
    addi t0, t0, 100         // 100 + subtest that trapped
    j fail

pass:
    li t1, EXIT
    sd x0, 0(t1)
1:  j 1b
fail:
    li t1, EXIT
    sd t0, 0(t1)
1:  j 1b
